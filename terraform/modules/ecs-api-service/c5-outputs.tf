# =============================================================================
# ecs-api-service module — outputs
# =============================================================================

output "service_name" {
  value       = aws_ecs_service.service.name
  description = "ECS service name — used by CI for rolling deploys."
}

output "service_arn" {
  value       = aws_ecs_service.service.id
  description = "ECS service ARN."
}

output "task_definition_arn" {
  value       = aws_ecs_task_definition.service_task.arn
  description = "Latest Terraform-managed task definition ARN."
}

output "task_definition_family" {
  value       = aws_ecs_task_definition.service_task.family
  description = "Task definition family name."
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.service_repo.repository_url
  description = "ECR repository URL — push images here in CI."
}

output "ecr_repository_arn" {
  value       = aws_ecr_repository.service_repo.arn
  description = "ECR repository ARN."
}

output "target_group_arn" {
  value       = aws_lb_target_group.service_tg.arn
  description = "ALB target group ARN."
}

output "target_group_name" {
  value       = aws_lb_target_group.service_tg.name
  description = "ALB target group name."
}

output "task_execution_role_arn" {
  value       = local.task_execution_role_arn
  description = "Task execution role ARN (module-created or caller-supplied)."
}

output "task_role_arn" {
  value       = local.task_role_arn
  description = "Task role ARN (module-created or caller-supplied)."
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.service_logs.name
  description = "CloudWatch log group name."
}

output "log_group_arn" {
  value       = aws_cloudwatch_log_group.service_logs.arn
  description = "CloudWatch log group ARN."
}

output "autoscaling_target_resource_id" {
  value       = var.enable_autoscaling ? aws_appautoscaling_target.service_scaling_target[0].resource_id : null
  description = "App Auto Scaling target resource ID (null when autoscaling disabled)."
}

output "autoscaling_policies" {
  value = {
    cpu     = var.enable_autoscaling && var.enable_cpu_scaling ? aws_appautoscaling_policy.cpu_scaling_policy[0].arn : null
    memory  = var.enable_autoscaling && var.enable_memory_scaling ? aws_appautoscaling_policy.memory_scaling_policy[0].arn : null
    request = var.enable_autoscaling && var.enable_request_count_scaling ? aws_appautoscaling_policy.request_count_scaling_policy[0].arn : null
  }
  description = "Map of auto-scaling policy ARNs (null when the policy is disabled)."
}

output "service_discovery_arn" {
  value       = var.enable_service_discovery ? aws_service_discovery_service.service[0].arn : null
  description = "Service discovery service ARN (null when disabled)."
}

output "service_discovery_name" {
  value       = var.enable_service_discovery ? aws_service_discovery_service.service[0].name : null
  description = "Service discovery DNS name (null when disabled)."
}

output "cloudwatch_alarms" {
  value = {
    cpu_alarm    = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.high_cpu[0].arn : null
    memory_alarm = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.high_memory[0].arn : null
  }
  description = "Map of CloudWatch alarm ARNs (null when alarms are disabled)."
}
