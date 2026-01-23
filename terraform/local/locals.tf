locals {
  common_labels = {
    "app.kubernetes.io/part-of"   = var.project_name
    "app.kubernetes.io/managed-by" = "terraform"
    "project" = var.project_name
    "env"     = var.environment
    "owner"   = var.owner
  }

  hosts = {
    argocd       = "argocd.${var.domain_base}"
    grafana      = "grafana.${var.domain_base}"
    prometheus   = "prometheus.${var.domain_base}"
    alertmanager = "alertmanager.${var.domain_base}"
    loki         = "loki.${var.domain_base}"
  }
}
