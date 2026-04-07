# OpenClaw Agent Infrastructure

Production-grade AWS infrastructure for running isolated OpenClaw agent runtimes on EC2 with Bedrock integration.

## Quick Reference

| Aspect | Details |
|--------|---------|
| **Location** | `/terraform/agents/` |
| **Provider** | AWS (Terraform ~> 5.0) |
| **Network** | Dedicated VPC, private subnets, VPC endpoints |
| **Security** | Zero inbound, IMDSv2, least privilege IAM, KMS encryption |
| **LLM Provider** | AWS Bedrock (no API keys) |
| **Access** | SSM Session Manager only |
| **Logging** | CloudWatch Logs (30-day retention) |
| **Isolation** | Per-agent security groups, IAM roles, log groups, secrets |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          VPC (10.100.0.0/16)                    │
│                                                                 │
│  ┌───────────────┐                    ┌───────────────┐       │
│  │ Public Subnet │                    │ Public Subnet │       │
│  │   (AZ-A)      │                    │   (AZ-B)      │       │
│  │               │                    │               │       │
│  │  NAT Gateway  │                    │ (NAT Gateway) │       │
│  └───────┬───────┘                    └───────────────┘       │
│          │                                                     │
│  ┌───────▼───────────────────┐   ┌────────────────────────┐  │
│  │   Private Subnet (AZ-A)    │   │ Private Subnet (AZ-B)  │  │
│  │                            │   │                        │  │
│  │  ┌──────────────────────┐ │   │ ┌──────────────────┐  │  │
│  │  │  Agent Instance      │ │   │ │  Agent Instance  │  │  │
│  │  │  ┌────────────────┐  │ │   │ │ ┌──────────────┐ │  │  │
│  │  │  │  OpenClaw      │  │ │   │ │ │  OpenClaw    │ │  │  │
│  │  │  │  (Docker)      │  │ │   │ │ │  (Docker)    │ │  │  │
│  │  │  └────────────────┘  │ │   │ │ └──────────────┘ │  │  │
│  │  │  IMDSv2 | gp3 EBS   │ │   │ │  IMDSv2 | gp3   │  │  │
│  │  │  Encrypted           │ │   │ │  Encrypted       │  │  │
│  │  └──────────────────────┘ │   │ └──────────────────┘  │  │
│  └────────────────────────────┘   └────────────────────────┘  │
│                                                                 │
│  VPC Endpoints:                                                │
│  • SSM, EC2Messages, SSMMessages (Session Manager)            │
│  • Bedrock Runtime (LLM API)                                  │
│  • CloudWatch Logs                                             │
│  • Secrets Manager, SSM Parameter Store                       │
│  • S3 Gateway                                                  │
└─────────────────────────────────────────────────────────────────┘

             ▲
             │ SSM Session Manager
             │ (Port 443)
             │
        ┌────┴────┐
        │ Admin   │
        │ (AWS)   │
        └─────────┘
```

## Key Features

### 🔒 Security First

- **Default Deny**: Zero inbound, HTTPS egress only
- **No SSH**: SSM Session Manager access only
- **Least Privilege**: IAM scoped to specific resources and models
- **Isolation**: Each agent has its own SG, IAM role, log group, secrets namespace
- **Encryption**: IMDSv2, EBS encryption, KMS for logs
- **Auditability**: CloudTrail, CloudWatch Logs, VPC Flow Logs (optional)

### 🧩 Modular Design

- **Network Module**: Reusable VPC foundation
- **Agent Module**: Spin up N isolated agents
- **Root Module**: Orchestrates network + agents

### 🤖 OpenClaw Integration

- **Pinned Versions**: No `latest` tags, semver only
- **Bedrock Provider**: AWS-native LLM access via IAM
- **Marketplace Control**: Third-party skills disabled by default
- **Auto-Start**: systemd service with health checks
- **Log Shipping**: CloudWatch Logs integration

### 🔧 Operational Excellence

- **Infrastructure as Code**: Full Terraform, no ClickOps
- **Repeatable**: Spin up identical environments
- **Observable**: CloudWatch metrics, logs, alarms
- **Recoverable**: State in S3, destroy/recreate anytime

## Repository Structure

```
agents/
├── README.md                    # User guide
├── DEPLOYMENT.md                # Step-by-step deployment
├── SECURITY.md                  # Security architecture
├── AGENTS.md                    # This file (overview)
├── versions.tf                  # Terraform/provider versions
├── variables.tf                 # Root input variables
├── outputs.tf                   # Root outputs
├── main.tf                      # Root orchestration
├── .gitignore                   # Ignore tfstate, secrets
│
├── modules/
│   ├── network/                 # VPC, subnets, NAT, VPC endpoints
│   │   ├── main.tf
│   │   ├── vpc_endpoints.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── agent_ec2/               # Reusable agent instance module
│       ├── main.tf              # EC2 instance, security group
│       ├── iam.tf               # IAM role, policies
│       ├── user_data.sh         # Bootstrap script
│       ├── variables.tf
│       └── outputs.tf
│
└── examples/
    └── basic/                   # Example deployment
        ├── main.tf
        ├── variables.tf
        └── terraform.tfvars.example
