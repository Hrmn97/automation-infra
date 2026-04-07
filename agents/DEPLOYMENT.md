# OpenClaw Deployment Guide

## Overview

This guide explains the simplified two-phase deployment approach for OpenClaw agents in a secure, sandboxed AWS environment.

## Architecture

### Security Model

- **No Public IPs**: Instances run in private subnets only
- **SSM Access Only**: Connect via AWS Systems Manager Session Manager (no SSH keys)
- **IAM-Based Auth**: Bedrock access via instance profile (no API keys)
- **Network Isolation**: VPC endpoints for AWS services, optional NAT gateway for package downloads
- **Least Privilege**: Scoped IAM policies per agent

### Two-Phase Deployment

**Phase 1: Infrastructure Setup (Terraform)**
- Creates VPC, subnets, VPC endpoints
- Launches EC2 instance with minimal user data
- Configures IAM roles with Bedrock permissions
- Sets up CloudWatch logging

**Phase 2: Application Deployment (Manual/SSM)**
- Install OpenClaw via deployment script
- Configure agent settings
- Start OpenClaw service

## Why This Approach?

### Previous Issues

The original user data script tried to do everything at boot:
- Install Docker, CloudWatch agent, Docker Compose
- Pull OpenClaw container
- Generate complex configuration files
- Start OpenClaw service

**Problems:**
- Hard to debug failures
- Slow instance startup
- No separation of concerns
- Difficult to update OpenClaw without recreating instances

### New Simplified Approach

**User Data (runs once at boot):**
```bash
- Update system packages
- Install Docker + CloudWatch agent
- Configure basic logging
- Enable automatic security updates
- Create directories
```

**Deployment Script (run when ready):**
```bash
- Pull OpenClaw container
- Generate configuration
- Start OpenClaw service
```

**Benefits:**
- Fast, predictable infrastructure creation
- Easy to debug issues
- Can redeploy OpenClaw without recreating EC2
- Clear separation: infrastructure vs application

## AMI Choice: Amazon Linux 2023

**Why AL2023?**
- ✅ Official AWS AMI (trusted, maintained)
- ✅ Excellent AWS service integration (SSM, CloudWatch, etc.)
- ✅ Optimized for EC2
- ✅ 5 years of support (until 2028)
- ✅ Modern package manager (dnf)
- ✅ SELinux enabled by default
- ✅ Minimal attack surface

**Ubuntu Alternative?**
You could use Ubuntu, but:
- AL2023 has better AWS integration out of the box
- AL2023 is specifically optimized for AWS workloads
- Package management is different (apt vs dnf)
- For sandboxed AWS environment, AL2023 is recommended

**To switch to Ubuntu:**
```hcl
# In modules/agent_ec2/main.tf, change the AMI data source:
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Then update:
ami = data.aws_ami.ubuntu.id
```

## Bedrock Permissions

Bedrock permissions are configured in `modules/agent_ec2/iam.tf`:

```hcl
resource "aws_iam_role_policy" "bedrock" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ]
      Resource = [local.bedrock_model_arn]
      Condition = {
        StringEquals = {
          "aws:RequestedRegion" = var.allowed_bedrock_regions
        }
      }
    }]
  })
}
```

**Key Security Features:**
1. **Scoped to specific model**: Only the configured model ARN is allowed
2. **Region restrictions**: Only configured regions (default: eu-west-2, us-east-1, us-west-2)
3. **No credentials stored**: Uses instance profile (IAM role)
4. **Least privilege**: Only InvokeModel permissions, no admin access

**To add more Bedrock permissions:**

```hcl
# In london.tfvars, add to allowed_bedrock_regions:
allowed_bedrock_regions = ["eu-west-2", "us-east-1", "us-west-2", "eu-central-1"]

# For cross-region inference, ensure VPC endpoints exist in those regions
# or enable NAT gateway for internet access
```

## Deployment Steps

### 1. Initial Setup

```bash
cd agents/

# Create workspace for your environment
terraform workspace new london

# Initialize Terraform
make init
```

### 2. Configure Variables

Edit `london.tfvars`:

```hcl
aws_region  = "eu-west-2"
environment = "london"

# Agent configuration
agents = {
  agent-one = {
    instance_type    = "m7i-flex.large"
    bedrock_model_id = "anthropic.claude-3-7-sonnet-20250219-v1:0"
  }
}

# Bedrock permissions
allowed_bedrock_regions = ["eu-west-2", "us-east-1"]
```

### 3. Deploy Infrastructure

```bash
# Plan
make plan-london

# Apply
make apply-london
```

This creates:
- VPC with private subnets
- EC2 instance with Docker installed
- IAM role with Bedrock permissions
- CloudWatch log groups
- VPC endpoints for AWS services

### 4. Deploy OpenClaw

**Option A: Manual Deployment (Recommended for First Time)**

```bash
# Connect to instance
make connect-london

# Once connected, run deployment script
cd /opt
sudo wget https://raw.githubusercontent.com/your-org/repo/main/scripts/deploy-openclaw.sh
sudo chmod +x deploy-openclaw.sh
sudo ./deploy-openclaw.sh agent-one 2026.2.3 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0
```

Or copy the local script:

```bash
# On your local machine
make connect-london

# In the SSM session
cd /opt/openclaw

# Copy/paste the contents of scripts/deploy-openclaw.sh
# Then run it
bash deploy-openclaw.sh agent-one 2026.2.3 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0
```

**Option B: Automated via SSM Run Command**

```bash
make deploy-openclaw-london
```

### 5. Verify Deployment

