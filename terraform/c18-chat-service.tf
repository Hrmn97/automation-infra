# =============================================================================
# Chat Service — ALB-backed Fargate HTTP service (WebSocket / streaming chat)
#
# What this file provisions:
#   Calls the ecs-api-service module (terraform/modules/ecs-api-service/),
#   which creates: ECR repo, CloudWatch log group, ECS task def + service
#   (with circuit breaker + AZ rebalancing), ALB target group + listener rule,
#   optional service-discovery A record, App Auto Scaling (CPU + request-count),
#   CPU + memory CloudWatch alarms, IAM execution role + task role.
#
# How the chat service fits in:
#   - Receives requests via the shared ALB at path /chat and /chat/*
#     (listener rule priority 210 — adjust if rules conflict).
#   - Registers itself in service discovery as chat.<env>.servefirst.local
#     so that other services can reach it internally without an ALB hop.
#   - Calls the API internally via service discovery:
#     api.<env>.servefirst.local:<api_service_port>
#   - Connects to Valkey (Redis-compatible) for WebSocket session state.
#   - Calls Bedrock foundation models (Claude) for AI responses.
#     Bedrock InvokeModel is locked to var.allowed_bedrock_regions to
#     support cross-region inference profiles (e.g. eu.anthropic.*).
#
# Connections to the rest of the stack:
#   - c8-shared-security.tf  — shared SG lets chat reach api + valkey internally.
#   - c9-service-discovery.tf — namespace for chat.<env>.servefirst.local.
#   - c7-monitoring.tf       — aws_sns_topic.infrastructure_alerts for alarms.
#   - module.api_setup (c6)  — ALB listener ARN, ALB ARN, VPC, subnets,
#                               ECS cluster, Valkey endpoint/port.
#   - c21-outputs.tf         — re-exports chat_service_url, ECR URL, etc.
#
# Auto scaling (prod only):
#   CPU target 70% + request-count 500 req/target → scale 2–10 tasks.
#   Non-prod: auto scaling disabled, desired_count = 1.
#
# Drift note (sanity check §3.5):
#   ALLOWED_ORIGINS hardcodes stage/prod domains. var.allowed_bedrock_regions
#   drives IAM conditions for cross-region inference profiles.
# =============================================================================

module "chat_service" {
  source = "./modules/ecs-api-service"

  # Identity
  environment  = var.environment
  service_name = "chat"
  aws_region   = var.aws_region

  # Infrastructure from api-infra module (c6-main.tf)
  vpc_id             = module.api_setup.vpc_id
  subnet_ids         = module.api_setup.private_subnets
  security_group_ids = [aws_security_group.ecs_shared_tasks.id]
  ecs_cluster_id     = module.api_setup.ecs_cluster_id
  ecs_cluster_name   = module.api_setup.ecs_cluster_name

  # ALB — reuse the shared API ALB (no second load balancer needed)
  alb_listener_arn       = module.api_setup.alb_listener_arn
  alb_arn                = module.api_setup.alb_arn
  listener_rule_priority = 210
  path_patterns          = ["/chat", "/chat/*"]

  # Container
  container_port   = var.chat_service_port
  task_cpu         = var.environment == "prod" ? "512" : "256"
  task_memory      = var.environment == "prod" ? "1024" : "512"
  desired_count    = var.environment == "prod" ? 2 : 1
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
    {
      name = "SF_API_URL"
      # Internal service-discovery URL — avoids an ALB hop for API calls
      value = "http://api.${aws_service_discovery_private_dns_namespace.internal.name}:${var.api_service_port}"
    },
    {
      name  = "CHAT_PORT"
      value = tostring(var.chat_service_port)
    },
    {
      name  = "REDIS_HOST"
      value = module.api_setup.valkey_endpoint
    },
    {
      name  = "REDIS_PORT"
      value = tostring(module.api_setup.valkey_port)
    },
  ]

  env_file_arn = "arn:aws:s3:::tf-infra-automation-artifacts/${var.environment}-chat.env"

  secrets_arns = [{
    name      = "JWT_SECRET_OR_KEY"
    valueFrom = var.JWT_secret_arn
  }]

  # Bedrock IAM — locked to allowed regions to support cross-region inference
  # profiles (e.g. eu.anthropic.claude-sonnet-4-5-20250929-v1:0 routes to
  # any EU region). Wildcard region in ARN is intentional for inference profiles.
  task_role_policy_statements = [
    {
      effect    = "Allow"
      actions   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      resources = ["arn:aws:bedrock:*::foundation-model/*"]
      conditions = [{
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = var.allowed_bedrock_regions
      }]
    },
    {
      effect = "Allow"
      actions = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:GetInferenceProfile",
      ]
      resources = ["arn:aws:bedrock:*:*:inference-profile/*"]
      conditions = [{
        test     = "StringEquals"
        variable = "aws:RequestedRegion"
        values   = var.allowed_bedrock_regions
      }]
    },
  ]

  # Auto scaling — prod only
  enable_autoscaling       = var.environment == "prod"
  autoscaling_min_capacity = 2
  autoscaling_max_capacity = 10

  enable_cpu_scaling           = true
  cpu_scaling_target           = 70
  enable_memory_scaling        = false
  enable_request_count_scaling = true
  request_count_scaling_target = 500

  # Observability
  log_retention_days       = var.environment == "prod" ? 30 : 7
  enable_cloudwatch_alarms = true
  cpu_alarm_threshold      = 85
  memory_alarm_threshold   = 85
  alarm_sns_topic_arns     = [aws_sns_topic.infrastructure_alerts.arn]

  # Circuit breaker — rolls back automatically on failed deploy
  enable_circuit_breaker          = true
  enable_circuit_breaker_rollback = true

  # ECR scanning — prod only
  enable_ecr_image_scanning = var.environment == "prod"

  # Service discovery — registers chat.<env>.servefirst.local
  enable_service_discovery       = true
  service_discovery_namespace_id = aws_service_discovery_private_dns_namespace.internal.id

  common_tags = {
    Project     = "ServeFirst"
    Service     = "chat-service"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "chat_service_url" {
  value       = "https://${module.api_setup.alb_dns_name}/chat"
  description = "Public HTTPS URL for the chat service via the shared ALB."
}

output "chat_ecr_repository_url" {
  value       = module.chat_service.ecr_repository_url
  description = "ECR repository URL — push chat service images here in CI."
}

output "chat_service_name" {
  value       = module.chat_service.service_name
  description = "ECS service name — used by CI to trigger rolling deploys."
}

output "chat_log_group" {
  value       = module.chat_service.log_group_name
  description = "CloudWatch log group for the chat service."
}
