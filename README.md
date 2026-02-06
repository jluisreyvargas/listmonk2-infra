# repo-infra — Bootstrap local (k3s) con Terraform

Este repositorio instala en tu clúster **k3s** (local/dev) la capa de **infra/observabilidad** usando **Terraform + Helm provider**.

Incluye:
- **Argo CD** (GitOps)
- **Argo Rollouts** (Blue/Green)
- **Sealed Secrets**
- **Observabilidad**:
  - kube-prometheus-stack (Prometheus/Grafana/Alertmanager)
  - Loki
  - Promtail
- **Mailpit** (SMTP testing) en namespace `infra` + **NetworkPolicies**

> Regla de oro:
> - **Infra/Observabilidad** ⇒ solo aquí (`repo-infra`)
> - **Apps** (Listmonk2, Rollouts, Ingress …) ⇒ en `repo-gitops`

---
## 1) Requisitos
- Ubuntu Server 22.04/24.04
- `curl`, `git`, `unzip`
- `kubectl`
- `terraform` (Helm CLI opcional)

## 2) Instalar k3s (1 nodo)
```bash
curl -sfL https://get.k3s.io | sh -
# kubeconfig (root)
sudo mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config
kubectl get nodes
```
> k3s instala Traefik por defecto. Si lo desactivaste, añade tu Ingress Controller preferido.

## 3) Variables (terraform/local/terraform.tfvars)
- `kubeconfig_path` → ruta a tu kubeconfig
- `gitops_repo_url` → URL del repo GitOps (GitHub)
- `gitops_repo_path` → path dentro del repo (p. ej. `apps/listmonk/overlays/local`)
- `domain_base` → dominio local (ej. `local`) para Ingress: `argocd.local`, `grafana.local`, `prometheus.local`, `listmonk.local`, `preview.listmonk.local`.

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

## 5) /etc/hosts (si no tienes DNS)
En tu PC añade:
```
<IP_UBUNTU_SERVER> argocd.local grafana.local prometheus.local alertmanager.local loki.local listmonk.local preview.listmonk.local mailpit.local
```

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