```bash
# Connect to instance
make connect-london

# Check service status
sudo systemctl status openclaw-agent

# Check Docker container
docker ps

# View logs
journalctl -u openclaw-agent -f

# Or view from CloudWatch
make logs-london
```

## Updating OpenClaw

To update OpenClaw version without recreating infrastructure:

```bash
# Connect to instance
make connect-london

# Run deployment script with new version
cd /opt/openclaw
sudo ./deploy-openclaw.sh agent-one 2026.3.0 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0

# Or manually
docker-compose down
docker pull ghcr.io/openclaw/openclaw:2026.3.0
# Update docker-compose.yml with new version
docker-compose up -d
```

## Security Considerations

### Network Isolation

**Current Setup:**
- Private subnets only (no public IPs)
- NAT gateway for outbound internet (Docker pulls, package updates)
- VPC endpoints for AWS services (SSM, CloudWatch, Bedrock)

**Enhanced Isolation ("Break-Glass Mode"):**

In `london.tfvars`:
```hcl
enable_nat_gateway = false
break_glass_mode   = true
```

This requires:
- Pre-baked AMI with Docker and OpenClaw pre-installed
- All VPC endpoints configured
- No internet access whatsoever

### IAM Permissions

Review and customize IAM permissions in `modules/agent_ec2/iam.tf`:

**Current permissions:**
- ✅ SSM Session Manager (for access)
- ✅ CloudWatch Logs (write only to agent's log group)
- ✅ SSM Parameter Store (read only from `/openclaw/agents/{agent-name}/*`)
- ✅ Secrets Manager (read only from `/openclaw/agents/{agent-name}/*`)
- ✅ Bedrock InvokeModel (specific model + regions only)

**To add S3 access (read-only):**

Uncomment and configure in `modules/agent_ec2/iam.tf`:

```hcl
variable "enable_s3_access" {
  type    = bool
  default = true
}

variable "allowed_s3_buckets" {
  type    = list(string)
  default = ["arn:aws:s3:::my-data-bucket"]
}

resource "aws_iam_role_policy" "s3_access" {
  # ... (already in file as example)
}
```

### Secrets Management

Store sensitive configuration in SSM Parameter Store:

```bash
# Store API tokens, credentials, etc.
aws ssm put-parameter \
  --name "/openclaw/agents/agent-one/github-token" \
  --value "ghp_xxxxxxxxxxxx" \
  --type "SecureString" \
  --region eu-west-2

# OpenClaw can read via IAM role (no credentials needed)
```

## Monitoring

### CloudWatch Logs

```bash
# View logs from terminal
make logs-london

# Or manually
aws logs tail /openclaw/agent/agent-one --follow --region eu-west-2
```

### Metrics

CloudWatch metrics are automatically published:
- Namespace: `OpenClaw/Agents`
- Dimensions: `Agent`, `Environment`

### Alarms (Optional)

Add to your Terraform:

```hcl
resource "aws_cloudwatch_metric_alarm" "agent_unhealthy" {
  alarm_name          = "openclaw-agent-one-unhealthy"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "OpenClaw/Agents"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  
  dimensions = {
    Agent = "agent-one"
  }
}
```

## Troubleshooting

### Instance won't start

```bash
# Check user data logs
make connect-london
sudo cat /var/log/user-data.log
sudo cat /var/log/cloud-init-output.log
```

### OpenClaw won't start

```bash
make connect-london

# Check Docker
sudo systemctl status docker
docker ps -a

# Check OpenClaw service
sudo systemctl status openclaw-agent
journalctl -u openclaw-agent -n 100

# Check container logs
docker logs openclaw-agent-agent-one
```

### Bedrock permission denied

```bash
# Verify IAM role is attached
aws sts get-caller-identity

# Check if model is available in region
aws bedrock list-foundation-models --region eu-west-2

# Verify model ARN in IAM policy
terraform output agent_instances
```

### Can't connect via SSM

```bash
# Verify SSM agent is running
make connect-london
sudo systemctl status amazon-ssm-agent

# Check instance has correct IAM role
aws ec2 describe-instances --instance-ids i-xxxxx --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Verify your IAM user has SSM permissions
aws iam get-user
```

## Cost Optimization

### Instance Right-Sizing

```hcl
# Start small
instance_type = "t3.medium"  # $0.0416/hr = ~$30/month

# Scale up as needed
instance_type = "m7i-flex.large"  # $0.1138/hr = ~$83/month
instance_type = "m7i-flex.xlarge" # $0.2275/hr = ~$166/month
```

### NAT Gateway

```hcl
# Development: Single NAT (not HA)
enable_nat_gateway_per_az = false  # ~$32/month

# Production: NAT per AZ (HA)
enable_nat_gateway_per_az = true   # ~$64/month
```

### VPC Endpoints

VPC endpoints cost ~$7/month per endpoint, but eliminate NAT charges for AWS service traffic.

Current setup uses:
- SSM (required for access)
- SSM Messages (required for Session Manager)
- EC2 Messages (required for Session Manager)
- Bedrock Runtime (optional, saves NAT cost)
- CloudWatch Logs (optional, saves NAT cost)

## Next Steps

1. **Test Bedrock Access**: Connect and verify OpenClaw can call Bedrock
2. **Configure Secrets**: Store any API keys in SSM Parameter Store
3. **Set Up Monitoring**: Configure CloudWatch alarms
4. **Create AMI**: Once working, create custom AMI to skip user data entirely
5. **Add Agents**: Define more agents in `london.tfvars` as needed

## References

- [OpenClaw Documentation](https://github.com/openclaw/openclaw)
- [Bedrock Model IDs](https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids.html)
- [Amazon Linux 2023](https://aws.amazon.com/linux/amazon-linux-2023/)
- [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
