# ============================================================
# c2-variables.tf
# All input variables for the infrastructure.
# Grouped by subsystem: General, Networking, App/ECS,
# Valkey, Service Discovery, Security, Bedrock, S3, Email.
# ============================================================

# ------------------------------------------------------------
# General
# ------------------------------------------------------------

variable "environment" {
  description = "Deployment environment name (e.g. prod, stage)"
}

variable "project_id" {
  description = "AWS account ID — used to construct ECR image URIs"
}

variable "aws_region" {
  description = "AWS region where all resources are deployed"
}

# ------------------------------------------------------------
# VPC
# ------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
}

variable "az_count" {
  description = "Number of Availability Zones to span (creates equal private + public subnets)"
}

variable "hosted_zone" {
  description = "Route 53 hosted zone name (e.g. example.co.uk)"
}

variable "domain_name" {
  description = "Fully-qualified domain name for the API (e.g. api.example.co.uk)"
}

# ------------------------------------------------------------
# Application / ECS
# ------------------------------------------------------------

variable "app_port" {
  description = "Container port exposed by the Docker image"
}

variable "api_desired_instances_count" {
  description = "Baseline number of ECS tasks to keep running"
}

variable "health_check_path" {
  description = "HTTP path the ALB uses for target health checks"
  default     = "/health"
}

variable "fargate_cpu" {
  description = "Fargate task CPU units (1 vCPU = 1024 units)"
}

variable "fargate_memory" {
  description = "Fargate task memory in MiB"
}

variable "JWT_secret_arn" {
  description = "Secrets Manager ARN for the JWT signing secret"
}

variable "sns_topic" {
  description = "SNS topic ARN for CloudWatch alarm notifications"
}

# ------------------------------------------------------------
# Valkey (ElastiCache)
# ------------------------------------------------------------

variable "valkey_port" {
  description = "Port the Valkey cluster listens on"
  default     = 6379
}

variable "valkey_node_type" {
  description = "ElastiCache node type for Valkey (e.g. cache.t3.micro)"
  default     = "cache.t3.micro"
}

variable "valkey_maintenance_window" {
  description = "Weekly maintenance window in UTC (e.g. sun:05:00-sun:06:00)"
  default     = "sun:05:00-sun:06:00"
}

variable "valkey_snapshot_window" {
  description = "Daily backup snapshot window in UTC (e.g. 03:00-04:00)"
  default     = "03:00-04:00"
}

variable "valkey_cpu_alarm_threshold" {
  description = "CPU utilization % that triggers the Valkey CPU alarm"
  default     = 80
}

variable "valkey_memory_alarm_threshold" {
  description = "Memory utilization % that triggers the Valkey memory alarm"
  default     = 75
}

# ------------------------------------------------------------
# Service Discovery (Cloud Map)
# ------------------------------------------------------------

variable "enable_service_discovery" {
  description = "Enable Cloud Map service discovery for the API service"
  type        = bool
  default     = false
}

variable "service_discovery_namespace_id" {
  description = "ID of the Cloud Map private DNS namespace"
  type        = string
  default     = ""
}

# ------------------------------------------------------------
# Cross-Service Security Group
# When multiple ECS services need to communicate, a shared SG
# avoids tight coupling between individual service SGs.
# ------------------------------------------------------------

variable "enable_shared_security_group" {
  description = "Allow inbound traffic to the API from the shared ECS security group"
  type        = bool
  default     = false
}

variable "shared_security_group_id" {
  description = "ID of the shared ECS security group used for cross-service traffic"
  type        = string
  default     = ""
}

variable "use_shared_security_group" {
  description = "Attach shared SG to the ECS service instead of the API-specific one"
  type        = bool
  default     = false
}

# ------------------------------------------------------------
# Bedrock (AI)
# ------------------------------------------------------------

variable "allowed_bedrock_regions" {
  description = "AWS regions permitted for Bedrock model invocations (cross-region inference)"
  type        = list(string)
  default     = ["eu-west-2"]
}

# ------------------------------------------------------------
# S3 Buckets (external — passed in as ARNs)
# ------------------------------------------------------------

variable "kb_raw_bucket_arn" {
  description = "ARN of the S3 bucket containing raw documents for the Bedrock Knowledge Base"
  type        = string
}

variable "client_uploads_bucket_arn" {
  description = "ARN of the S3 bucket used for client file uploads"
  type        = string
}

# ------------------------------------------------------------
# Email (SendGrid Inbound Parse)
# ------------------------------------------------------------

variable "sendgrid_parse_subdomain" {
  description = "Subdomain for SendGrid inbound email parsing (e.g. parse.example.co.uk)"
  type        = string
}
