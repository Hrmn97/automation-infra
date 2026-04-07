# =============================================================================
# Sync Reviews Service — SQS worker (syncs reviews from external platforms)
#
# What this file provisions:
#   Calls the sqs-worker-service module (terraform/modules/sqs-worker-service/),
#   which creates: SQS queue + DLQ, ECR repo, ECS task def + service,
#   App Auto Scaling, CloudWatch log group + 4 alarms, IAM roles.
#   Optionally creates the GitHub repository (stage-only, create_github_repo).
#
# How the sync-reviews service fits in:
#   1. A scheduled trigger (EventBridge cron or API call) sends a sync job to
#      the SQS queue.
#   2. Auto-scaler wakes a Fargate task when messages become visible.
#   3. The worker calls external review platforms (Google, Trustpilot, etc.),
#      fetches new reviews, and writes them to the database via the internal API
#      (reachable at api.*.servefirst.local via the shared SG + service discovery).
#   4. On success it calls sqs:DeleteMessage → scales back to 0.
#   5. On failure, message re-queues up to max_retries, then lands in DLQ
#      → DLQ alarm fires → SNS pages on-call.
#
# Connections to the rest of the stack:
#   - aws_security_group.ecs_shared_tasks (c8) — shared SG allows the worker
#     to reach api.*.servefirst.local without additional ingress rules.
#   - aws_sns_topic.infrastructure_alerts (c7) — DLQ + queue-age alarms.
#   - module.api_setup (c6) — vpc_id, private subnets, ECS cluster ID/name.
#   - c21-outputs.tf — re-exports queue_url and ecr_repository_url.
#
# Task sizing:
#   prod: 512 CPU / 1024 MB — handles parallel review ingestion bursts.
#   non-prod: 256 CPU / 512 MB — minimal footprint for testing.
# =============================================================================

module "syncreviews_service" {
  source = "./modules/sqs-worker-service"

  # Identity
  environment  = var.environment
  service_name = "syncreviews" # module appends "-service" for AWS resource names
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

  # Task sizing — prod gets more headroom for parallel review ingestion
  task_cpu         = var.environment == "prod" ? "512" : "256"
  task_memory      = var.environment == "prod" ? "1024" : "512"
  cpu_architecture = "ARM64" # Graviton for cost savings

  # SQS tuning
  visibility_timeout = 300 # 5 min — covers typical external API round-trips
  max_retries        = 3
  retention_days     = 4 # Prod: 4 days; non-prod locked to 1 day by module

  # Auto-scaling ceiling
  max_tasks = 10

  # .env file from CI artifact bucket
  env_file_arn = "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}-syncreviews.env"

  # Alarms → shared SNS topic (c7)
  alarm_sns_topic_arn = aws_sns_topic.infrastructure_alerts.arn

  # GitHub repo created once in stage (both stage + prod share the same repo)
  create_github_repo = true

  common_tags = {
    Name        = "${var.environment}-syncreviews-service"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "syncreviews-service"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "syncreviews_service_queue_url" {
  value       = module.syncreviews_service.queue_url
  description = "Sync-reviews SQS queue URL — send sync-job messages here."
}

output "syncreviews_service_ecr_url" {
  value       = module.syncreviews_service.ecr_repository_url
  description = "Sync-reviews ECR repository URL — push images here in CI."
}
