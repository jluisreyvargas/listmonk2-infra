# repo-infra — Bootstrap local (k3s) con Terraform

Este repositorio instala en tu cluster k3s:

- **Argo CD** (GitOps) — chart `argo-cd` (argo-helm)
- **Argo Rollouts** (Blue/Green)
- **Sealed Secrets**
- **Observabilidad**: kube-prometheus-stack (Prometheus/Grafana/Alertmanager) + Loki + Promtail

Todo se instala con **Terraform + Helm provider** contra tu kubeconfig.

---

## 1) Requisitos en Ubuntu Server

- Ubuntu Server 22.04/24.04
- `curl`, `git`, `unzip`
- `kubectl`
- `helm` (solo opcional; Terraform usa Helm internamente)
- `terraform` (recomendado v1.14.1+) citeturn1search1

### Instalar k3s (1 nodo)

```bash
curl -sfL https://get.k3s.io | sh -

# kubeconfig (root)
sudo cat /etc/rancher/k3s/k3s.yaml > $HOME/.kube/config
sudo chown $USER:$USER $HOME/.kube/config

kubectl get nodes
```

> k3s instala Traefik por defecto. Si lo desactivaste, añade tu Ingress Controller preferido.

---

## 2) Configurar variables

En `terraform/local/terraform.tfvars`:

- `kubeconfig_path` → ruta a tu kubeconfig
- `gitops_repo_url` → URL del repo GitOps (GitHub)
- `gitops_repo_path` → path dentro del repo (por defecto `apps/listmonk/overlays/local`)
- `domain_base` → dominio local (ej. `local`) para Ingress (`argocd.local`, `listmonk.local`)

---

## 3) Aplicar Terraform

```bash
cd terraform/local
terraform init
terraform apply
```

Al terminar:

- Argo CD: `https://argocd.<domain_base>`
- Grafana: `https://grafana.<domain_base>`
- Prometheus: `https://prometheus.<domain_base>`

### /etc/hosts (si no tienes DNS local)

En tu PC (cliente) añade:

```
<IP_UBUNTU_SERVER> argocd.local grafana.local prometheus.local alertmanager.local loki.local listmonk.local preview.listmonk.local
```

---

## 4) Credenciales

Argo CD (password inicial):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Grafana (admin/pass por defecto en este ejemplo): ver `terraform/local/values/monitoring-values.yaml`.

---

## 5) Bootstrap GitOps (automático)

Terraform crea un `AppProject` y un `Application` de Argo CD que apunta a tu repo GitOps.

Cuando hagas push al repo GitOps (y generes los SealedSecrets), Argo CD sincroniza y despliega la app.

---

## (Opcional) AWS skeleton

`aws-skeleton/` contiene:

- ejemplo de `locals { tags = {...} }`
- variables para nombre de proyecto/env/owner

Para el despliegue AWS completo (EKS/RDS/ALB/Secrets Manager) se mantiene el mismo patrón infra/app/gitops.
