# Proyecto ListMonk2

## 1. Objetivo y alcance
ListMonk2 es una implantación de **Listmonk** desplegada en Kubernetes mediante **GitOps (Argo CD)**. El objetivo del proyecto es disponer de un sistema de email marketing/autogestión de listas con:

- Despliegue reproducible (declarativo) con Kustomize.
- Gestión de secretos con Sealed Secrets.
- Canal de prueba de correo con Mailpit (opcional, para entornos de desarrollo).
- CI/CD para construir la imagen de la aplicación y publicarla en GHCR, con escaneo de vulnerabilidades.

Este documento describe la arquitectura, el proceso de instalación y la operativa para validar que el sistema funciona.

## 2. Arquitectura

### 2.1 Componentes

**Aplicación (Listmonk)**
- Se despliega como workload en el namespace `listmonk`.
- La imagen de la aplicación se publica en GHCR y se referencia desde los manifiestos Kustomize (campo `images`).

**Base de datos (PostgreSQL)**
- Listmonk requiere PostgreSQL. Puede ser un servicio gestionado (recomendado en producción) o un despliegue en el clúster.
- La configuración (host, puerto, nombre de DB, usuario, contraseña) se inyecta por variables de entorno.

**Argo CD (GitOps)**
- Argo CD aplica el estado deseado desde el repositorio GitOps.
- El flujo habitual es: actualizar manifiestos → commit → Argo CD sincroniza.

**Sealed Secrets**
- Los secretos se guardan en el repo GitOps como `SealedSecret` y se desencriptan en el clúster por el controller.
- En el repo hay, como mínimo, un `sealedsecret-listmonk.yaml` para credenciales/variables de Listmonk.

**Mailpit (opcional, recomendado en local/dev)**
- Se despliega en el namespace `infra`.
- Expone UI (HTTP) y SMTP.
- Se protegen accesos por NetworkPolicies (default-deny y allowlist desde `listmonk`).

### 2.2 Namespaces recomendados
- `argocd`: Argo CD.
- `listmonk`: aplicación y recursos relacionados.
- `infra`: servicios de apoyo (por ejemplo Mailpit).
- `logging`: observabilidad si aplica (por ejemplo promtail), según overlays del repositorio.

## 3. Requisitos

### 3.1 Herramientas
- `kubectl` (compatible con la versión del clúster).
- `kustomize`.
- Acceso al repositorio GitOps y permisos para hacer push.
- Acceso al clúster (kubeconfig).

### 3.2 Requisitos del clúster
- Un Ingress Controller (si se va a exponer Listmonk externamente).
- Un StorageClass por defecto (si se despliegan componentes con PVC).
- Sealed Secrets controller instalado si se usan `SealedSecret`.
- (Opcional) Políticas de red activas si se usan NetworkPolicies.

## 4. Repositorios y responsabilidades

El proyecto se organiza en **tres repositorios** con responsabilidades separadas:

**listmonk2-app**
Repositorio de aplicación. Construye y publica la imagen de Listmonk en GHCR y ejecuta la cadena de CI (lint, Trivy y firma con Cosign). Como parte del pipeline, actualiza el tag de la imagen en el repositorio GitOps.

**listmonk2-gitops**
Repositorio GitOps. Contiene los manifiestos Kubernetes (Kustomize) por entorno y es la fuente de verdad que sincroniza Argo CD.

**listmonk2-infra**
Repositorio de infraestructura. Agrupa el aprovisionamiento y bootstrap del entorno (clúster y/o componentes base), manteniendo esta capa independiente de la aplicación.

### 4.1 Detalle del repositorio listmonk2-app

#### Imagen (Listmonk no-root)
El pipeline construye una imagen derivada de `listmonk/listmonk:v6.0.0` ejecutándose como **usuario no-root**. Incluye un `entrypoint.sh` que genera la configuración en tiempo de arranque en `/tmp/config.toml` (directorio escribible; el rootfs puede ser de solo lectura).

#### Publicación en GHCR
La imagen resultante se publica en **GitHub Container Registry (GHCR)**. El despliegue en Kubernetes referencia la imagen y el tag definidos en `listmonk2-gitops`.

#### Variables de ejecución (runtime)
La aplicación consume como mínimo las siguientes variables de entorno:

- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`
- `LISTMONK_ADMIN_USER`, `LISTMONK_ADMIN_PASSWORD`
- `LISTMONK_APP_ADDRESS` (por defecto `0.0.0.0:9000`)
- `LISTMONK_APP_ROOT_URL` (por ejemplo `http://listmonk.local/`)

#### Build local
Para construir localmente:

- `docker build -t ghcr.io/<ORG>/listmonk2:dev .`

#### CI (GitHub Actions)
El flujo de CI del repositorio `listmonk2-app` realiza, como mínimo:

- Lint del repositorio (por ejemplo `shellcheck` y `hadolint`).
- Análisis de vulnerabilidades con **Trivy**:
  - Publica resultados en **SARIF** para Code Scanning.
  - Genera un reporte adicional (por ejemplo en Job Summary y/o artefacto) en modo informativo.
- Firma de la imagen con **Cosign** en modo **keyless** (OIDC), firmando por **digest** y usando referrers OCI 1.1.
- Actualización automática del repositorio `listmonk2-gitops`:
  - Edita el `kustomization.yaml` del overlay correspondiente con `kustomize edit set image`.
  - Hace commit y push al repositorio GitOps.

Para permitir la actualización automática de GitOps, el pipeline requiere un secreto `GITOPS_TOKEN` con permisos de lectura/escritura sobre el repositorio `listmonk2-gitops`.

#### Verificación de firma (Cosign)
Para verificar localmente una imagen firmada (Cosign v2):

```bash
export COSIGN_REGISTRY_REFERRERS_MODE=oci-1-1
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/<ORG>/listmonk2-app/.github/workflows/ci\.yml@.*' \
  ghcr.io/<ORG>/listmonk2@sha256:<DIGEST>
```

### 4.2 Detalle del repositorio listmonk2-infra

#### Propósito
El repositorio `listmonk2-infra` realiza el **bootstrap local (k3s)** para entornos `local/dev`, instalando la capa de infraestructura y observabilidad con **Terraform** usando el provider de **Helm**.

La regla operativa del proyecto es:

- **Infra/observabilidad**: se gestiona únicamente en `listmonk2-infra`.
- **Aplicaciones** (Listmonk2 y recursos de despliegue asociados): se gestionan en `listmonk2-gitops`.

#### Componentes instalados
El bootstrap instala, como mínimo:

- **Argo CD** (GitOps).
- **Argo Rollouts** (estrategias Blue/Green).
- **Sealed Secrets**.
- **Observabilidad**:
  - `kube-prometheus-stack` (Prometheus, Grafana, Alertmanager).
  - Loki.
  - Promtail.
- **Mailpit** (testing SMTP) en namespace `infra`, con NetworkPolicies.

#### Requisitos
- Ubuntu Server 22.04/24.04.
- Paquetes: `curl`, `git`, `unzip`.
- `kubectl`.
- `terraform` (Helm CLI es opcional).

#### Instalación de k3s (un nodo)
Instalar k3s y configurar el kubeconfig para el usuario:

```bash
curl -sfL https://get.k3s.io | sh -

sudo mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

kubectl get nodes
```

Nota: k3s instala Traefik por defecto. Si se deshabilita, debe instalarse un Ingress Controller alternativo.

#### Variables de Terraform
En `terraform/local/terraform.tfvars` se definen, como mínimo:

- `kubeconfig_path`: ruta al kubeconfig.
- `gitops_repo_url`: URL del repositorio GitOps (GitHub).
- `gitops_repo_path`: path dentro del repo GitOps (por ejemplo `apps/listmonk/overlays/local`).
- `domain_base`: dominio local base (por ejemplo `local`). Se usa para exponer servicios como `argocd.<domain_base>`, `grafana.<domain_base>`, `prometheus.<domain_base>`, `listmonk.<domain_base>` y el endpoint de preview `preview.listmonk.<domain_base>`.

#### Aplicar Terraform
Desde el directorio de entorno local:

```bash
cd terraform/local
terraform init
terraform apply
```

Al finalizar, y dependiendo de `domain_base`, quedarán disponibles al menos:

- Argo CD: `https://argocd.<domain_base>`
- Grafana: `https://grafana.<domain_base>`
- Prometheus: `https://prometheus.<domain_base>`

