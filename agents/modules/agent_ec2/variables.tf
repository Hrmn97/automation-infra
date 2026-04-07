variable "agent_name" {
  description = "Unique name for this agent (lowercase alphanumeric with hyphens)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.agent_name))
    error_message = "Agent name must be lowercase alphanumeric with hyphens only"
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., stage, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where agent will be deployed"
  type        = string
}

variable "private_subnet_id" {
  description = "Private subnet ID for agent instance (must NOT be public)"
  type        = string

  validation {
    condition     = length(var.private_subnet_id) > 0
    error_message = "Private subnet ID must be provided"
  }
}

variable "vpc_endpoint_sg_id" {
  description = "Security group ID for VPC endpoints"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^t3\\.|^t3a\\.|^t4g\\.|^m5\\.|^m6i\\.|^m7i\\.|^m7i-flex\\.|^c5\\.", var.instance_type))
    error_message = "Instance type should be general purpose or compute optimized (t3, t3a, t4g, m5, m6i, m7i, m7i-flex, c5 families)"
  }
}

variable "root_volume_size_gb" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 30

  validation {
    condition     = var.root_volume_size_gb >= 20 && var.root_volume_size_gb <= 1000
    error_message = "Root volume size must be between 20 and 1000 GB"
  }
}

variable "detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (1-min intervals, additional cost)"
  type        = bool
  default     = false
}

variable "openclaw_version" {
  description = "OpenClaw version tag for reference/tagging. Install uses npm @latest."
  type        = string
  default     = "latest"
}

variable "bedrock_model_ids" {
  description = "Bedrock model IDs to allow. Supports foundation models and cross-region inference profiles. First entry is the default model in user_data."
  type        = list(string)

  validation {
    condition     = length(var.bedrock_model_ids) > 0
    error_message = "At least one Bedrock model ID must be specified"
  }
}

variable "enable_marketplace" {
  description = "Enable third-party skill marketplace (SECURITY: default false)"
  type        = bool
  default     = false
}

variable "allowed_bedrock_regions" {
  description = "AWS regions where Bedrock API calls are allowed"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1", "us-west-2"]
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "kms_key_id" {
  description = "KMS key ID for CloudWatch Logs encryption (optional)"
  type        = string
  default     = null
}

variable "custom_security_group_rules" {
  description = "Additional security group rules (use with caution)"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}

variable "enable_self_diagnostics" {
  description = "Grant read-only access to EC2, VPC, CloudWatch, and own IAM role for self-troubleshooting"
  type        = bool
  default     = false
}

variable "enable_host_metrics" {
  description = "Enable CloudWatch agent host metrics (CPU, memory, disk, swap), dashboard, and alarms"
  type        = bool
  default     = false
}

variable "host_metrics_namespace" {
  description = "CloudWatch custom namespace for host metrics"
  type        = string
  default     = "OpenClaw/AgentHost"
}

variable "host_metrics_interval" {
  description = "Metrics collection interval in seconds"
  type        = number
  default     = 300
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarm notifications (optional, alarms still fire without it)"
  type        = string
  default     = ""
}

variable "additional_iam_policies" {
  description = "Additional IAM policy ARNs to attach to instance role (use with caution)"
  type        = list(string)
  default     = []
}

variable "enable_ebs_snapshots" {
  description = "Enable automated EBS snapshots via AWS DLM (hourly + daily)"
  type        = bool
  default     = false
}

variable "snapshot_hourly_retain" {
  description = "Number of hourly snapshots to retain"
  type        = number
  default     = 72 # 3 days
}

variable "snapshot_daily_retain" {
  description = "Number of daily snapshots to retain"
  type        = number
  default     = 30 # 1 month
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# --- OpenClaw Gateway & Channel Configuration ---

variable "gateway_port" {
  description = "Port for the OpenClaw gateway (Control UI + WebSocket)"
  type        = number
  default     = 18789
}

variable "telegram_bot_token" {
  description = "Telegram bot token from BotFather (sensitive)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gateway_auth_token" {
  description = "Auth token for the OpenClaw Control UI. Leave empty to auto-generate."
  type        = string
  sensitive   = true
  default     = ""
}
