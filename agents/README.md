# Safe OpenClaw Agent Runners on AWS EC2

Production-grade Terraform infrastructure for running OpenClaw agent runtimes on EC2 with strong isolation, security guardrails, and AWS Bedrock integration.

> **📚 New here?** See [INDEX.md](INDEX.md) for a complete documentation map, or jump to [QUICKSTART.md](QUICKSTART.md) to deploy in 15 minutes.

## Architecture Overview

This Terraform configuration creates:

- **Dedicated VPC** with public/private subnets across 2 AZs
- **VPC Endpoints** for AWS services (SSM, CloudWatch, Secrets Manager, Bedrock)
- **Isolated Agent Instances** - each agent gets:
  - Dedicated security group (zero inbound, restricted egress)
  - Dedicated IAM role (least privilege, Bedrock-only model access)
  - Dedicated CloudWatch log group (KMS encrypted)
  - Dedicated secrets namespace in SSM Parameter Store
- **No Public Access** - SSM Session Manager only, no SSH, no public IPs
- **IMDSv2 Required** - prevents SSRF attacks
- **Encrypted Storage** - gp3 volumes with encryption
- **Bedrock Integration** - no API keys, uses AWS IAM for model access

## Security Principles

1. **Default Deny** - All ingress blocked, egress restricted to HTTPS
2. **Least Privilege** - Minimal IAM permissions, scoped to specific resources
3. **Defense in Depth** - Network isolation + IAM + encryption + logging
4. **No Secrets in Code** - Bedrock via IAM, secrets in Parameter Store
5. **Auditability** - CloudWatch logs with retention, detailed monitoring optional

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured with appropriate credentials
- AWS account with Bedrock enabled in target region
- Model access granted in Bedrock console (e.g., Claude 3, Titan)

## Quick Start

```bash
cd terraform/agents

# Review and customize
cp examples/basic/terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Initialize
terraform init

# Plan
terraform plan

# Apply
terraform apply

# Access an agent via SSM
aws ssm start-session --target <instance-id>

# View logs
aws logs tail /openclaw/agent/research-agent --follow
```

## Module Structure

```
agents/
├── modules/
│   ├── network/          # VPC, subnets, NAT, VPC endpoints
│   └── agent_ec2/        # Reusable agent instance module
├── main.tf               # Root orchestration
├── variables.tf          # Input variables
├── outputs.tf            # Outputs (instance IDs, SSM targets)
├── versions.tf           # Provider versions
└── examples/
    └── basic/            # Example configuration
```

## Configuration

### Network Module

Creates the foundation VPC with:
- 2 AZs, 2 private + 2 public subnets
- NAT Gateway for outbound internet (can be disabled with `break_glass_mode`)
- VPC Endpoints: SSM, EC2Messages, SSMMessages, CloudWatch Logs, Secrets Manager, Bedrock Runtime, S3 Gateway

### Agent Module

Each agent instance includes:
- EC2 instance in private subnet (no public IP)
- Security group with egress to HTTPS only
- IAM role with Bedrock model access (specific model ARN)
- CloudWatch log group with 30-day retention
- SSM Parameter Store namespace: `/openclaw/agents/<agent-name>/*`
- User data script that:
  - Installs Docker + Docker Compose
  - Pulls pinned OpenClaw container image
  - Creates systemd service for auto-restart
  - Configures Bedrock as LLM provider
  - Ships logs to CloudWatch

## Agent Configuration

Define agents in `terraform.tfvars`:

```hcl
agents = {
  research-agent = {
    instance_type     = "t3.medium"
    openclaw_version  = "v1.2.0"  # Pin to specific release
    bedrock_model_id  = "anthropic.claude-3-sonnet-20240229-v1:0"
    enable_marketplace = false     # Disable third-party skills
    detailed_monitoring = true
  }
  
  qa-agent = {
    instance_type     = "t3.small"
    openclaw_version  = "v1.2.0"
    bedrock_model_id  = "amazon.titan-text-express-v1"
    enable_marketplace = false
  }
}
```

## Security Features

### Network Isolation
- Private subnets only, no public IPs
- Security groups with zero inbound
- Egress restricted to TCP/443
- VPC endpoints for AWS service access (no NAT required)