#### Resolución local de nombres (si no hay DNS)
En la máquina cliente, añadir entradas a `/etc/hosts` apuntando a la IP del servidor donde corre k3s:

```text
<IP_UBUNTU_SERVER> argocd.local grafana.local prometheus.local alertmanager.local loki.local listmonk.local preview.listmonk.local mailpit.local
```

#### Credenciales
Argo CD expone un password inicial en el secreto `argocd-initial-admin-secret`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Grafana: las credenciales y valores relevantes se definen en `terraform/local/values/monitoring-values.yaml`.

#### Bootstrap GitOps
Terraform crea los recursos necesarios en Argo CD (por ejemplo `AppProject` y `Application`) apuntando a `listmonk2-gitops`. A partir de ese momento, los cambios se gestionan mediante push al repositorio GitOps; cuando se incorporan los `SealedSecret` y manifiestos, Argo CD sincroniza y despliega.

#### Mailpit (SMTP testing) y validaciones
Mailpit se instala en el namespace `infra` con Service ClusterIP (UI en 8025 y SMTP en 1025). Se aplican NetworkPolicies de tipo `default-deny` y una allowlist para SMTP desde `listmonk`.

Validaciones recomendadas:

1) Acceder a la UI sin exponer un Ingress:

```bash
kubectl -n infra port-forward svc/mailpit 8025:8025
# http://localhost:8025
```

2) Verificar conectividad SMTP desde `listmonk`:

```bash
kubectl -n listmonk run -it --rm smtp-test \
  --image=busybox:1.36 --restart=Never \
  --labels=app.kubernetes.io/name=listmonk \
  -- sh -lc 'nc -zv -w 2 mailpit.infra.svc.cluster.local 1025'
```

El resultado esperado es que el puerto aparezca como `open`.

#### Verificación de requests/limits
Para auditar requests/limits (CPU/memoria) y el security context, un comando útil es:

```bash
kubectl -n monitoring describe deploy kube-prometheus-stack-grafana \
  | egrep -ni -A6 -B1 'Limits:|Requests:|Security Context'
```

### 4.3 Detalle del repositorio listmonk2-gitops

#### Propósito
El repositorio `listmonk2-gitops` es la **fuente de verdad** de los manifiestos Kubernetes de la aplicación (principalmente en el namespace `listmonk`). Argo CD observa este repositorio y aplica los cambios declarativos.

De forma resumida, este repositorio contiene:

- PostgreSQL (StatefulSet con almacenamiento persistente).
- Listmonk desplegado con Argo Rollouts (estrategia Blue/Green).
- Ingress para el tráfico activo y un endpoint de preview.
- Sealed Secrets para credenciales de base de datos y usuario administrador.

#### Selección de imagen (GHCR)
Para fijar la imagen de la aplicación se usa Kustomize en el overlay local. El punto de edición es:

- `apps/listmonk/overlays/local/kustomization.yaml` → sección `images:`

Ahí se define el `newName` (por ejemplo `ghcr.io/<ORG>/listmonk2`) y el `newTag` (por ejemplo `sha-...` o un `vX.Y.Z`).

En el flujo estándar, este tag se actualiza automáticamente desde el repositorio `listmonk2-app` mediante el job `update_gitops`.

#### Gestión de secretos (Sealed Secrets)
Las credenciales se publican en el repositorio como `SealedSecret` (cifrado), nunca en texto plano.

El procedimiento habitual es:

1) Exportar las variables requeridas (DB y admin).
2) Ejecutar el script de generación.
3) Subir el YAML cifrado al overlay (directorio `sealedsecrets/`).

Ejemplo de variables esperadas por el script:

- `DB_USER`
- `DB_PASSWORD`
- `ADMIN_USER`
- `ADMIN_PASSWORD`

Ejecución del generador:

```bash
./scripts/generate-sealedsecret.sh
```

#### Validación y operación del despliegue
Para comprobar el estado de la aplicación y sus recursos principales:

```bash
kubectl -n listmonk get rollout,svc,ingress,pods
kubectl argo rollouts -n listmonk get rollout listmonk
```

Promoción (Blue/Green):

```bash
kubectl argo rollouts -n listmonk promote listmonk
```

Rollback:

```bash
kubectl argo rollouts -n listmonk undo listmonk
```

