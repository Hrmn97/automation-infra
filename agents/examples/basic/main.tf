# Example: Basic OpenClaw Agents Deployment
# This is a minimal example showing how to use the root module

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Project     = "OpenClaw-Agents"
      Environment = var.environment
      Example     = "basic"
    }
  }
}

# Use the root module directly
module "openclaw_agents" {
  source = "../../" # Points to the root agents/ directory

  # Pass through all variables
  aws_region         = var.aws_region
  environment        = var.environment
  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones

  enable_nat_gateway        = var.enable_nat_gateway
  enable_nat_gateway_per_az = var.enable_nat_gateway_per_az
  break_glass_mode          = var.break_glass_mode
  enable_vpc_flow_logs      = var.enable_vpc_flow_logs

  cloudwatch_log_retention_days = var.cloudwatch_log_retention_days
  enable_kms_encryption         = var.enable_kms_encryption

  openclaw_default_version    = var.openclaw_default_version
  openclaw_container_registry = var.openclaw_container_registry

  agents = var.agents

  allowed_bedrock_regions = var.allowed_bedrock_regions

  enable_ssm_session_logging = var.enable_ssm_session_logging
  allowed_ssm_principals     = var.allowed_ssm_principals

  additional_vpc_endpoint_services = var.additional_vpc_endpoint_services

  tags = var.tags
}

# Outputs
output "vpc_id" {
  value = module.openclaw_agents.vpc_id
}

output "agent_instances" {
  value = module.openclaw_agents.agent_instances
}

output "ssm_connection_commands" {
  value = module.openclaw_agents.ssm_connection_commands
}

output "cloudwatch_log_commands" {
  value = module.openclaw_agents.cloudwatch_log_commands
}

output "network_security_summary" {
  value = module.openclaw_agents.network_security_summary
}
