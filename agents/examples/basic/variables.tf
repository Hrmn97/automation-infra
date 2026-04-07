# Variables file for basic example
# These are pass-through variables to the root module

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "stage"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "openclaw-agents"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.100.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway"
  type        = bool
  default     = true
}

variable "enable_nat_gateway_per_az" {
  description = "NAT Gateway per AZ"
  type        = bool
  default     = false
}

variable "break_glass_mode" {
  description = "Disable internet access"
  type        = bool
  default     = false
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention"
  type        = number
  default     = 30
}

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for logs"
  type        = bool
  default     = true
}

variable "openclaw_default_version" {
  description = "Default OpenClaw version"
  type        = string
  default     = "v1.2.0"
}

variable "openclaw_container_registry" {
  description = "OpenClaw container registry"
  type        = string
  default     = "ghcr.io/openclaw/openclaw"
}

variable "agents" {
  description = "Agent configurations"
  type = map(object({
    instance_type               = string
    openclaw_version            = optional(string)
    bedrock_model_id            = string
    enable_marketplace          = optional(bool, false)
    detailed_monitoring         = optional(bool, false)
    root_volume_size_gb         = optional(number, 30)
    additional_iam_policies     = optional(list(string), [])
    subnet_index                = optional(number, 0)
    custom_security_group_rules = optional(list(object({
      type        = string
      from_port   = number
      to_port     = number
      protocol    = string
      cidr_blocks = list(string)
      description = string
    })), [])
  }))
  default = {}
}

variable "allowed_bedrock_regions" {
  description = "Allowed Bedrock regions"
  type        = list(string)
  default     = ["eu-west-2", "us-east-1", "us-west-2"]
}

variable "enable_ssm_session_logging" {
  description = "Enable SSM session logging"
  type        = bool
  default     = true
}

variable "allowed_ssm_principals" {
  description = "Allowed SSM principals"
  type        = list(string)
  default     = []
}

variable "additional_vpc_endpoint_services" {
  description = "Additional VPC endpoint services"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
