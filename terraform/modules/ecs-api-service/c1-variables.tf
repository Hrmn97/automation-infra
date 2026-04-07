# =============================================================================
# ecs-api-service module — input variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required — infrastructure context
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev, stage, prod)."
  type        = string
}

variable "service_name" {
  description = "Short root name, e.g. 'chat'. Module appends '-service' for AWS resource names."
  type        = string
}

variable "aws_region" {
  description = "AWS region, e.g. eu-west-2."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the service runs."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for ECS task network placement."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to ECS tasks."
  type        = list(string)
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name — needed for App Auto Scaling resource ID."
  type        = string
}

variable "alb_listener_arn" {
  description = "HTTPS ALB listener ARN — the module attaches a listener rule to this."
  type        = string
}

variable "alb_arn" {
  description = "ALB ARN — required only when enable_request_count_scaling = true."
  type        = string
  default     = ""
}

variable "listener_rule_priority" {
  description = "Priority for the ALB listener rule. Must be unique across all services on the same listener."
  type        = number
}

# -----------------------------------------------------------------------------
# Container
# -----------------------------------------------------------------------------

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "Fargate task CPU units (256, 512, 1024, 2048, 4096)."
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Fargate task memory in MB."
  type        = string
  default     = "512"
}

variable "cpu_architecture" {
  description = "CPU architecture (X86_64 or ARM64)."
  type        = string
  default     = "X86_64"
}

variable "ephemeral_storage_size" {
  description = "Fargate ephemeral storage in GiB (21–200)."
  type        = number
  default     = 21
}

variable "image_tag" {
  description = "Docker image tag to deploy."
  type        = string
  default     = "latest"
}

