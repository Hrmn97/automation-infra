# =============================================================================
# Auth Service — ALB-backed Fargate HTTP service (Google OAuth + JWT)
#
# Centralised authentication and authorisation for SF internal tools.
# First consumer: sf-admin-app (admin dashboard).
# See: https://servefirst.atlassian.net/wiki/spaces/Eng/pages/228065281
#
# What this file provisions:
#   Calls the ecs-api-service module (terraform/modules/ecs-api-service/),
#   which creates: ECR repo, CloudWatch log group, ECS task def + service
#   (circuit breaker + AZ rebalancing), ALB target group + listener rule,
#   service-discovery A record, CloudWatch alarms, IAM execution + task roles.
#   Also creates the GitHub repository (stage-only via create_github_repo).
#   Plus 4 Secrets Manager secret stubs (values set manually after creation).
#
# How the auth service fits in:
#   - Mounted at ALB path /identity and /identity/* (priority 220, after chat).
#   - Registers auth.<env>.servefirst.local so services call it internally.
#   - Handles Google OAuth 2.0 flow and issues RS256 JWTs.
#   - Calls the API internally via service discovery for user lookups.
#   - Uses Valkey for refresh-token storage.
#   - Admin app (c20) is its primary consumer — ALLOWED_ORIGINS locked to
#     the admin domain per environment.
#
# Connections to the rest of the stack:
#   - c8-shared-security.tf  — shared SG allows auth to reach api + valkey.
#   - c9-service-discovery.tf — namespace for auth.<env>.servefirst.local.
#   - c7-monitoring.tf        — infrastructure_alerts SNS topic for alarms.
#   - module.api_setup (c6)   — ALB listener/ARN, VPC, subnets, ECS cluster,
#                                Valkey endpoint/port, ALB DNS name.
#   - c20-admin-app.tf        — admin app points its auth requests here.
#   - c21-outputs.tf          — re-exports auth_service_url, ECR URL, etc.
#
# Drift note (sanity check §3.5):
#   ALLOWED_ORIGINS hardcodes stage/prod admin domains. No dev case exists —
#   dev workspace will use the stage origin (admin-stage.servefirst.co.uk).
#   Add a dev branch to the conditional if a dev admin app is ever deployed.
# =============================================================================

locals {
  auth_service_base_path = "/identity"

  # ALLOWED_ORIGINS: prod → admin, stage/dev → admin-stage
  # (dev falls back to stage admin — intentional until a dev admin app exists)
  auth_allowed_origins = var.environment == "prod" ? "https://admin.servefirst.co.uk" : "https://admin-stage.servefirst.co.uk"
}

