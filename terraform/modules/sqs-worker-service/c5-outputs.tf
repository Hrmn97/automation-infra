# =============================================================================
# sqs-worker-service module — outputs
# =============================================================================

output "queue_url" {
  value       = aws_sqs_queue.service_queue.url
  description = "URL of the SQS main queue — injected as SQS_QUEUE_URL env var."
}

output "queue_arn" {
  value       = aws_sqs_queue.service_queue.arn
  description = "ARN of the SQS main queue."
}

output "queue_name" {
  value       = aws_sqs_queue.service_queue.name
  description = "Name of the SQS main queue."
}

output "dlq_url" {
  value       = aws_sqs_queue.service_dlq.url
  description = "URL of the Dead Letter Queue."
}

output "dlq_arn" {
  value       = aws_sqs_queue.service_dlq.arn
  description = "ARN of the Dead Letter Queue."
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.service_repo.repository_url
  description = "ECR repository URL — used by CI to push images."
}

output "ecr_repository_name" {
  value       = aws_ecr_repository.service_repo.name
  description = "ECR repository name."
}

output "ecs_service_name" {
  value       = aws_ecs_service.service.name
  description = "ECS service name — used by CI to trigger rolling deploys."
}

output "task_role_arn" {
  value       = aws_iam_role.task_role.arn
  description = "ARN of the ECS task role (container runtime permissions)."
}

output "task_execution_role_arn" {
  value       = aws_iam_role.task_execution_role.arn
  description = "ARN of the ECS task execution role (ECS agent permissions)."
}

output "log_group_name" {
  value       = aws_cloudwatch_log_group.service_logs.name
  description = "CloudWatch log group name for the service."
}

output "security_group_id" {
  value       = length(var.security_group_ids) == 0 ? aws_security_group.service_sg[0].id : var.security_group_ids[0]
  description = "Security group ID in use (module-created or first caller-supplied)."
}