#### Mailpit en el overlay local
En el overlay local se incluye una carpeta `mailpit/` que aporta Mailpit y sus NetworkPolicies. En particular:

- `00-namespace-and-default-deny.yaml`
- `10-mailpit.yaml`
- `20-networkpolicy-allow-smtp-from-listmonk.yaml` (la allowlist de SMTP usa el selector `app.kubernetes.io/name: listmonk`)
- `kustomization.yaml`

Esto permite validar que Listmonk puede entregar emails a Mailpit únicamente cuando cumple el selector/namespace esperado.

#### Notas de higiene del repositorio
Si aparecen restos de componentes que deberían vivir en `listmonk2-infra` (por ejemplo `promtail` o `loki-gateway`), deben eliminarse o moverse a `archive/` para mantener el repositorio GitOps centrado en aplicaciones.

### 4.4 Estructura del repositorio listmonk2-gitops

El repositorio GitOps organiza recursos por aplicación y por overlay. Una estructura típica es:

- `apps/listmonk/base`: manifiestos base.
- `apps/listmonk/overlays/<entorno>`: personalizaciones por entorno.
- `apps/listmonk/overlays/<entorno>/sealedsecrets/`: secretos sellados.
- `apps/listmonk/overlays/<entorno>/mailpit`: despliegue opcional de Mailpit.

Ejemplo de `kustomization.yaml` del overlay:
- `resources` incluye `../../base`, el sealed secret y `mailpit`.
- `images` reescribe el nombre/tag de la imagen a desplegar.

## 5. Instalación

### 5.1 Preparación
1. Asegurar conectividad al clúster:
   - `kubectl get nodes`
2. Verificar que Argo CD existe y está operativo (si ya está instalado):
   - `kubectl -n argocd get pods`

Si Argo CD no está instalado, instálalo según el método estándar de tu organización (Helm/Terraform). Una vez esté funcionando, continuar con el flujo GitOps.

### 5.2 Despliegue de la aplicación (GitOps)
1. En el repositorio GitOps, seleccionar el overlay del entorno a desplegar.
2. Ajustar la imagen:
   - `images[].newName`: `ghcr.io/<org>/<repo>`
   - `images[].newTag`: tag del build (por ejemplo `sha-...`).
3. Confirmar que los recursos a aplicar incluyen:
   - Manifiestos base.
   - `SealedSecret` de Listmonk.
   - Dependencias del entorno (por ejemplo Mailpit en dev/local).
4. Ejecutar una validación local:
   - `kustomize build <ruta_overlay> > /tmp/render.yaml`
   - Revisar que el YAML es válido y contiene los recursos esperados.
5. Hacer commit y push.
6. En Argo CD, sincronizar la aplicación (auto o manual) y comprobar el estado.

### 5.3 Base de datos
Configurar la conexión a PostgreSQL mediante variables de entorno o configuración equivalente. Como mínimo:
- `DB_HOST`
- `DB_PORT` (por defecto 5432)
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`

En producción se recomienda usar un servicio gestionado y rotación de credenciales.

### 5.4 Mailpit (entornos de prueba)
Mailpit se despliega en el namespace `infra` y se consume desde Listmonk vía SMTP.

Puntos clave:
- Service ClusterIP expone:
  - UI HTTP en el puerto 8025.
  - SMTP en el puerto 1025.
- NetworkPolicies:
  - `default-deny` en `infra`.
  - allowlist para permitir SMTP desde `listmonk` al puerto 1025, con el selector de pods `app.kubernetes.io/name=listmonk`.

## 6. Validación

### 6.1 Validación del render (antes de aplicar)
1. Renderizar con Kustomize:
   - `kustomize build <ruta_overlay>`
2. Revisar estilo/CI (si aplica):
   - Asegurar que el YAML cumple el formato requerido por el pipeline (por ejemplo longitud de línea, rutas ignoradas).

### 6.2 Validación del despliegue en Kubernetes
1. Estado de recursos:
   - `kubectl -n listmonk get pods -o wide`
   - `kubectl -n listmonk get svc,ingress`
2. Comprobación básica de salud:
   - Port-forward (si no hay Ingress): `kubectl -n listmonk port-forward svc/<svc_listmonk> 9000:9000`
   - Abrir la UI en `http://localhost:9000`.

