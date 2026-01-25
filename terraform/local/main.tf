resource "kubernetes_namespace" "argocd" {
  metadata {
    name   = "argocd"
    labels = local.common_labels
  }
}

resource "kubernetes_namespace" "argo_rollouts" {
  metadata {
    name   = "argo-rollouts"
    labels = local.common_labels
  }
}

resource "kubernetes_namespace" "sealed_secrets" {
  metadata {
    name   = "sealed-secrets"
    labels = local.common_labels
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name   = "monitoring"
    labels = local.common_labels
  }
}

resource "kubernetes_namespace" "logging" {
  metadata {
    name   = "logging"
    labels = local.common_labels
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.3.4"

  values = [
    file("${path.module}/values/argocd-values.yaml")
  ]

  # host dinámico (evita hardcode)
  set {
    name  = "server.ingress.hosts[0]"
    value = local.hosts.argocd
  }
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  namespace        = kubernetes_namespace.argo_rollouts.metadata[0].name
  create_namespace = false

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = "2.40.5"

  values = [
    file("${path.module}/values/argo-rollouts-values.yaml")
  ]

  set {
    name  = "dashboard.ingress.hosts[0]"
    value = "rollouts.${var.domain_base}"
  }
}

resource "helm_release" "sealed_secrets" {
  name             = "sealed-secrets"
  namespace        = kubernetes_namespace.sealed_secrets.metadata[0].name
  create_namespace = false

  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.18.0"

  values = [
    file("${path.module}/values/sealed-secrets-values.yaml")
  ]
}

resource "helm_release" "monitoring" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "81.0.0"

  values = [
    file("${path.module}/values/monitoring-values.yaml")
  ]

  set {
    name  = "grafana.ingress.hosts[0]"
    value = local.hosts.grafana
  }
  set {
    name  = "prometheus.ingress.hosts[0]"
    value = local.hosts.prometheus
  }
  set {
    name  = "alertmanager.ingress.hosts[0]"
    value = local.hosts.alertmanager
  }

  # Password sin hardcode (usa TF_VAR_grafana_admin_password)
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
}

resource "helm_release" "loki" {
  name             = "loki"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false

  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.49.0"

values = [yamlencode({
  deploymentMode = "SingleBinary"

  loki = {
    auth_enabled = false
    commonConfig = {
      replication_factor = 1
    }
    storage = {
      type = "filesystem"
    }
    schemaConfig = {
      configs = [
        {
          from = "2024-01-01"
          store = "tsdb"
          object_store = "filesystem"
          schema = "v13"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }
      ]
    }
  }

  singleBinary = {
    replicas = 1
  }

  # Desactiva componentes distribuidos que asumen S3
  write = { replicas = 0 }
  read  = { replicas = 0 }
  backend = { replicas = 0 }

  gateway = { enabled = false }
})]

}

resource "helm_release" "promtail" {
  name             = "promtail"
  namespace        = kubernetes_namespace.logging.metadata[0].name
  create_namespace = false

  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.17.1"

  values = [
    file("${path.module}/values/promtail-values.yaml")
  ]

  depends_on = [helm_release.loki]
}

# Ingress para Loki (gateway)
resource "kubernetes_ingress_v1" "loki" {
  metadata {
    name      = "loki"
    namespace = kubernetes_namespace.logging.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                             = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints"       = "web"
    }
    labels = local.common_labels
  }

  spec {
    rule {
      host = local.hosts.loki
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "loki-gateway"
              port { number = 80 }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.loki]
}

# Bootstrap GitOps: AppProject + Application
resource "kubernetes_manifest" "argocd_project" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "listmonk2"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      labels    = local.common_labels
    }
    spec = {
      description = "Proyecto ListMonk2 (local)"
      sourceRepos = ["*"]
      destinations = [
        {
          namespace = "*"
          server    = "https://kubernetes.default.svc"
        }
      ]
      clusterResourceWhitelist = [
        { group = "*", kind = "*" }
      ]
      namespaceResourceWhitelist = [
        { group = "*", kind = "*" }
      ]
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "listmonk2"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      labels    = local.common_labels
    }
    spec = {
      project = kubernetes_manifest.argocd_project.manifest["metadata"]["name"]
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_target_revision
        path           = var.gitops_repo_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "listmonk"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.argocd_project]
}
