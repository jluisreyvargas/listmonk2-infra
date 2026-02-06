# repo-infra — Bootstrap local (k3s) con Terraform

<<<<<<< HEAD
Este repositorio instala en tu clúster **k3s** (local/dev) la capa de **infra/observabilidad** usando **Terraform + Helm provider**.

Incluye:
=======
Este repositorio instala en tu cluster k3s (local/dev) la capa de **infra/observabilidad** usando **Terraform + Helm provider**.

Incluye:

>>>>>>> 847c493 (Updated README.md)
- **Argo CD** (GitOps)
- **Argo Rollouts** (Blue/Green)
- **Sealed Secrets**
- **Observabilidad**:
<<<<<<< HEAD
  - kube-prometheus-stack (Prometheus/Grafana/Alertmanager)
  - Loki
  - Promtail
- **Mailpit** (SMTP testing) en namespace `infra` + **NetworkPolicies**

> Regla de oro:
> - **Infra/Observabilidad** ⇒ solo aquí (`repo-infra`)
> - **Apps** (Listmonk2, Rollouts, Ingress …) ⇒ en `repo-gitops`
=======
  - kube-prometheus-stack (Prometheus / Grafana / Alertmanager)
  - Loki
  - Promtail
- **Mailpit** (SMTP testing) en namespace `infra` + NetworkPolicies

> Regla de oro:
> - **Infra/Observabilidad** ⇒ solo aquí (`repo-infra`)
> - **Apps** (Listmonk2, Mailpit manifests app-side, Rollouts, Ingress, etc.) ⇒ en `repo-gitops`
>>>>>>> 847c493 (Updated README.md)

---
## 1) Requisitos
- Ubuntu Server 22.04/24.04
- `curl`, `git`, `unzip`
- `kubectl`
<<<<<<< HEAD
- `terraform` (Helm CLI opcional)
=======
- `terraform`

> `helm` es opcional (Terraform usa Helm internamente).

---

## 2) Instalar k3s (1 nodo)
>>>>>>> 847c493 (Updated README.md)

## 2) Instalar k3s (1 nodo)
```bash
curl -sfL https://get.k3s.io | sh -
# kubeconfig (root)
sudo mkdir -p $HOME/.kube
<<<<<<< HEAD
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
=======
sudo cat /etc/rancher/k3s/k3s.yaml > $HOME/.kube/config
>>>>>>> 847c493 (Updated README.md)
sudo chown $USER:$USER $HOME/.kube/config
kubectl get nodes
```
> k3s instala Traefik por defecto. Si lo desactivaste, añade tu Ingress Controller preferido.

<<<<<<< HEAD
## 3) Variables (terraform/local/terraform.tfvars)
- `kubeconfig_path` → ruta a tu kubeconfig
- `gitops_repo_url` → URL del repo GitOps (GitHub)
- `gitops_repo_path` → path dentro del repo (p. ej. `apps/listmonk/overlays/local`)
- `domain_base` → dominio local (ej. `local`) para Ingress: `argocd.local`, `grafana.local`, `prometheus.local`, `listmonk.local`, `preview.listmonk.local`.
=======
---

## 3) Configurar variables

En `terraform/local/terraform.tfvars`:

- `kubeconfig_path` → ruta a tu kubeconfig
- `gitops_repo_url` → URL del repo GitOps (GitHub)
- `gitops_repo_path` → path dentro del repo (por defecto `apps/listmonk/overlays/local`)
- `domain_base` → dominio local (ej. `local`) para Ingress:
  - `argocd.local`, `grafana.local`, `prometheus.local`, etc.

---

## 4) Aplicar Terraform
>>>>>>> 847c493 (Updated README.md)

## 4) Aplicar Terraform
```bash
cd terraform/local
terraform init
terraform apply
```
Al terminar (según `domain_base`):
- Argo CD → https://argocd.<domain_base>
- Grafana → https://grafana.<domain_base>
- Prometheus → https://prometheus.<domain_base>

<<<<<<< HEAD
## 5) /etc/hosts (si no tienes DNS)
En tu PC añade:
=======
Al terminar (según `domain_base`):