```

## Usage Patterns

### Single Agent (Minimal)

```hcl
# terraform.tfvars
agents = {
  research-agent = {
    instance_type    = "t3.medium"
    bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
  }
}
```

### Multiple Agents (Different Models)

```hcl
agents = {
  research-agent = {
    instance_type    = "t3.medium"
    bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
  }
  
  qa-agent = {
    instance_type    = "t3.small"
    bedrock_model_id = "anthropic.claude-3-haiku-20240307-v1:0"
  }
  
  code-review-agent = {
    instance_type    = "t3.large"
    bedrock_model_id = "anthropic.claude-3-opus-20240229-v1:0"
    detailed_monitoring = true
    root_volume_size_gb = 50
  }
}
```

### High Security (Air-Gapped)

```hcl
break_glass_mode = true  # No NAT, no internet
enable_vpc_flow_logs = true
enable_kms_encryption = true

# Requires:
# - Pre-baked AMI with Docker + OpenClaw
# - Or ECR with OpenClaw image (add ECR endpoints)
```

### Multi-Region (Bedrock)

```hcl
allowed_bedrock_regions = ["eu-west-2", "eu-west-1"]  # EU-only for GDPR

agents = {
  eu-agent = {
    bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
  }
}
```

## Common Operations

### Deploy

```bash
cd terraform/agents
terraform init
terraform plan
terraform apply
```

### Connect to Agent

```bash
# Get instance ID
terraform output -json agent_instances | jq -r '.["research-agent"].instance_id'

# Start session
aws ssm start-session --target i-1234567890abcdef0
```

### View Logs

```bash
# CloudWatch
aws logs tail /openclaw/agent/research-agent --follow

# On instance
sudo journalctl -u openclaw-agent -f
sudo docker logs -f openclaw-agent-research-agent
```

### Add Agent

```hcl
# Edit terraform.tfvars, add new agent
agents = {
  existing-agent = { ... }
  new-agent = { ... }  # Add this
}
```

```bash
terraform apply
```

### Update OpenClaw Version

```hcl
# terraform.tfvars
agents = {
  research-agent = {
    openclaw_version = "v1.3.0"  # Was v1.2.0
    # ...
  }
}
```

```bash
terraform apply  # Blue/green replacement
```

### Destroy

```bash
terraform destroy
```

## Security Model

### Network Isolation

```
Agent Instance:
  ✓ Private subnet (no public IP)
  ✓ Security group: zero inbound
  ✓ Security group: HTTPS egress only
  ✗ No SSH (SSM only)
  ✗ No RDP
  ✗ No direct internet (via NAT or VPC endpoints)
```

### IAM Permissions

```
Per-Agent Role:
  ✓ Bedrock: InvokeModel for SPECIFIC model ARN
  ✓ CloudWatch Logs: PutLogEvents to /openclaw/agent/{name}
  ✓ Secrets: GetSecretValue for /openclaw/agents/{name}/*
  ✓ SSM: Managed instance core
  ✗ NO S3, DynamoDB, Lambda (unless explicitly added)
  ✗ NO other agents' resources
  ✗ NO cross-account access
```

### Data Protection

```
At Rest:
  ✓ EBS encrypted (AWS-managed or CMK)
  ✓ CloudWatch Logs encrypted with KMS
  ✓ Secrets in Parameter Store (encrypted)

In Transit:
  ✓ TLS 1.2+ for all AWS API calls
  ✓ VPC endpoints (private connectivity)
  ✓ SSM Session Manager (encrypted tunnel)
```

## Integration Guide

### With Existing VPC

Replace the network module with your existing VPC:

```hcl
# main.tf
# Comment out:
# module "network" { ... }

# Use existing VPC
data "aws_vpc" "existing" {
  id = "vpc-xxxxx"
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
  tags = {
    Tier = "Private"
  }
}

# Update agent module
module "agents" {
  vpc_id            = data.aws_vpc.existing.id
  private_subnet_id = data.aws_subnets.private.ids[0]
  # ...
}
```

### With External Secrets

Use Secrets Manager instead of Parameter Store:

```bash
# Store secrets
aws secretsmanager create-secret \
  --name /openclaw/agents/research-agent/api-key \
  --secret-string "secret-value"

# Agent config automatically reads from Secrets Manager
# (IAM role already has permissions)
```

### With S3 Tool Access

See `modules/agent_ec2/iam.tf` for commented examples:

```hcl
# Uncomment and customize
variable "enable_s3_access" { default = false }
variable "allowed_s3_buckets" { default = [] }

# In terraform.tfvars
agents = {
  research-agent = {
    # ... existing config ...
    additional_iam_policies = [
      # Option 1: Managed policy
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    ]
  }
}
```

### With CI/CD

```yaml
# GitHub Actions example
- name: Deploy OpenClaw Agents
  run: |
    cd terraform/agents
    terraform init \
      -backend-config="bucket=${{ secrets.TF_STATE_BUCKET }}" \
      -backend-config="key=agents/terraform.tfstate"
    terraform plan -out=tfplan
    terraform apply tfplan
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Roadmap

- [ ] Auto Scaling Groups for agent pools
- [ ] Internal ALB for agent API endpoints
- [ ] Egress proxy with domain allowlist
- [ ] AMI baking pipeline (Packer)
- [ ] GuardDuty / Falco runtime protection
- [ ] Secrets rotation automation
- [ ] Multi-region deployment module
- [ ] Cost anomaly detection
- [ ] Patch management automation

## Contributing

1. Test changes in `examples/basic/` first
2. Run `terraform fmt -recursive`
3. Run `terraform validate`
4. Update documentation if changing interfaces
5. No secrets in code or comments

## Support

- **Terraform Issues**: Check `terraform.log`, CloudTrail
- **Agent Issues**: Check CloudWatch Logs, SSM to instance
- **Security**: See [SECURITY.md](SECURITY.md)
- **Deployment**: See [DEPLOYMENT.md](DEPLOYMENT.md)

## License

Internal use - ServeFirst