variable "additional_env_vars" {
  description = "Extra name/value env vars injected alongside NODE_ENV, PORT, AWS_REGION."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "env_file_arn" {
  description = "S3 ARN of a .env file loaded by ECS at task start."
  type        = string
  default     = ""
}

variable "secrets_arns" {
  description = "Secrets Manager secrets injected as env vars. Each entry needs name (env var key) and valueFrom (secret ARN)."
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "enable_container_health_check" {
  description = "Add a container-level HEALTHCHECK using curl against health_check_path."
  type        = bool
  default     = false
}

variable "enable_increased_ulimits" {
  description = "Set nofile ulimit to 65536/65536 — useful for high-connection services."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# ECS service
# -----------------------------------------------------------------------------

variable "desired_count" {
  description = "Initial desired task count. Ignored after first apply (lifecycle ignore_changes)."
  type        = number
  default     = 1
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percent during rolling deploy."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Maximum percent during rolling deploy."
  type        = number
  default     = 200
}

variable "health_check_grace_period" {
  description = "Seconds ECS waits before starting health checks on new tasks."
  type        = number
  default     = 60
}

variable "enable_circuit_breaker" {
  description = "Enable ECS deployment circuit breaker — stops a bad deploy automatically."
  type        = bool
  default     = true
}

variable "enable_circuit_breaker_rollback" {
  description = "Automatically roll back to the previous task definition when circuit breaker fires."
  type        = bool
  default     = true
}

variable "enable_capacity_providers" {
  description = "Enable capacity provider strategy (e.g. for Spot Fargate)."
  type        = bool
  default     = false
}

variable "capacity_provider_strategy" {
  description = "Capacity provider strategy entries."
  type = list(object({
    capacity_provider = string
    weight            = number
    base              = number
  }))
  default = []
}

# -----------------------------------------------------------------------------
# ALB routing
# -----------------------------------------------------------------------------

variable "path_patterns" {
  description = "URL path patterns for ALB listener rule (e.g. [\"/chat\", \"/chat/*\"])."
  type        = list(string)
  default     = []
}

variable "host_headers" {
  description = "Host headers for ALB listener rule (alternative or addition to path patterns)."
  type        = list(string)
  default     = []
}

variable "deregistration_delay" {
  description = "Target group deregistration delay in seconds — allows in-flight requests to drain."
  type        = number
  default     = 30
}

variable "enable_stickiness" {
  description = "Enable ALB session stickiness (lb_cookie)."
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Stickiness cookie duration in seconds."
  type        = number
  default     = 86400
}

# -----------------------------------------------------------------------------
# Health check
# -----------------------------------------------------------------------------

variable "health_check_path" {
  description = "HTTP path the ALB health check hits."
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between ALB health checks."
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Seconds the ALB waits for a health check response."
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes to mark a target healthy."
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures to mark a target unhealthy."
  type        = number
  default     = 3
}

variable "health_check_matcher" {
  description = "HTTP status codes accepted as healthy (e.g. \"200\" or \"200-299\")."
  type        = string
  default     = "200"
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------

variable "enable_autoscaling" {
  description = "Enable App Auto Scaling for the ECS service."
  type        = bool
  default     = false
}

variable "autoscaling_min_capacity" {
  description = "Minimum task count for auto scaling."
  type        = number
  default     = 1
}

variable "autoscaling_max_capacity" {
  description = "Maximum task count for auto scaling."
  type        = number
  default     = 10
}

variable "enable_cpu_scaling" {
  description = "Scale on average CPU utilisation."
  type        = bool
  default     = true
}

variable "cpu_scaling_target" {
  description = "Target CPU utilisation percentage for scaling."
  type        = number
  default     = 70
}

variable "enable_memory_scaling" {
  description = "Scale on average memory utilisation."
  type        = bool
  default     = false
}

variable "memory_scaling_target" {
  description = "Target memory utilisation percentage for scaling."
  type        = number
  default     = 80
}

variable "enable_request_count_scaling" {
  description = "Scale on ALBRequestCountPerTarget. Requires alb_arn."
  type        = bool
  default     = false
}

variable "request_count_scaling_target" {
  description = "Target requests-per-target for scaling."
  type        = number
  default     = 1000
}

variable "scale_in_cooldown" {
  description = "Seconds to wait after a scale-in event before allowing another."
  type        = number
  default     = 300
}

variable "scale_out_cooldown" {
  description = "Seconds to wait after a scale-out event before allowing another."
  type        = number
  default     = 60
}

# -----------------------------------------------------------------------------
# Observability
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 7
}

variable "enable_cloudwatch_alarms" {
  description = "Create CPU and memory CloudWatch alarms."
  type        = bool
  default     = true
}

variable "cpu_alarm_threshold" {
  description = "CPU utilisation % that triggers the high-CPU alarm."
  type        = number
  default     = 85
}

variable "memory_alarm_threshold" {
  description = "Memory utilisation % that triggers the high-memory alarm."
  type        = number
  default     = 85
}

variable "alarm_sns_topic_arns" {
  description = "SNS topic ARNs that receive alarm notifications."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Service Discovery
# -----------------------------------------------------------------------------

variable "enable_service_discovery" {
  description = "Register an A-record in the private DNS namespace (c9)."
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "ID of aws_service_discovery_private_dns_namespace (c9). Required when enable_service_discovery = true."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------

variable "task_execution_role_arn" {
  description = "Bring-your-own execution role ARN. When empty the module creates one."
  type        = string
  default     = ""
}

variable "task_role_arn" {
  description = "Bring-your-own task role ARN. When empty the module creates one."
  type        = string
  default     = ""
}

variable "task_role_policy_statements" {
  description = "Additional IAM policy statements merged into the task role custom policy. Supports optional per-statement conditions."
  type = list(object({
    effect    = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

# -----------------------------------------------------------------------------
# ECR
# -----------------------------------------------------------------------------

variable "enable_ecr_image_scanning" {
  description = "Scan images on push to ECR (recommended for prod)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Tagging
# -----------------------------------------------------------------------------

variable "common_tags" {
  description = "Tags merged onto every resource created by this module."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# GitHub repo management (optional, stage-only)
# -----------------------------------------------------------------------------

variable "create_github_repo" {
  description = "Create a GitHub repository for this service. Only acts in stage."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organisation."
  type        = string
  default     = "servefirstcx"
}

variable "service_display_name" {
  description = "Human-readable name used in repo descriptions and workflow files."
  type        = string
  default     = ""
}

variable "github_repo_visibility" {
  description = "GitHub repository visibility."
  type        = string
  default     = "private"
  validation {
    condition     = contains(["private", "public", "internal"], var.github_repo_visibility)
    error_message = "github_repo_visibility must be private, public, or internal."
  }
}

variable "github_repo_topics" {
  description = "Extra GitHub topics appended to the default set."
  type        = list(string)
  default     = []
}

variable "github_template_owner" {
  description = "Owner of a GitHub template repo to initialise from."
  type        = string
  default     = ""
}

variable "github_template_repo" {
  description = "Name of a GitHub template repo to initialise from."
  type        = string
  default     = ""
}

variable "create_workflows" {
  description = "Commit GitHub Actions workflow files into the new repo."
  type        = bool
  default     = true
}

variable "enable_branch_protection" {
  description = "Enable branch protection on main and stage branches."
  type        = bool
  default     = true
}

variable "required_approvals" {
  description = "PR approvals required to merge to main."
  type        = number
  default     = 1
}

variable "require_code_owner_reviews" {
  description = "Require code-owner review on PRs to main."
  type        = bool
  default     = true
}

variable "enforce_admins_on_main" {
  description = "Apply branch-protection rules to admins on main."
  type        = bool
  default     = false
}

variable "protect_stage_branch" {
  description = "Apply lighter branch-protection rules to the stage branch."
  type        = bool
  default     = true
}
