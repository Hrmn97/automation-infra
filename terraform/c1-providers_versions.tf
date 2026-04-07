# ---------------------------------------------------------------------------
# Providers and versions
# ---------------------------------------------------------------------------

# No. of variables set in this file: 4
# 1. ATLAS_PUBLIC_KEY
# 2. aws_region
# 3. github_org
# 4. github_token

terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.31.0"
    }
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "1.2.0"
    }
    opensearch = {
      # Pinned exactly — the opensearch provider has historically had breaking changes
      source  = "opensearch-project/opensearch"
      version = "= 2.2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }

  # Remote state storage.
  # Backend values are supplied via environment-specific -backend-config files.
  backend "s3" {}
}

# ---------------------------------------------------------------------------
# AWS providers
# ---------------------------------------------------------------------------

provider "aws" {
  region  = "eu-west-2"
  profile = "sf-deploy"
}

# Required by the s3-cloudfront-app module — ACM certificates for CloudFront
# must be provisioned in us-east-1 regardless of the primary region.
provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  profile = "sf-deploy"
}

# ---------------------------------------------------------------------------
# MongoDB Atlas provider
# PRIVATE keys are sourced from Secrets Manager to keep credentials out of vars.
# ---------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "mongo_atlas_private_key" {
  secret_id = "MONGO_ATLAS_ORG_PRIVATE_KEY"
}

provider "mongodbatlas" {
  public_key  = var.ATLAS_PUBLIC_KEY
  private_key = data.aws_secretsmanager_secret_version.mongo_atlas_private_key.secret_string
}

# ---------------------------------------------------------------------------
# OpenSearch provider — manages indexes in the OpenSearch Serverless collection
# ---------------------------------------------------------------------------

provider "opensearch" {
  url               = aws_opensearchserverless_collection.kb.collection_endpoint
  healthcheck       = false
  sign_aws_requests = true
  aws_region        = var.aws_region
  aws_profile       = "sf-deploy"
}

# ---------------------------------------------------------------------------
# GitHub provider
# ---------------------------------------------------------------------------

provider "github" {
  # `owner` must be set to target org repos; without it the provider defaults
  # to the authenticated user and creates user-owned repositories.
  owner = var.github_org

  # Auth — in order of preference:
  #   1. Set TF_VAR_github_token to populate var.github_token
  #   2. Set GITHUB_TOKEN env var (provider falls back automatically when token = null)
  #   3. GitHub App: set GITHUB_APP_ID, GITHUB_INSTALLATION_ID, GITHUB_PEM_FILE
  token = var.github_token != "" ? var.github_token : null
}