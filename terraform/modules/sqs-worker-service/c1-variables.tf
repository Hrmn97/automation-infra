# =============================================================================
# sqs-worker-service module — input variables
# =============================================================================

# -----------------------------------------------------------------------------
# Required — infrastructure context
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (dev, stage, prod)."
  type        = string
}

variable "service_name" {
  description = "Short root name for the service, e.g. 'pdf'. The module appends '-service' for AWS resource names."
  type        = string
}

variable "aws_region" {
  description = "AWS region, e.g. eu-west-2."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID in which the ECS tasks run."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS task network placement."
  type        = list(string)
}

variable "ecs_cluster_id" {
  description = "ECS cluster ID that will run this service."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name — needed for App Auto Scaling resource ID."
  type        = string
}

# -----------------------------------------------------------------------------
# Networking / security
# -----------------------------------------------------------------------------

variable "security_group_ids" {
  description = "Security group IDs to attach to the ECS tasks. When empty the module creates a minimal egress-only SG."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Service Discovery (optional — workers normally skip this)
# -----------------------------------------------------------------------------

variable "enable_service_discovery" {
  description = "Register an A-record in the private DNS namespace. Set true only for services that expose an HTTP port."
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "ID of the aws_service_discovery_private_dns_namespace (c9). Required when enable_service_discovery = true."
  type        = string
  default     = ""
}

variable "service_discovery_port" {
  description = "HTTP port to register in service discovery. Must be > 0 when enable_service_discovery = true."
  type        = number
  default     = 0
}

# -----------------------------------------------------------------------------
# SQS queue tuning
# -----------------------------------------------------------------------------

variable "delay_seconds" {
  description = "Seconds a new message is invisible before becoming available (0–900)."
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Maximum SQS message size in bytes (1024–262144). Ignored after first apply due to lifecycle ignore."
  type        = number
  default     = 262144 # 256 KB
}

variable "retention_days" {
  description = <<-EOT
    Main queue message retention in days (prod); non-prod is always 1 day.
    Messages exceeding retention are deleted permanently — they do NOT go to DLQ.
    Minimum 0.0007 days (60 s), maximum 14 days.
  EOT
  type        = number
  default     = 1
}

variable "visibility_timeout" {
  description = "Seconds a received message is hidden from other consumers. Set higher than your worst-case processing time."
  type        = number
  default     = 300 # 5 minutes
}

variable "max_retries" {
  description = "Number of processing failures before a message is moved to the DLQ."
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# ECS task sizing
# -----------------------------------------------------------------------------

variable "task_cpu" {
  description = "CPU units for the Fargate task (256, 512, 1024, 2048, 4096)."
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory in MB for the Fargate task."
  type        = string
  default     = "512"
}

variable "cpu_architecture" {
  description = "CPU architecture for the Fargate task."
  type        = string
  default     = "X86_64"
  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

# -----------------------------------------------------------------------------
# Auto-scaling
# -----------------------------------------------------------------------------

variable "max_tasks" {
  description = "Maximum number of ECS tasks the auto-scaler can launch."
  type        = number
  default     = 10
}

variable "scale_up_threshold" {
  description = "ApproximateNumberOfMessagesVisible count that triggers a scale-up alarm."
  type        = number
  default     = 1
}

variable "scale_up_steps" {
  description = "Step-scaling steps for scale-up. Each step maps a message-count range to a task-count adjustment."
  type = list(object({
    lower_bound = number
    upper_bound = optional(number)
    adjustment  = number
  }))
  default = [
    { lower_bound = 0, upper_bound = 10, adjustment = 1 },
    { lower_bound = 10, upper_bound = 20, adjustment = 2 },
    { lower_bound = 20, adjustment = 3 },
  ]
}

variable "queue_age_threshold_seconds" {
  description = "ApproximateAgeOfOldestMessage alarm threshold in seconds. Default 15 minutes."
  type        = number
  default     = 900
}

# -----------------------------------------------------------------------------
# Container configuration
# -----------------------------------------------------------------------------

variable "additional_env_vars" {
  description = "Extra name/value pairs injected into the container alongside the standard SQS_QUEUE_URL, NODE_ENV, AWS_REGION."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "env_file_arn" {
  description = "S3 ARN of a .env file loaded by ECS at task start (e.g. arn:aws:s3:::bucket/key.env). Leave empty to skip."
  type        = string
  default     = ""
}

variable "secrets_arns" {
  description = "Secrets Manager ARNs exposed to the container via the secrets block."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Alarms
# -----------------------------------------------------------------------------

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for DLQ and queue-age alarms. Leave empty to disable notifications."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# IAM extensions
# -----------------------------------------------------------------------------

variable "additional_task_role_policies" {
  description = "Extra managed policy ARNs attached to the ECS task role (container → AWS service access)."
  type        = list(string)
  default     = []
}

variable "additional_execution_role_policies" {
  description = "Extra managed policy ARNs attached to the ECS task execution role (ECS agent → ECR/Secrets access)."
  type        = list(string)
  default     = []
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
  description = "Create a GitHub repository for this service. Only acts in stage environment."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organisation that will own the repository."
  type        = string
  default     = "servefirstcx"
}

variable "service_display_name" {
  description = "Human-readable service name used in GitHub repo descriptions and workflow files."
  type        = string
  default     = ""
}

variable "github_repo_visibility" {
  description = "GitHub repo visibility."
  type        = string
  default     = "private"
  validation {
    condition     = contains(["private", "public", "internal"], var.github_repo_visibility)
    error_message = "github_repo_visibility must be private, public, or internal."
  }
}

variable "github_repo_topics" {
  description = "Additional GitHub topics appended to the default set."
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
  description = "Enable branch protection rules on main and stage branches."
  type        = bool
  default     = true
}

variable "required_approvals" {
  description = "Number of PR approvals required to merge to main."
  type        = number
  default     = 1
}

variable "require_code_owner_reviews" {
  description = "Require code-owner review on PRs to main."
  type        = bool
  default     = true
}

variable "enforce_admins_on_main" {
  description = "Apply branch-protection rules to repository admins on main."
  type        = bool
  default     = false
}

variable "protect_stage_branch" {
  description = "Apply lighter branch-protection rules to the stage branch."
  type        = bool
  default     = true
}
