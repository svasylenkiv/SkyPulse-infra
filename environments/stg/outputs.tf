output "alb_dns_name" {
  description = "ALB DNS name (app URL)"
  value       = module.skypulse.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL"
  value       = module.skypulse.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.skypulse.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = module.skypulse.ecs_service_name
}

output "sns_alerts_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
  value       = module.skypulse.sns_alerts_topic_arn
}
