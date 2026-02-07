terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SkyPulse"
      ManagedBy   = "Terraform"
      Environment = "stg"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Get ECR URL from dev state (or pass manually)
variable "ecr_repository_url" {
  description = "ECR repository URL (from dev environment output)"
  type        = string
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region          = var.aws_region
  environment         = "stg"
  app_name            = "SkyPulse"
  cpu                 = 256
  memory              = 512
  desired_count       = 1
  min_capacity        = 1
  max_capacity        = 2
  cpu_target_percent  = 70
  create_ecr          = false
  ecr_repository_url  = var.ecr_repository_url
}
