variable "project_name" { type = string }
variable "environment" { type = string }
variable "owner" { type = string }

locals {
  tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }
}

# Ejemplo de uso:
# resource "aws_s3_bucket" "example" {
#   bucket = "..."
#   tags   = local.tags
# }
