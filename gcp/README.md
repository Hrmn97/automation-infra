# GCP Terraform

Manages Google Cloud Platform resources for ServeFirst.

## Structure

```
gcp/
├── provider.tf    # Google provider + backend config
├── variables.tf   # GCP-specific variables
└── oauth.tf       # OAuth consent screen + client credentials
```

## Setup

### Prerequisites

1. Install the `gcloud` CLI:
   ```bash
   brew install --cask google-cloud-sdk
   ```

2. Set your Terraform SA credentials:
   ```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/terraform-sa-key.json"
   ```

### Initialize

```bash
cd terraform/gcp
terraform init
```

### Plan / Apply

```bash
terraform plan
terraform apply
```

## State

GCP state is stored separately from AWS:
- **Bucket:** `tf-infra-automation-artifacts`
- **Key:** `terraform/gcp-state/terraform.tfstate`
- **Lock table:** `tf-state` (shared with AWS)

## Notes

- The OAuth consent screen "Internal" setting must be configured manually in GCP Console (one-time)
- OAuth client resources are commented out until the consent screen is ready
- Project: `servefirst` (project number: 314428023041)