### 6.3 Validación de Mailpit (si está habilitado)
1. Acceso a la UI:
   - `kubectl -n infra port-forward svc/mailpit 8025:8025`
   - Abrir `http://localhost:8025`.
2. Test de conectividad SMTP desde namespace `listmonk`:
   - Lanzar un pod temporal con la etiqueta de Listmonk:
     - `kubectl -n listmonk run -it --rm smtp-test --image=busybox:1.36 --restart=Never --labels=app.kubernetes.io/name=listmonk -- sh -lc 'nc -zv -w 2 mailpit.infra.svc.cluster.local 1025'`
   - El resultado esperado es que el puerto aparezca como `open`.
3. Configurar SMTP en Listmonk (entorno dev/local):
   - Host: `mailpit.infra.svc.cluster.local`
   - Puerto: `1025`
   - Sin TLS y sin autenticación.
4. Enviar un email de prueba desde Listmonk y confirmar la recepción en la UI de Mailpit.

### 6.4 Validación del pipeline (CI)
Si el pipeline incluye escaneo con Trivy “fail on HIGH/CRITICAL”, el build fallará cuando existan vulnerabilidades severas.

Criterio recomendado:
- Priorizar corrección (actualizar dependencias o base image).
- Si se requiere excepcionar temporalmente, documentar la excepción y acotarla (por CVE y fecha de revisión).

## 7. Operativa

### 7.1 Actualizar versión de la aplicación
1. Construir/publicar nueva imagen (CI/CD).
2. Actualizar `images.newTag` en el overlay correspondiente.
3. Commit y push.
4. Verificar sincronización en Argo CD.
5. Confirmar que los pods ejecutan la nueva imagen:
   - `kubectl -n listmonk get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'`

### 7.2 Rotación de secretos
1. Actualizar secreto origen.
2. Regenerar el `SealedSecret` con la herramienta estándar del proyecto.
3. Commit y push.
4. Validar que el Secret resultante existe en el clúster y que Listmonk reinicia correctamente.

### 7.3 Cambios de configuración
Los cambios de configuración se realizan en manifiestos declarativos (ConfigMap/Secret/Deployment). El mecanismo recomendado es:
- Modificar en Git.
- Revisar con render local.
- Aplicar por Argo CD.

## 8. Resolución de problemas

### 8.1 Argo CD no sincroniza
Comprobar:
- Estado de la aplicación en Argo CD (errores de validación, falta de permisos, recursos en conflicto).
- Eventos del namespace:
  - `kubectl -n listmonk get events --sort-by=.lastTimestamp | tail -n 50`
- Si hay restricciones de recursos, revisar requests/limits y capacidad del nodo.

### 8.2 El pipeline falla en yamllint
- Revisar reglas activas (por ejemplo `line-length`).
- Confirmar rutas ignoradas y ubicación de recursos (por ejemplo secretos sellados en rutas específicas).

### 8.3 El pipeline falla en Trivy
- Identificar el paquete vulnerable y su origen (OS vs librería).
- Actualizar base image o dependencias.
- Evitar deshabilitar el control sin un procedimiento de excepción documentado.

### 8.4 Problemas de conectividad SMTP hacia Mailpit
- Confirmar Service y DNS:
  - `kubectl -n infra get svc mailpit`
- Validar NetworkPolicies:
  - Debe existir una policy que permita desde namespace `listmonk` (y pods con label `app.kubernetes.io/name=listmonk`) al puerto 1025.
- Ejecutar el test con `nc` desde un pod en `listmonk` (ver sección 6.3).

## 9. Checklist de puesta en marcha

Antes de dar el entorno por operativo:
- Argo CD sincroniza sin errores.
- Listmonk responde (UI accesible por Ingress o port-forward).
- Listmonk conecta a PostgreSQL y no hay errores de migración.
- (Si aplica) Mailpit recibe emails de prueba.
- Los secretos se gestionan exclusivamente vía Sealed Secrets.

## 10. Información a completar
Para que esta guía sea 100% autocontenida, conviene añadir:
- URL/hostname del Ingress y TLS (si aplica).
- Cómo se instala Argo CD en este proyecto (Helm/Terraform, chart y valores principales).
- Cómo se instala/gestiona PostgreSQL (RDS/Helm, backups, política de retención).
- Procedimiento exacto para generar/rotar Sealed Secrets (comandos y prerequisitos de `kubeseal`).
- Mapa de overlays disponibles (local/dev/staging/prod) y diferencias entre ellos.



