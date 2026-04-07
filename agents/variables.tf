variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name (e.g., stage, prod)"
  type        = string
  default     = "stage"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "openclaw-agents"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones (must be 2 for high availability)"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly 2 availability zones required for HA setup"
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for outbound internet access"
  type        = bool
  default     = true
}

variable "enable_nat_gateway_per_az" {
  description = "Create one NAT Gateway per AZ for high availability (increases cost)"
  type        = bool
  default     = false
}

variable "break_glass_mode" {
  description = "SECURITY: When true, removes all internet access (no NAT route). Requires Docker images pre-baked or from ECR."
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Must be a valid CloudWatch Logs retention period"
  }
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for CloudWatch Logs (additional cost)"
  type        = bool
  default     = true
}

variable "openclaw_default_version" {
  description = "OpenClaw version for reference/tagging. Install uses npm @latest."
  type        = string
  default     = "latest"
}

variable "agents" {
  description = "Map of agent configurations. Key is agent name."
  type = map(object({
    instance_type          = string
    openclaw_version       = optional(string)
    bedrock_model_ids      = list(string)
    enable_marketplace     = optional(bool, false)
    enable_self_diagnostics = optional(bool, false)
    enable_host_metrics    = optional(bool, false)
    detailed_monitoring    = optional(bool, false)
    root_volume_size_gb    = optional(number, 30)
    gateway_port           = optional(number, 18789)
    additional_iam_policies = optional(list(string), [])
    subnet_index           = optional(number, 0) # 0 or 1, spreads across AZs
    custom_security_group_rules = optional(list(object({
      type        = string
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
      description = string
    })), [])
    enable_ebs_snapshots   = optional(bool, false)
    snapshot_hourly_retain = optional(number, 72)
    snapshot_daily_retain  = optional(number, 30)
  }))

  default = {}

  validation {
    condition = alltrue([
      for name, config in var.agents :
      can(regex("^[a-z0-9-]+$", name))
    ])
    error_message = "Agent names must be lowercase alphanumeric with hyphens only"
  }

  validation {
    condition = alltrue([
      for name, config in var.agents :
      config.subnet_index >= 0 && config.subnet_index <= 1
    ])
    error_message = "subnet_index must be 0 or 1"
  }
}

variable "allowed_bedrock_regions" {
  description = "AWS regions where Bedrock API calls are allowed"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1", "us-west-2"]
}

variable "enable_ssm_session_logging" {
  description = "Enable logging of SSM Session Manager sessions to CloudWatch/S3"
  type        = bool
  default     = true
}

variable "allowed_ssm_principals" {
  description = "IAM principals (ARNs) allowed to start SSM sessions. Empty = all authenticated users in account."
  type        = list(string)
  default     = []
}

variable "additional_vpc_endpoint_services" {
  description = "Additional VPC endpoint services to create (e.g., ['ecr.api', 'ecr.dkr'])"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# --- OpenClaw Gateway & Channel Secrets ---

variable "telegram_bot_token" {
  description = "Telegram bot token from BotFather. Set via TF_VAR_telegram_bot_token env var."
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
