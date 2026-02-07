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
  #   key    = "dev/terraform.tfstate"
  #   region = "eu-central-1"
  # }
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
  default     = "eu-central-1"
}

module "skypulse" {
  source = "../../modules/skypulse"

  aws_region         = var.aws_region
  environment        = "dev"
  app_name           = "skypulse"
  cpu                = 256
  memory             = 512
  desired_count      = 1
  min_capacity       = 1
  max_capacity       = 1
  cpu_target_percent = 70
  create_ecr         = true # ECR created in dev, shared across envs
}