## Guía rápida de primer despliegue (local/k3s)

### Flujo del sistema (visión operativa)

```text
listmonk2-infra  ──(terraform apply)──▶ instala Argo CD / observabilidad / sealed-secrets / rollouts
       │
       └──────────────────────────────▶ Argo CD observa listmonk2-gitops (Kustomize overlays)
                                         │
listmonk2-app  ──(CI build/push/sign)──▶ publica imagen en GHCR y actualiza tag en listmonk2-gitops
                                         │
                                         └──────────────────────────────▶ Argo CD sincroniza y despliega
```

Este flujo separa responsabilidades: infraestructura en `listmonk2-infra`, despliegue declarativo en `listmonk2-gitops` y construcción/seguridad de imagen en `listmonk2-app`.

### 1) Preparar el host y el clúster

1. Instala herramientas base: `curl`, `git`, `unzip`, `kubectl`, `terraform`.
2. Instala k3s (un nodo) y configura kubeconfig para tu usuario:

```bash
curl -sfL https://get.k3s.io | sh -

sudo mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

kubectl get nodes
```

Si deshabilitaste Traefik en k3s, instala un Ingress Controller alternativo antes del bootstrap.

### 2) Bootstrap de infraestructura (repo `listmonk2-infra`)

1. Clona el repositorio y entra en el entorno local:

```bash
git clone https://github.com/jluisreyvargas/listmonk2-infra
cd listmonk2-infra/terraform/local
```

2. Crea/edita `terraform.tfvars` con, como mínimo:

- `kubeconfig_path`
- `gitops_repo_url`
- `gitops_repo_path` (por ejemplo `apps/listmonk/overlays/local`)
- `domain_base` (por ejemplo `local`)

3. Aplica Terraform:

```bash
terraform init
terraform apply
```

Servicios típicos expuestos por Ingress (según `domain_base`):
- `https://argocd.<domain_base>`
- `https://grafana.<domain_base>`
- `https://prometheus.<domain_base>`

### 3) Resolver nombres localmente (si no hay DNS)

En tu equipo cliente, añade entradas a `/etc/hosts` apuntando a la IP del servidor donde corre k3s, por ejemplo:

```text
<IP_UBUNTU_SERVER> argocd.local grafana.local prometheus.local alertmanager.local loki.local listmonk.local preview.listmonk.local mailpit.local
```

### 4) Acceso a Argo CD

Obtén el password inicial de `admin`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Entra en la UI en `https://argocd.<domain_base>`.

### 5) Despliegue de la aplicación (repo `listmonk2-gitops`)

1. Clona el repositorio GitOps:

```bash
git clone https://github.com/jluisreyvargas/listmonk2-gitops
cd listmonk2-gitops
```

2. Configura la imagen objetivo en el overlay local:
- Fichero: `apps/listmonk/overlays/local/kustomization.yaml` (sección `images:`)

3. Genera el `SealedSecret` con credenciales (DB + admin):

```bash
export DB_USER=listmonk
export DB_PASSWORD='...'
export ADMIN_USER=admin
export ADMIN_PASSWORD='...'
./scripts/generate-sealedsecret.sh
```

4. Commit y push. Argo CD sincronizará automáticamente.

### 6) Validaciones mínimas (Kubernetes)

```bash
kubectl -n listmonk get pods,svc,ingress
kubectl -n listmonk get rollout
kubectl argo rollouts -n listmonk get rollout listmonk
```

Blue/Green:

```bash
kubectl argo rollouts -n listmonk promote listmonk
kubectl argo rollouts -n listmonk undo listmonk
```

### 7) Mailpit (testing SMTP)

UI sin exponer por Ingress:

```bash
kubectl -n infra port-forward svc/mailpit 8025:8025
# http://localhost:8025
```

Conectividad SMTP desde el namespace `listmonk` (debe devolver `open`):

```bash
kubectl -n listmonk run -it --rm smtp-test \
  --image=busybox:1.36 --restart=Never \
  --labels=app.kubernetes.io/name=listmonk \
  -- sh -lc 'nc -zv -w 2 mailpit.infra.svc.cluster.local 1025'
```

