# =============================================================================
# Response Service — SQS worker (processes survey responses)
#
# What this file provisions:
#   Calls the sqs-worker-service module (terraform/modules/sqs-worker-service/),
#   which creates: SQS queue + DLQ, ECR repo, ECS task def + service,
#   App Auto Scaling, CloudWatch log group + 4 alarms, IAM roles.
#   Also creates the GitHub repository (stage-only via create_github_repo).
#
# How the response service fits in:
#   1. A survey submission (from the API) sends a response-processing job to
#      the SQS queue.
#   2. Auto-scaler wakes a Fargate task when messages become visible.
#   3. The worker processes the response (scoring, aggregation, notifications).
#   4. On success it calls sqs:DeleteMessage → auto-scaler scales back to 0.
#   5. On failure the message re-queues up to max_retries, then lands in DLQ
#      → DLQ alarm fires → SNS pages on-call.
#
# Connections to the rest of the stack:
#   - aws_security_group.ecs_shared_tasks (c8) — shared SG lets this worker
#     reach api.*.servefirst.local without additional ingress rules.
#   - aws_sns_topic.infrastructure_alerts (c7) — DLQ + queue-age alarms.
#   - module.api_setup (c6) — vpc_id, private subnets, ECS cluster ID/name.
#   - c21-outputs.tf — re-exports queue_url and ecr_repository_url.
#
# Locals collision fix (sanity check §3.4):
#   Source declared `local.service_name_root = "response"` which collides with
#   `local.service_name` in c3-datasources-and-locals.tf. Fixed by inlining
#   the string literal "response" directly — no local needed.
# =============================================================================

module "response_service" {
  source = "./modules/sqs-worker-service"

  # Identity
  environment  = var.environment
  service_name = "response" # module appends "-service" for AWS resource names
  aws_region   = var.aws_region

  # Infrastructure from api-infra module (c6-main.tf)
  vpc_id             = module.api_setup.vpc_id
  private_subnet_ids = module.api_setup.private_subnets
  ecs_cluster_id     = module.api_setup.ecs_cluster_id
  ecs_cluster_name   = module.api_setup.ecs_cluster_name

  # Shared security group (c8) — lets worker reach internal services
  security_group_ids = [aws_security_group.ecs_shared_tasks.id]

  # Worker — no HTTP port, no DNS record needed
  enable_service_discovery = false

  # Task sizing — lightweight; response processing is CPU-light
  task_cpu         = "256"
  task_memory      = "512"
  cpu_architecture = "ARM64" # Graviton for cost savings

  # SQS tuning
  visibility_timeout = 300 # 5 min — covers typical response-processing time
  max_retries        = 3
  retention_days     = 4 # Prod: 4 days; non-prod locked to 1 day by module

  # Auto-scaling ceiling
  max_tasks = 10

  # .env file from CI artifact bucket
  env_file_arn = "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}-response.env"

  # Alarms → shared SNS topic (c7)
  alarm_sns_topic_arn = aws_sns_topic.infrastructure_alerts.arn

  # GitHub repo created once in stage (both stage + prod share the same repo)
  create_github_repo = true

  common_tags = {
    Name        = "${var.environment}-response-service"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "response-service"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "response_service_queue_url" {
  value       = module.response_service.queue_url
  description = "Response service SQS queue URL — send survey-response jobs here."
}

output "response_service_ecr_url" {
  value       = module.response_service.ecr_repository_url
  description = "Response service ECR repository URL — push images here in CI."
}
