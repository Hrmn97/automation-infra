# Example Terraform variables for OpenClaw Agents
# Copy this file to ../../terraform.tfvars and customize

# AWS Configuration
aws_region  = "eu-west-2"
environment = "london"  # Just for tagging/naming resources

# Network Configuration
vpc_cidr           = "10.100.0.0/16"
availability_zones = ["eu-west-2a", "eu-west-2b"]

# NAT Gateway (required for npm install and outbound API calls)
enable_nat_gateway        = true
enable_nat_gateway_per_az = false # Set to true for HA (doubles NAT cost)

# Break-glass mode: disable all internet access (requires pre-baked AMI with Node + OpenClaw)
break_glass_mode = false

# Logging
cloudwatch_log_retention_days = 30
enable_vpc_flow_logs          = false # Enable for compliance/auditing
enable_kms_encryption         = true

# OpenClaw Configuration
# OpenClaw is installed via npm (openclaw@latest) in user_data.sh
# Version pinning is handled at the npm level, not via container registry

# Bedrock Configuration
# Cross-region inference profiles route to multiple EU regions automatically
allowed_bedrock_regions = [
  "eu-west-1",    # Ireland
  "eu-west-2",    # London
  "eu-west-3",    # Paris
  "eu-central-1", # Frankfurt
  "eu-central-2", # Zurich
  "eu-north-1",   # Stockholm
  "eu-south-1",   # Milan
  "eu-south-2",   # Spain
]

# Agent Definitions
agents = {
  # Research Agent - General purpose LLM tasks
  agent-one = {
    instance_type       = "m7i-flex.xlarge"
    bedrock_model_ids   = [
      "anthropic.claude-3-7-sonnet-20250219-v1:0",  # Sonnet 3.7 (direct, eu-west-2)
      "eu.anthropic.claude-opus-4-6-v1",       # Opus 4.6 (cross-region inference profile)
      "anthropic.claude-3-haiku-20240307-v1:0",  # Haiku (direct, eu-west-2)
      "eu.anthropic.claude-sonnet-4-6", # Sonnet 4.6 (cross-region inference profile)
      "eu.anthropic.claude-haiku-4-5-20251001-v1:0", # Haiku 4.5 (cross-region inference profile)
      "amazon.titan-embed-text-v2:0",           # Titan Embeddings v2 (for Mem0 vector store)
      "cohere.embed-v4:0",                     # Cohere Embed v4 (latest, unified English+multilingual)
    ]
    enable_marketplace      = false
    enable_self_diagnostics = true
    enable_host_metrics     = true
    enable_ebs_snapshots    = true  # Hourly (72 retain = 3 days) + Daily (30 retain = 1 month)
    detailed_monitoring = true
    root_volume_size_gb = 200
    gateway_port        = 18789
    subnet_index        = 0 # eu-west-2a
    custom_security_group_rules = [
      {
        type        = "egress"
        from_port   = 27017
        to_port     = 27017
        protocol    = "tcp"
        cidr_blocks = [
          "65.63.248.0/24",  # MongoDB Atlas prod (mongo-cluster-prod.ikybf.mongodb.net)
          "65.63.197.0/24",  # MongoDB Atlas stage shard-00-00
          "65.63.231.0/24",  # MongoDB Atlas stage shard-00-01
          "65.63.198.0/24",  # MongoDB Atlas stage shard-00-02
        ]
        description = "MongoDB Atlas - prod and stage clusters"
      },
      {
        type        = "egress"
        from_port   = 22
        to_port     = 22
        protocol    = "tcp"
        cidr_blocks = ["10.100.0.0/16"]  # VPC CIDR — SSH to vision instances via EC2 Instance Connect
        description = "SSH to vision training/pipeline instances (EC2 Instance Connect)"
      }
    ]
  }
}

# Optional: Additional VPC Endpoints
# additional_vpc_endpoint_services = [
#   "ecr.api",      # For pulling from ECR
#   "ecr.dkr",      # For pulling from ECR
#   "sts",          # For AssumeRole
# ]

# Vision Training Infrastructure (GPU spot instances + S3 for YOLO training)
enable_vision_training                  = true
vision_training_allowed_instance_types  = ["g5.xlarge", "g4dn.xlarge"]

# Tags
tags = {
  Owner       = "amayer"
  Team        = "Exec"
}

# SSM Session Manager
enable_ssm_session_logging = true

# Restrict SSM access to specific IAM principals (optional)
# allowed_ssm_principals = [
#   "arn:aws:iam::123456789012:role/AdminRole",
#   "arn:aws:iam::123456789012:user/ops-user"
# ]