### 8) Publicación de imagen (repo `listmonk2-app`)

El pipeline de `listmonk2-app` publica la imagen en GHCR, la firma con Cosign (keyless/OIDC) y actualiza el tag en `listmonk2-gitops` (job `update_gitops`).

Para construir localmente:

```bash
docker build -t ghcr.io/<ORG>/listmonk2:dev .
```

Verificación de firma (Cosign v2):

```bash
export COSIGN_REGISTRY_REFERRERS_MODE=oci-1-1
cosign verify \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp 'https://github.com/<ORG>/listmonk2-app/.github/workflows/ci\.yml@.*' \
  ghcr.io/<ORG>/listmonk2@sha256:<DIGEST>
```

## Solución de problemas comunes

- Repositorios Helm inaccesibles durante `terraform apply`: suele ser un problema de DNS o salida a Internet desde el host. Verifica resolución, proxy (si aplica) y conectividad.
- `yamllint` falla en GitOps: revisa reglas de indentación/line-length y rutas ignoradas.
- Trivy en `listmonk2-app` detecta HIGH/CRITICAL: actualiza base image/dependencias o aplica una excepción temporal documentada.
- Argo CD en `OutOfSync`: confirma `gitops_repo_path`, la presencia del `SealedSecret` en el overlay y que no existan recursos gestionados fuera de Git.



## Operativa diaria

### Desplegar una nueva versión (flujo end-to-end)

El repositorio `listmonk2-app` construye una imagen no-root basada en `listmonk/listmonk:v6.0.0`, la publica en GHCR y ejecuta controles de seguridad en CI (Trivy y firma con Cosign). Como parte del pipeline, actualiza el tag de imagen en `listmonk2-gitops` (overlay local). Al detectarse el cambio, Argo CD sincroniza el overlay y Argo Rollouts gestiona el despliegue Blue/Green.

En la práctica, publicar una versión nueva consiste en hacer merge/push a `main` en `listmonk2-app` y comprobar que el commit de actualización del `kustomization.yaml` llega al repo GitOps. A partir de ahí, el clúster converge solo.

### Comprobar estado del despliegue (sin abrir la UI)

1. Verifica que el Rollout y los pods están en estado consistente:

    kubectl -n listmonk get rollout,pods,svc,ingress

2. Valida conectividad HTTP desde dentro del clúster (evita depender de DNS/hosts local):

    kubectl -n listmonk run -it --rm http-test \
      --image=curlimages/curl:8.6.0 --restart=Never \
      -- sh -lc 'curl -fsS -I http://listmonk-stable | head -n 1 && echo OK'

Si estás usando preview (durante un cambio Blue/Green), repite el test contra `http://listmonk-preview`.

Nota: la validación visual de Mailpit (port-forward a la UI) es opcional si ya validaste conectividad SMTP.

### Promover (Blue/Green)

Cuando la versión nueva responde correctamente en `preview`, promueve el cambio para pasar tráfico a `stable`.

    kubectl argo rollouts -n listmonk promote listmonk

### Rollback

Si una versión falla, vuelve a la revisión anterior:

    kubectl argo rollouts -n listmonk undo listmonk

### Incidencias típicas

- Rollout con `CURRENT` mayor que `DESIRED`: suele indicar revisiones antiguas aún presentes o un despliegue a medio completar. Revisa eventos del rollout y ReplicaSets.

    kubectl -n listmonk describe rollout listmonk
    kubectl -n listmonk get rs -l app.kubernetes.io/name=listmonk

- Reinicios en `argocd-repo-server`: revisa límites/requests y logs; si ocurre al sincronizar manifests grandes, puede ser presión de memoria.

    kubectl -n argocd logs deploy/argocd-repo-server --tail=200

### Rotación de credenciales

Las credenciales (DB y admin) se gestionan como SealedSecrets en `listmonk2-gitops`. Para rotarlas, regenera el YAML cifrado con el script del repo y haz commit/push. Argo CD aplicará el cambio y los pods se recrearán según corresponda.

### Observabilidad

La capa de monitorización vive en `listmonk2-infra` (Prometheus/Grafana/Loki/Promtail). Ante problemas de rendimiento o errores, comienza por:

    kubectl -n listmonk logs deploy/listmonk -c listmonk --tail=200
    kubectl -n monitoring get pods

