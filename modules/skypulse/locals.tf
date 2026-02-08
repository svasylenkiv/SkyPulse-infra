locals {
  prefix  = "${var.app_name}-${var.environment}"
  ecr_url = var.create_ecr ? aws_ecr_repository.app[0].repository_url : var.ecr_repository_url
}
