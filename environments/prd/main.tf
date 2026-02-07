terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote backend (uncomment and configure for your setup)
  # backend "s3" {
  #   bucket = "skypulse-terraform-state"
  #   key    = "prd/terraform.tfstate"
  #   region = "eu-central-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SkyPulse"
      ManagedBy   = "Terraform"
      Environment = "prd"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

# Get ECR URL from dev state (or pass manually)
variable "ecr_repository_url" {
  description = "ECR repository URL (from dev environment output)"
  type        = string
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region          = var.aws_region
  environment         = "prd"
  app_name            = "skypulse"
  cpu                 = 512
  memory              = 1024
  desired_count       = 2
  min_capacity        = 2
  max_capacity        = 4
  cpu_target_percent  = 60
  create_ecr          = false
  ecr_repository_url  = var.ecr_repository_url
}
