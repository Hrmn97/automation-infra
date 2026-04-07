# Quick Start Guide

Get your OpenClaw agents running on AWS in under 15 minutes.

## Prerequisites (5 minutes)

1. **AWS Account** with:
   - Bedrock enabled in target region
   - Administrator or PowerUser access
   - Claude model access granted in Bedrock console

2. **Local Tools**:
   ```bash
   # Verify installations
   terraform version  # >= 1.6
   aws --version      # >= 2.0
   jq --version       # For helper scripts
   ```

3. **AWS Credentials**:
   ```bash
   aws configure
   # Or use AWS_PROFILE, AWS_ACCESS_KEY_ID, etc.
   
   # Test access
   aws sts get-caller-identity
   ```

## Deploy (5 minutes)

### Step 1: Configure

```bash
cd terraform/agents

# Copy example configuration
cp examples/basic/terraform.tfvars.example terraform.tfvars

# Edit configuration (minimal example below)
cat > terraform.tfvars <<EOF
aws_region  = "eu-west-2"
environment = "stage"

agents = {
  research-agent = {
    instance_type    = "t3.medium"
    bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
  }
}
EOF
```

### Step 2: Validate

```bash
# Run validation script
./scripts/validate-config.sh

# Or manually
terraform init
terraform validate
terraform plan
```

### Step 3: Deploy

```bash
# Apply infrastructure
terraform apply

# Review the plan, then type 'yes' to confirm
# Takes ~3-5 minutes to create all resources
```

### Step 4: Verify

```bash
# Show outputs
terraform output

# Connect to agent
./scripts/connect-agent.sh

# Or manually
INSTANCE_ID=$(terraform output -json agent_instances | jq -r '.["research-agent"].instance_id')
aws ssm start-session --target $INSTANCE_ID
```

## Using Your Agent (3 minutes)

### Check Status

Once connected via SSM:

```bash
# Check Docker
sudo docker ps

# Check OpenClaw service
sudo systemctl status openclaw-agent

# Check logs
sudo journalctl -u openclaw-agent -f
```

### View Logs Remotely

```bash
# From your local machine
aws logs tail /openclaw/agent/research-agent --follow
```

### Test Agent

```bash
# Inside the instance
curl http://localhost:8080/health

# Check Docker logs
sudo docker logs -f openclaw-agent-research-agent
```

## Common Tasks

### Add Another Agent

```bash
# Edit terraform.tfvars
cat >> terraform.tfvars <<EOF

  qa-agent = {
    instance_type    = "t3.small"
    bedrock_model_id = "anthropic.claude-3-haiku-20240307-v1:0"
  }
EOF

# Apply changes
terraform apply
```

### Update OpenClaw Version

```hcl
# In terraform.tfvars
agents = {
  research-agent = {
    openclaw_version = "v1.3.0"  # Update this
    # ...
  }
}
```

```bash
terraform apply
# Instance will be replaced (zero downtime for single agent)
```

### View All Agents

```bash
# List agents
make list-agents

# Or manually
terraform output -json agent_instances | jq -r 'to_entries[] | "\(.key): \(.value.instance_id)"'
```

## Troubleshooting

### Agent Won't Start

```bash
# Connect to instance
./scripts/connect-agent.sh

# Check bootstrap logs
sudo cat /var/log/cloud-init-output.log
sudo cat /var/log/openclaw-bootstrap.log

# Check systemd service
sudo systemctl status openclaw-agent
sudo journalctl -u openclaw-agent -n 50
```

### Bedrock Access Denied

```bash
# Verify model access in Bedrock console
aws bedrock list-foundation-models --region eu-west-2 \
  | jq '.modelSummaries[] | select(.modelId | contains("claude"))'

# Check IAM role permissions
ROLE_NAME=$(terraform output -json agent_instances | jq -r '.["research-agent"].iam_role_name')
aws iam get-role-policy --role-name $ROLE_NAME --policy-name bedrock
```

### Can't Connect via SSM

```bash
# Check instance is running
terraform output -json agent_instances

# Check SSM agent
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID"

# Verify VPC endpoints exist
terraform output vpc_endpoints
```

### High Costs

```bash
# Check what's running
terraform state list

# Estimate costs
make cost-estimate  # Requires infracost

# Stop agents when not in use
aws ec2 stop-instances --instance-ids $INSTANCE_ID

# Or destroy everything
terraform destroy
```

## Next Steps

- **Customize Configuration**: See [README.md](README.md) for all options
- **Security Review**: Read [SECURITY.md](SECURITY.md)
- **Production Deployment**: See [DEPLOYMENT.md](DEPLOYMENT.md)
- **Add Tools**: See examples in `modules/agent_ec2/iam.tf`

## Cost Estimate

**Minimal Setup (1 agent)**:
- NAT Gateway: ~$35/month
- VPC Endpoints: ~$60/month (8 endpoints)
- EC2 t3.medium: ~$35/month
- EBS 30GB: ~$3/month
- CloudWatch Logs: ~$5/month
- **Total: ~$138/month**

**Cost Savings**:
- Use `break_glass_mode = true` to eliminate NAT (-$35/month)
- Use `t3.small` instead of `t3.medium` (-$18/month)
- Reduce VPC endpoints, use NAT for some services (-$20-40/month)
- Stop instances when not in use (pay only for storage)

## Cleanup

```bash
# Destroy all infrastructure
terraform destroy

# Clean local files
make clean
```

## Support

- **Issues**: Check logs in CloudWatch or on instance
- **Questions**: See [README.md](README.md) for detailed docs
- **Security**: See [SECURITY.md](SECURITY.md)