### IAM Permissions (Per Agent)
- SSM Session Manager access
- CloudWatch Logs write (scoped to agent's log group)
- Secrets Manager/Parameter Store read (scoped to agent's namespace)
- Bedrock InvokeModel (scoped to specific model ARN only)
- NO S3, NO Lambda, NO DynamoDB by default

### Instance Hardening
- IMDSv2 required (prevents SSRF)
- gp3 encrypted volumes
- Latest Amazon Linux 2023 AMI
- Automatic security updates enabled
- CloudWatch detailed monitoring (optional)

### Break-Glass Mode

For maximum security, disable outbound internet entirely:

```hcl
break_glass_mode = true  # Removes NAT gateway route
```

In this mode:
- All outbound traffic goes through VPC endpoints only
- Docker image must be pre-baked into AMI or pulled from ECR
- Useful for air-gapped or highly regulated environments

## Adding Tool Access Safely

To grant an agent access to AWS services (e.g., S3, DynamoDB):

1. Create a separate IAM policy with minimal permissions
2. Attach via module variable (not enabled by default)
3. Use condition keys to restrict further

Example in `modules/agent_ec2/variables.tf`:

```hcl
variable "enable_s3_access" {
  type        = bool
  default     = false
  description = "Enable S3 read-only access for agent"
}

variable "allowed_s3_buckets" {
  type        = list(string)
  default     = []
  description = "List of S3 bucket ARNs agent can read from"
}
```

Example in `modules/agent_ec2/iam.tf`:

```hcl
resource "aws_iam_role_policy" "s3_access" {
  count = var.enable_s3_access ? 1 : 0
  
  role = aws_iam_role.agent.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ]
      Resource = concat(
        var.allowed_s3_buckets,
        [for b in var.allowed_s3_buckets : "${b}/*"]
      )
    }]
  })
}
```

## Accessing Agents

### SSM Session Manager

```bash
# List instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=openclaw-agent-*" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Start session
aws ssm start-session --target i-1234567890abcdef0

# Once connected:
sudo docker ps
sudo docker logs openclaw-agent
sudo journalctl -u openclaw-agent -f
```

### SFTP/SCP File Transfer

See [SFTP_ACCESS.md](SFTP_ACCESS.md) for detailed instructions on secure file transfer using SSM port forwarding.

```bash
# Quick start: Create SFTP tunnel (in one terminal)
make sftp-london

# Then use SFTP in another terminal
sftp -P 2222 agent-one@localhost
```

### CloudWatch Logs

```bash
# Tail logs
aws logs tail /openclaw/agent/research-agent --follow

# Query logs
aws logs filter-log-events \
  --log-group-name /openclaw/agent/research-agent \
  --filter-pattern "ERROR"
```

## Monitoring

Each agent exports:
- CloudWatch Logs: `/openclaw/agent/<agent-name>`
- EC2 Metrics: CPU, Network, Disk
- Optional: Detailed monitoring (1-min intervals)

Set up alarms:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name openclaw-research-agent-cpu \
  --alarm-description "High CPU on research agent" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=i-1234567890abcdef0
```

## Updating Agents

To update OpenClaw version:

1. Update `openclaw_version` in `terraform.tfvars`
2. Apply: `terraform apply`
3. Instances will be replaced (blue/green)

To update in-place (risky):

```bash
aws ssm start-session --target <instance-id>
sudo systemctl stop openclaw-agent
sudo docker pull ghcr.io/openclaw/openclaw:v1.3.0
sudo systemctl start openclaw-agent
```

## Cost Optimization

- Use `t3.small` or `t3.medium` for most workloads
- Enable break-glass mode to eliminate NAT Gateway costs ($0.045/hr)
- Use VPC endpoints instead (flat $0.01/GB)
- Set CloudWatch log retention to 7-30 days
- Stop agents when not in use (manual)

## Compliance & Auditing

- All instances tagged with `Environment`, `ManagedBy`, `Agent`
- CloudTrail logs all IAM/API activity
- VPC Flow Logs (optional, add to network module)
- CloudWatch Logs encrypted with KMS
- No SSH keys, no bastion hosts

## Troubleshooting

### Agent won't start

```bash
aws ssm start-session --target <instance-id>
sudo journalctl -u openclaw-agent -n 100
sudo cat /var/log/cloud-init-output.log
```

### Bedrock access denied

- Verify model ID is correct
- Check Bedrock console → Model access
- Verify IAM role has `bedrock:InvokeModel` for specific model ARN
- Check region (Bedrock not available in all regions)

### SSM connection fails

- Verify instance has SSM agent running: `systemctl status amazon-ssm-agent`
- Check instance role has `AmazonSSMManagedInstanceCore`
- Verify VPC endpoints are accessible
- Check security group allows HTTPS outbound

### No internet access

- If `break_glass_mode = true`, internet is disabled by design
- Otherwise, check NAT Gateway is running
- Verify route table has route to NAT
- Check security group allows HTTPS egress

## Future Enhancements

- [ ] Auto-scaling group for agent pools
- [ ] Shared internal ALB for agent API endpoints
- [ ] Egress proxy with domain allowlist
- [ ] VPC Flow Logs to S3
- [ ] GuardDuty integration
- [ ] Patch management with SSM Patch Manager
- [ ] Secrets rotation with Secrets Manager
- [ ] Multi-region deployment

## License

Internal use only - ServeFirst
