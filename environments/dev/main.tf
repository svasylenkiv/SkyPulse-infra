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
      Environment = "dev"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region         = var.aws_region
  environment        = "dev"
  app_name           = "SkyPulse"
  cpu                = 256
  memory             = 512
  desired_count      = 1
  min_capacity       = 1
  max_capacity       = 1
  cpu_target_percent = 70
  create_ecr         = true # ECR created in dev, shared across envs
}
