# Stage environment — root module variables (see terraform/c2-variables.tf)
# Apply: terraform init -backend-config=environments/stage/backend.hcl && terraform plan -var-file=environments/stage/stage.tfvars

# -----------------------------------------------------------------------------
# Core
# -----------------------------------------------------------------------------
environment = "stage"
aws_region  = "eu-west-2"
project_id  = "127424156127"

# -----------------------------------------------------------------------------
# DNS & domains (Route 53 zone: hosted_zone_domain)
# -----------------------------------------------------------------------------
hosted_zone_domain = "hrmn.pro"
fe_domain_name     = "stagev2.hrmn.pro"
front_domain_name  = "front-stage.hrmn.pro"
api_domain_name    = "stageapi.hrmn.pro"

sendgrid_parse_subdomain = "parse-stage.hrmn.pro"

# -----------------------------------------------------------------------------
# GitHub repos & branches (CI/CD + provider)
# -----------------------------------------------------------------------------
api_repo              = "servefirstcx/sf-api"
api_repo_branch       = "stage"
fe_repo               = "servefirstcx/sf-react-app"
fe_repo_front         = "servefirstcx/front-ratings"
fe_repo_branch        = "stage"
github_org            = "servefirstcx"
enable_github_actions = true
github_deploy_repo    = "sf-api"   # repo allowed to assume the stage deploy role
github_deploy_branch  = "stage"    # only the stage branch can trigger deploys

# -----------------------------------------------------------------------------
# API & networking (api-infra)
# -----------------------------------------------------------------------------
JWT_secret_arn              = "arn:aws:secretsmanager:eu-west-2:068531097348:secret:SFV2_stage-CKlcRD"
vpc_cidr                    = "172.16.0.0/16"
az_count                    = 2
api_desired_instances_count = 1
valkey_node_type            = "cache.t3.micro"

# -----------------------------------------------------------------------------
# MongoDB Atlas
# -----------------------------------------------------------------------------
ATLAS_VPC_CIDR             = "192.168.248.0/21"
ATLAS_PROJECT_ID           = "61e696c3e6540228f06a2daf"
mongodb_replication_factor = 3

# -----------------------------------------------------------------------------
# Product integrations
# -----------------------------------------------------------------------------
heap_env_id    = "4037358445"
chargebee_key  = "test_N2Co0wWkMXOZjTxY7ykTebqaqvUni40V"
chargebee_site = "servefirst-test"

# Bedrock: allow EU regions for cross-region inference profiles (eu.*)
allowed_bedrock_regions = [
  "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-central-2",
  "eu-north-1", "eu-south-1", "eu-south-2",
]
