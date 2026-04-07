# =============================================================================
# PDF Service — SQS worker (Puppeteer-based PDF generation)
#
# What this file provisions:
#   Calls the sqs-worker-service module, which creates:
#     - SQS queue + DLQ
#     - ECR repository
#     - ECS task definition (ARM64, 1 vCPU / 2 GB — Puppeteer needs headroom)
#     - ECS service (desired=0, auto-scaled by queue depth)
#     - CloudWatch log group + 4 alarms (queue-high, queue-low, DLQ, age)
#     - IAM execution role + task role + SQS consumer policy
#   Plus an env-specific S3 IAM policy for storing generated PDFs.
#
# How the PDF service fits in:
#   1. Another service (api or workflow) sends a job to the SQS queue.
#   2. Auto-scaler wakes a Fargate task when ApproximateNumberOfMessagesVisible ≥ 1.
#   3. Puppeteer renders HTML → PDF.
#   4. Task writes the PDF to the reports/images S3 bucket (pdf_s3_access policy).
#   5. Task calls sqs:DeleteMessage → auto-scaler scales back to 0.
#
# Connections to the rest of the stack:
#   - aws_security_group.ecs_shared_tasks (c8) — shared SG lets PDF call api
#     via service-discovery without opening additional rules.
#   - aws_sns_topic.infrastructure_alerts (c7) — DLQ + age alarms page on-call.
#   - c10-client-uploads.tf / cloudfront-s3 stacks — PDF writes to the same
#     account-level buckets (app.servefirst.co.uk.reports etc).
#   - c21-outputs.tf — re-exports queue_url and ecr_repository_url.
#
# Drift note (sanity check §3.5):
#   Source hardcoded "stagev2" for non-prod S3 bucket. Fixed: now uses
#   a local that maps prod→app, stage→stagev2, everything else→dev.
# =============================================================================

locals {
  # Map each environment to the bucket prefix that holds PDFs + images.
  # prod  → app.servefirst.co.uk
  # stage → stagev2.servefirst.co.uk
  # dev   → dev.servefirst.co.uk  (new — avoids sharing stagev2 from dev)
  pdf_bucket_prefix = lookup({
    prod  = "app"
    stage = "stagev2"
  }, var.environment, var.environment)
}

# -----------------------------------------------------------------------------
# S3 access policy — lets the PDF task write generated files
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "pdf_s3_access" {
  name        = "${var.environment}-pdf-s3-access"
  description = "Allows the PDF service task to write generated PDFs and images to S3."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "PDFBucketWrite"
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
      ]
      Resource = [
        "arn:aws:s3:::${local.pdf_bucket_prefix}.servefirst.co.uk.reports/*",
        "arn:aws:s3:::${local.pdf_bucket_prefix}.servefirst.co.uk.images/*",
      ]
    }]
  })

  tags = {
    Name        = "${var.environment}-pdf-s3-access"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "pdf-service"
  }
}

# -----------------------------------------------------------------------------
# PDF Service module call
# -----------------------------------------------------------------------------

module "pdf_service" {
  source = "./modules/sqs-worker-service"

  # Identity
  environment  = var.environment
  service_name = "pdf" # module appends "-service" for AWS resource names
  aws_region   = var.aws_region

  # Infrastructure from api-infra module (c6-main.tf)
  vpc_id             = module.api_setup.vpc_id
  private_subnet_ids = module.api_setup.private_subnets
  ecs_cluster_id     = module.api_setup.ecs_cluster_id
  ecs_cluster_name   = module.api_setup.ecs_cluster_name

  # Shared security group (c8) — allows PDF to reach api.*.servefirst.local
  security_group_ids = [aws_security_group.ecs_shared_tasks.id]

  # Workers don't register a DNS record; they call others via service discovery
  enable_service_discovery = false

  # Task sizing — Puppeteer (headless Chromium) needs at least 1 vCPU / 2 GB
  task_cpu         = "1024"
  task_memory      = "2048"
  cpu_architecture = "ARM64" # Graviton for cost savings

  # SQS tuning
  visibility_timeout = 300 # 5 min — enough for typical PDF renders
  max_retries        = 3
  retention_days     = 3 # Prod: 3 days; non-prod locked to 1 day by module

  # max_message_size left at module default (256 KB); lifecycle ignore_changes
  # in the module prevents plan noise if AWS adjusts this after creation

  # Auto-scaling ceiling
  max_tasks = 10

  # .env file from CI artifact bucket
  env_file_arn = "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}-pdf.env"

  # Alarms → shared SNS topic (c7)
  alarm_sns_topic_arn = aws_sns_topic.infrastructure_alerts.arn

  # Grant the task role write access to the PDF/images S3 buckets
  additional_task_role_policies = [aws_iam_policy.pdf_s3_access.arn]

  common_tags = {
    Name        = "${var.environment}-pdf-service"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "pdf-service"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "pdf_service_queue_url" {
  value       = module.pdf_service.queue_url
  description = "PDF service SQS queue URL — send jobs here to trigger PDF generation."
}

output "pdf_service_ecr_url" {
  value       = module.pdf_service.ecr_repository_url
  description = "PDF service ECR repository URL — push images here in CI."
}
