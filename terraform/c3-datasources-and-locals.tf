# Provides the AWS account ID and caller ARN — used in IAM and AOSS access
# policies across multiple files (e.g. c12-kb.tf, c13-github-actions-iam.tf).
data "aws_caller_identity" "current" {}

locals {
  service_name = "mongodb-atlas-vpc-peering"
  common_tags = {
    Environment = var.environment
    Service     = local.service_name
    ManagedBy   = "terraform"
  }
}