- Argo CD: `https://argocd.<domain_base>`
- Grafana: `https://grafana.<domain_base>`
- Prometheus: `https://prometheus.<domain_base>`
- Alertmanager: `https://alertmanager.<domain_base>`
- Loki (si expones gateway/ingress): `https://loki.<domain_base>`
- Mailpit UI: `http://mailpit.<domain_base>` (si lo expones)

---

## 5) /etc/hosts (si no tienes DNS local)

En tu PC (cliente) añade:

>>>>>>> 847c493 (Updated README.md)
```
<IP_UBUNTU_SERVER> argocd.local grafana.local prometheus.local alertmanager.local loki.local listmonk.local preview.listmonk.local mailpit.local
```

<<<<<<< HEAD
## 6) Credenciales
**Argo CD (password inicial)**
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```
**Grafana**: ver `terraform/local/values/monitoring-values.yaml`.

## 7) Bootstrap GitOps
Terraform crea AppProject + Application en ArgoCD apuntando a tu repo GitOps. Al hacer push (y subir los SealedSecrets), ArgoCD sincroniza y despliega.

## 8) Mailpit (SMTP testing) + validaciones
- Namespace `infra`, Service **ClusterIP** (UI 8025 / SMTP 1025).
- NetworkPolicies: `default-deny` + `allow-smtp-from-listmonk`.
### 8.1 UI sin exponer
```bash
kubectl -n infra port-forward svc/mailpit 8025:8025
# http://localhost:8025
```
### 8.2 Test SMTP desde `listmonk`
```bash
kubectl -n listmonk run -it --rm smtp-test   --image=busybox:1.36 --restart=Never   --labels=app.kubernetes.io/name=listmonk   -- sh -lc 'nc -zv -w 2 mailpit.infra.svc.cluster.local 1025'
```
Debe mostrar **open**.

## 9) Verificar requests/limits
Usa contexto en `egrep` o `jsonpath` para ver cpu/memory:
```bash
kubectl -n monitoring describe deploy kube-prometheus-stack-grafana   | egrep -ni -A6 -B1 'Limits:|Requests:|Security Context'
```

---

=======
---

## 6) Credenciales

### Argo CD (password inicial)
```bash
kubectl -n argocd get secret argocd-initial-admin-secret   -o jsonpath='{.data.password}' | base64 -d; echo
```

### Grafana
Ver `terraform/local/values/monitoring-values.yaml` (admin/pass del ejemplo).

---

## 7) Bootstrap GitOps (automático)

Terraform crea un `AppProject` y un `Application` de Argo CD que apunta a tu repo GitOps.

Cuando haces push al repo GitOps (y generas los SealedSecrets), Argo CD sincroniza y despliega la app.

---

## 8) Mailpit (SMTP testing) + validaciones

Mailpit está desplegado en namespace `infra` con:

- Service ClusterIP: UI (8025) + SMTP (1025)
- NetworkPolicies: default-deny + allow-smtp-from-listmonk

### 8.1 Ver UI por port-forward
```bash
kubectl -n infra port-forward svc/mailpit 8025:8025
# abre: http://localhost:8025
```

### 8.2 Probar conectividad SMTP desde namespace listmonk
```bash
kubectl -n listmonk run -it --rm smtp-test   --image=busybox:1.36   --restart=Never   --labels=app.kubernetes.io/name=listmonk   -- sh -lc 'nc -zv -w 2 mailpit.infra.svc.cluster.local 1025'
```
Debe mostrar `open`.

### 8.3 Configurar SMTP en Listmonk
- Host: `mailpit.infra.svc.cluster.local`
- Puerto: `1025`
- Sin TLS / sin auth

Enviar “test email” y comprobar en Mailpit UI.

---

## 9) Verificar requests/limits correctamente (nota)
Si usas `kubectl describe | grep`, recuerda incluir contexto; si no, verás “Limits:” vacío.

Ejemplo:
```bash
kubectl -n monitoring describe deploy kube-prometheus-stack-grafana | egrep -ni -A6 -B1 "Limits:|Requests:|Security Context"
```

---

## (Opcional) AWS skeleton

`aws-skeleton/` contiene un ejemplo mínimo de estructura Terraform (tags/variables) para un despliegue futuro en AWS.
>>>>>>> 847c493 (Updated README.md)
