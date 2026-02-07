variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stg, prd)"
  type        = string
}

variable "app_name" {
  description = "Application name"
  type        = string
  default     = "skypulse"
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "Fargate task CPU (in CPU units)"
  type        = number
}

variable "memory" {
  description = "Fargate task memory (in MiB)"
  type        = number
}

variable "desired_count" {
  description = "Initial number of running tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of tasks (autoscaling)"
  type        = number
}

variable "max_capacity" {
  description = "Maximum number of tasks (autoscaling)"
  type        = number
}

variable "cpu_target_percent" {
  description = "Target CPU utilization for autoscaling (%)"
  type        = number
  default     = 70
}

variable "create_ecr" {
  description = "Whether to create ECR repository (set true only in one environment)"
  type        = bool
  default     = false
}

variable "ecr_repository_url" {
  description = "ECR repository URL (when create_ecr = false, pass from shared)"
  type        = string
  default     = ""
}
