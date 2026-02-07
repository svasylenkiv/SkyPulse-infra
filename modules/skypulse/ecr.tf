# --- ECR Repository (created only when create_ecr = true) ---
resource "aws_ecr_repository" "app" {
  count                = var.create_ecr ? 1 : 0
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.app_name}-ecr" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  count      = var.create_ecr ? 1 : 0
  repository = aws_ecr_repository.app[0].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

locals {
  ecr_url = var.create_ecr ? aws_ecr_repository.app[0].repository_url : var.ecr_repository_url
}
