# =============================================================================
# Root module variables — used by c6-main.tf and child modules
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Deployment environment (prod, stage, dev)"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS account & networking
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_id" {
  description = "AWS account ID (project)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the application VPC"
  type        = string
}

variable "az_count" {
  description = "Number of availability zones"
  type        = number
}

# -----------------------------------------------------------------------------
# Domains & DNS
# -----------------------------------------------------------------------------

variable "hosted_zone_domain" {
  description = "Route 53 hosted zone domain (e.g. servefirst.co.uk)"
  type        = string
}

variable "fe_domain_name" {
  description = "Primary frontend hostname (main React app)"
  type        = string
}

variable "front_domain_name" {
  description = "Ratings / secondary frontend hostname"
  type        = string
}

variable "api_domain_name" {
  description = "API hostname (TLS / Route53)"
  type        = string
}

# -----------------------------------------------------------------------------
# API application (api-infra)
# -----------------------------------------------------------------------------

variable "JWT_secret_arn" {
  description = "ARN of the JWT secret in Secrets Manager"
  type        = string
}

variable "api_desired_instances_count" {
  description = "Desired count of API ECS tasks"
  type        = number
}

variable "api_service_port" {
  description = "Container port for the main API service"
  type        = number
  default     = 5000
}

# -----------------------------------------------------------------------------
# Redis (Valkey)
# -----------------------------------------------------------------------------

variable "valkey_node_type" {
  description = "ElastiCache / Valkey node instance class"
  type        = string
  default     = "cache.t3.micro"
}

# -----------------------------------------------------------------------------
# Integrations — analytics, billing, email, AI
# -----------------------------------------------------------------------------

variable "heap_env_id" {
  description = "Heap analytics environment ID (frontend builds)"
  type        = string
}

variable "chargebee_key" {
  description = "Chargebee publishable key"
  type        = string
}

variable "chargebee_site" {
  description = "Chargebee site name"
  type        = string
}

variable "sendgrid_parse_subdomain" {
  description = "Subdomain for SendGrid inbound parse (e.g. parse.dev.servefirst.co.uk)"
  type        = string
}

variable "allowed_bedrock_regions" {
  description = "AWS regions allowed for Bedrock calls (cross-region inference profiles)"
  type        = list(string)
  default     = ["eu-west-2"]
}

# -----------------------------------------------------------------------------
# CI/CD — repositories & GitHub Actions
# -----------------------------------------------------------------------------

variable "api_repo" {
  description = "GitHub repo for the API (org/repo)"
  type        = string
}

variable "api_repo_branch" {
  description = "Branch monitored by CodePipeline for the API"
  type        = string
}

variable "fe_repo" {
  description = "GitHub repo for the primary frontend"
  type        = string
}

variable "fe_repo_front" {
  description = "GitHub repo for the ratings / secondary frontend"
  type        = string
}

variable "fe_repo_branch" {
  description = "Branch monitored for frontends"
  type        = string
}

variable "enable_github_actions" {
  description = "If true, CodePipeline source branch is disabled so GitHub Actions can deploy"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# GitHub provider (optional repos / automation)
# -----------------------------------------------------------------------------

variable "github_org" {
  description = "GitHub organization for provider and repo-scoped resources"
  type        = string
  default     = "servefirstcx"
}

variable "github_token" {
  description = "GitHub token — prefer TF_VAR_github_token or GITHUB_TOKEN"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_deploy_repo" {
  description = "GitHub repo name (without org prefix) that is allowed to assume the OIDC deploy role. E.g. 'serveFirst-backend'."
  type        = string
  default     = "serveFirst-backend"
}

variable "github_deploy_branch" {
  description = "Git branch that is allowed to assume the OIDC deploy role. Tighten to 'main' or 'master' in prod."
  type        = string
  default     = "main"
}

# -----------------------------------------------------------------------------
# MongoDB Atlas
# -----------------------------------------------------------------------------

variable "ATLAS_PUBLIC_KEY" {
  description = "MongoDB Atlas API public key"
  type        = string
  default     = "phixozkt"
}

variable "ATLAS_PRIVATE_KEY" {
  description = "MongoDB Atlas API private key (prefer Secrets Manager in provider)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ATLAS_PROJECT_ID" {
  description = "MongoDB Atlas project ID"
  type        = string
}

variable "ATLAS_VPC_CIDR" {
  description = "CIDR of the Atlas peered network (for routes / access list)"
  type        = string
}

variable "ATLAS_PROVIDER" {
  description = "Atlas cloud provider name"
  type        = string
  default     = "AWS"
}

variable "atlas_region" {
  description = "Atlas region identifier (e.g. EU_WEST_2)"
  type        = string
  default     = "EU_WEST_2"
}

variable "mongodb_replication_factor" {
  description = "Number of data-bearing members in the Atlas cluster"
  type        = number
}

# -----------------------------------------------------------------------------
# Optional — additional ECS / ALB service ports (e.g. microservices)
# -----------------------------------------------------------------------------

variable "chat_service_port" {
  description = "Port for the chat service behind the ALB"
  type        = number
  default     = 7070
}

variable "auth_service_port" {
  description = "Port for the auth service behind the ALB"
  type        = number
  default     = 3100
}

variable "ecs_service_ports" {
  description = "Extra ingress rules for shared security groups (port + description)"
  type = list(object({
    port        = number
    description = string
  }))
  default = []
}
