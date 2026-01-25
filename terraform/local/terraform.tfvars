# Copia a terraform.tfvars y ajusta valores
kubeconfig_path = "~/.kube/config"
# Ejemplo: https://github.com/TU_ORG/repo-gitops.git
gitops_repo_url = "https://github.com/jluisreyvargas/listmonk2-gitops.git"
# Path dentro del repo GitOps
gitops_repo_path = "apps/listmonk/overlays/local"
# Branch
gitops_target_revision = "main"

# Dominio base para Ingress (argocd.local, grafana.local, ...)
domain_base = "local"

# NO lo comitees: mejor exporta TF_VAR_grafana_admin_password
# grafana_admin_password = ""
