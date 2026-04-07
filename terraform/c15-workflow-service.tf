# =============================================================================
# Workflow Service — SQS worker (business workflow orchestration)
#
# What this file provisions:
#   Calls the sqs-worker-service module (terraform/modules/sqs-worker-service/),
#   which creates: SQS queue + DLQ, ECR repo, ECS task def + service,
#   App Auto Scaling, CloudWatch log group + 4 alarms, IAM roles.
#
# How the workflow service fits in:
#   1. The API (or another trigger) sends a job message to the SQS queue.
#   2. Auto-scaler wakes a Fargate task when messages become visible.
#   3. The worker processes the workflow step (e.g. status transitions,
#      notifications, third-party integrations).
#   4. On success it calls sqs:DeleteMessage → auto-scaler scales back to 0.
#   5. On failure the message re-queues up to max_retries then lands in DLQ
#      → DLQ alarm fires → SNS pages on-call.
# =============================================================================

module "workflow_service" {
  source = "./modules/sqs-worker-service"

  # Identity
  environment  = var.environment
  service_name = "workflow" # module appends "-service" for AWS resource names
  aws_region   = var.aws_region

  # Infrastructure from api-infra module (c6-main.tf)
  vpc_id             = module.api_setup.vpc_id
  private_subnet_ids = module.api_setup.private_subnets
  ecs_cluster_id     = module.api_setup.ecs_cluster_id
  ecs_cluster_name   = module.api_setup.ecs_cluster_name

  # Shared security group (c8) — allows worker to reach internal services
  security_group_ids = [aws_security_group.ecs_shared_tasks.id]

  # Worker — no HTTP port, so no DNS record needed in service discovery
  enable_service_discovery = false

  # Task sizing — workflow processing is lighter than Puppeteer PDF rendering
  task_cpu         = "512"
  task_memory      = "1024"
  cpu_architecture = "ARM64" # Graviton for cost savings

  # SQS tuning
  visibility_timeout = 300 # 5 min — covers typical workflow step durations
  max_retries        = 3
  retention_days     = 2 # Prod: 2 days; non-prod locked to 1 day by module

  # Auto-scaling ceiling
  max_tasks = 10

  # .env file from CI artifact bucket
  env_file_arn = "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}-workflow.env"

  # Alarms → shared SNS topic (c7)
  alarm_sns_topic_arn = aws_sns_topic.infrastructure_alerts.arn

  # No workflow-specific policies today — add here when needed, e.g.:
  # additional_task_role_policies = [aws_iam_policy.workflow_bedrock_access.arn]
  additional_task_role_policies = []

  common_tags = {
    Name        = "${var.environment}-workflow-service"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "workflow-service"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "workflow_service_queue_url" {
  value       = module.workflow_service.queue_url
  description = "Workflow service SQS queue URL — send job messages here."
}

output "workflow_service_ecr_url" {
  value       = module.workflow_service.ecr_repository_url
  description = "Workflow service ECR repository URL — push images here in CI."
}