# -----------------------------------------------------------------------------
# Secrets Manager stubs — values must be set manually after first apply
#
# Naming convention: <env>/auth-service/<KEY>
# Keeping env in the path allows stage + prod secrets to coexist in the same
# account without collision.
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "auth_google_client_id" {
  name        = "${var.environment}/auth-service/GOOGLE_CLIENT_ID"
  description = "Google OAuth Client ID for SF Auth Service"

  tags = {
    Name        = "${var.environment}-auth-google-client-id"
    Service     = "auth-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret" "auth_google_client_secret" {
  name        = "${var.environment}/auth-service/GOOGLE_CLIENT_SECRET"
  description = "Google OAuth Client Secret for SF Auth Service"

  tags = {
    Name        = "${var.environment}-auth-google-client-secret"
    Service     = "auth-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret" "auth_jwt_private_key" {
  name        = "${var.environment}/auth-service/JWT_PRIVATE_KEY"
  description = "RSA private key for signing JWTs (RS256)"

  tags = {
    Name        = "${var.environment}-auth-jwt-private-key"
    Service     = "auth-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret" "auth_mongo_uri" {
  name        = "${var.environment}/auth-service/MONGO_URI"
  description = "MongoDB connection string for the sf-auth database"

  tags = {
    Name        = "${var.environment}-auth-mongo-uri"
    Service     = "auth-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Auth Service module call
# -----------------------------------------------------------------------------

module "auth_service" {
  source = "./modules/ecs-api-service"

  # Identity
  environment  = var.environment
  service_name = "auth"
  aws_region   = var.aws_region

  # Infrastructure from api-infra module (c6-main.tf)
  vpc_id             = module.api_setup.vpc_id
  subnet_ids         = module.api_setup.private_subnets
  security_group_ids = [aws_security_group.ecs_shared_tasks.id]
  ecs_cluster_id     = module.api_setup.ecs_cluster_id
  ecs_cluster_name   = module.api_setup.ecs_cluster_name

  # ALB — reuse the shared API ALB, mounted at /identity
  alb_listener_arn       = module.api_setup.alb_listener_arn
  alb_arn                = module.api_setup.alb_arn
  listener_rule_priority = 220 # After chat (210)
  path_patterns          = [local.auth_service_base_path, "${local.auth_service_base_path}/*"]

  # Container — lightweight auth service, no heavy compute needed
  container_port   = var.auth_service_port
  task_cpu         = "256"
  task_memory      = "512"
  desired_count    = 1
  cpu_architecture = "ARM64"

  # Health check
  health_check_path                = "/health"
  health_check_interval            = 30
  health_check_timeout             = 5
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 3
  health_check_grace_period        = 60

  # Environment variables
  additional_env_vars = [
    { name = "AUTH_PORT", value = tostring(var.auth_service_port) },
    { name = "JWT_ISSUER", value = "sf-auth-service" },
    { name = "JWT_AUDIENCE", value = "servefirst-internal" },
    { name = "JWT_ACCESS_TOKEN_EXPIRY", value = "15m" },
    { name = "JWT_REFRESH_TOKEN_EXPIRY_DAYS", value = "7" },
    { name = "SF_API_URL", value = "http://api.${aws_service_discovery_private_dns_namespace.internal.name}:${var.api_service_port}" },
    { name = "REDIS_HOST", value = module.api_setup.valkey_endpoint },
    { name = "REDIS_PORT", value = tostring(module.api_setup.valkey_port) },
    { name = "BASE_PATH", value = local.auth_service_base_path },
    { name = "ALLOWED_ORIGINS", value = local.auth_allowed_origins },
    { name = "AUTH_CALLBACK_URL", value = "https://${var.api_domain_name}${local.auth_service_base_path}/auth/google/callback" },
  ]

  # All config is in Secrets Manager or env vars above — no S3 env file needed
  env_file_arn = ""

  # Secrets injected as env vars by ECS agent
  secrets_arns = [
    { name = "GOOGLE_CLIENT_ID", valueFrom = aws_secretsmanager_secret.auth_google_client_id.arn },
    { name = "GOOGLE_CLIENT_SECRET", valueFrom = aws_secretsmanager_secret.auth_google_client_secret.arn },
    { name = "JWT_PRIVATE_KEY", valueFrom = aws_secretsmanager_secret.auth_jwt_private_key.arn },
    { name = "MONGO_URI", valueFrom = aws_secretsmanager_secret.auth_mongo_uri.arn },
  ]

  # No custom task role policies — auth doesn't call Bedrock, S3, or DynamoDB
  task_role_policy_statements = []

  # Auto scaling disabled — single instance is sufficient for now
  enable_autoscaling = false

  # Observability
  log_retention_days       = 7
  enable_cloudwatch_alarms = true
  cpu_alarm_threshold      = 85
  memory_alarm_threshold   = 85
  alarm_sns_topic_arns     = [aws_sns_topic.infrastructure_alerts.arn]

  # Circuit breaker — auto-rolls back on bad deploy
  enable_circuit_breaker          = true
  enable_circuit_breaker_rollback = true

  # ECR scanning disabled (non-prod only service currently)
  enable_ecr_image_scanning = false

  # Service discovery — registers auth.<env>.servefirst.local
  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.internal.id

  # GitHub repo (stage-only)
  create_github_repo       = true
  github_org               = var.github_org
  service_display_name     = "SF Auth Service"
  github_repo_visibility   = "private"
  github_repo_topics       = ["auth", "oidc", "internal-tools"]
  create_workflows         = true
  enable_branch_protection = true
  required_approvals       = 1

  common_tags = {
    Project     = "ServeFirst"
    Service     = "auth-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "auth_service_url" {
  value       = "https://${module.api_setup.alb_dns_name}${local.auth_service_base_path}"
  description = "Public HTTPS URL for the auth service via the shared ALB."
}

output "auth_ecr_repository_url" {
  value       = module.auth_service.ecr_repository_url
  description = "ECR repository URL — push auth service images here in CI."
}

output "auth_service_name" {
  value       = module.auth_service.service_name
  description = "ECS service name — used by CI to trigger rolling deploys."
}

output "auth_log_group" {
  value       = module.auth_service.log_group_name
  description = "CloudWatch log group for the auth service."
}

output "auth_service_discovery_name" {
  value       = module.auth_service.service_discovery_name
  description = "Service discovery name — auth.<env>.servefirst.local."
}
