output "urls" {
  value = {
    argocd       = "http://${local.hosts.argocd}"
    grafana      = "http://${local.hosts.grafana}"
    prometheus   = "http://${local.hosts.prometheus}"
    alertmanager = "http://${local.hosts.alertmanager}"
    loki         = "http://${local.hosts.loki}"
    rollouts     = "http://rollouts.${var.domain_base}"
  }
}
