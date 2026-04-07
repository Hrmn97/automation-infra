terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "tf-infra-automation-artifacts"
    key            = "terraform/gcp-state/terraform.tfstate"
    region         = "eu-west-2"
    profile        = "sf-deploy"
    dynamodb_table = "tf-state"
    encrypt        = true
  }
}

# Auth: set GOOGLE_APPLICATION_CREDENTIALS env var to the Terraform SA key file
# e.g. export GOOGLE_APPLICATION_CREDENTIALS="/path/to/terraform-sa-key.json"
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}
