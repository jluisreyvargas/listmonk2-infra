variable "project_name" {
  description = "Project tag/label value"
  type        = string
  default     = "listmonk2"
}

variable "environment" {
  description = "Environment label"
  type        = string
  default     = "local"
}

variable "owner" {
  description = "Owner label"
  type        = string
  default     = "devops"
}

variable "kubeconfig_path" {
  description = "Ruta al kubeconfig (ej: ~/.kube/config)"
  type        = string
}

variable "domain_base" {
  description = "Dominio base local (ej: local)"
  type        = string
  default     = "local"
}

variable "gitops_repo_url" {
  description = "URL del repo GitOps (ej: https://github.com/ORG/repo-gitops.git)"
  type        = string
}

variable "gitops_repo_path" {
  description = "Path en el repo GitOps donde está el overlay local"
  type        = string
  default     = "apps/listmonk/overlays/local"
}

variable "gitops_target_revision" {
  description = "Branch o tag (ej: main)"
  type        = string
  default     = "main"
}

variable "grafana_admin_password" {
  description = "Password admin Grafana (NO lo comitees: usa TF_VAR_grafana_admin_password)"
  type        = string
  sensitive   = true
}
