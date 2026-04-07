# OpenClaw Quick Reference

## Common Commands

### Infrastructure

```bash
# Initialize
make init

# Plan changes
make plan-london

# Apply changes
make apply-london

# Destroy everything
make destroy-london
```

### Access

```bash
# Connect to agent via SSM
make connect-london

# View logs
make logs-london

# List all agents
make list-agents
```

### Deploy OpenClaw

```bash
# Automated deployment
make deploy-openclaw-london

# Manual deployment (recommended first time)
make connect-london
# Then in the instance:
cd /opt/openclaw
curl -O https://path-to/deploy-openclaw.sh
chmod +x deploy-openclaw.sh
./deploy-openclaw.sh agent-one 2026.2.3 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0
```

### On the Instance

```bash
# Check OpenClaw status
sudo systemctl status openclaw-agent

# View logs
journalctl -u openclaw-agent -f

# Docker logs
docker logs -f openclaw-agent-agent-one

# Restart service
sudo systemctl restart openclaw-agent

# Check Docker
docker ps
docker stats

# Test health endpoint
curl http://localhost:8080/health
```

## File Locations

```
/opt/openclaw/
├── config/
│   └── agent.yaml          # OpenClaw configuration
├── data/                   # Persistent data
├── logs/                   # Application logs
└── docker-compose.yml      # Container definition

/var/log/
├── user-data.log          # User data script output
├── cloud-init-output.log  # Cloud-init logs
└── openclaw-agent.log     # OpenClaw application logs

/etc/systemd/system/
└── openclaw-agent.service # Systemd service definition
```

## Troubleshooting

### Instance won't start
```bash
# View user data logs
make connect-london
cat /var/log/user-data.log
cat /var/log/cloud-init-output.log
```

### OpenClaw won't start
```bash
# Check service
sudo systemctl status openclaw-agent
journalctl -u openclaw-agent -n 50

# Check Docker
docker ps -a
docker logs openclaw-agent-agent-one

# Check config
cat /opt/openclaw/config/agent.yaml
```

### Bedrock errors
```bash
# Test IAM role
aws sts get-caller-identity

# List available models
aws bedrock list-foundation-models --region eu-west-2

# Check OpenClaw logs for Bedrock errors
journalctl -u openclaw-agent | grep -i bedrock
```

## Configuration

### Update OpenClaw Version

```bash
make connect-london
cd /opt/openclaw
./deploy-openclaw.sh agent-one 2026.3.0 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0
```

### Change Bedrock Model

```bash
# Edit configuration
sudo nano /opt/openclaw/config/agent.yaml

# Update model_id:
llm:
  bedrock:
    model_id: anthropic.claude-3-haiku-20240307-v1:0

# Restart service
sudo systemctl restart openclaw-agent
```

### Add Secrets

```bash
# From local machine
aws ssm put-parameter \
  --name "/openclaw/agents/agent-one/my-secret" \
  --value "secret-value" \
  --type "SecureString" \
  --region eu-west-2

# OpenClaw can access via config:
security:
  secrets:
    provider: aws-ssm
    ssm:
      prefix: /openclaw/agents/agent-one
```

## Security Checklist

- [ ] No public IPs (instances in private subnets)
- [ ] SSM access only (no SSH keys)
- [ ] IAM instance profile configured
- [ ] Bedrock permissions scoped to specific model
- [ ] CloudWatch logging enabled
- [ ] Automatic security updates enabled
- [ ] VPC endpoints configured
- [ ] Security group blocks inbound traffic
- [ ] Secrets in SSM Parameter Store (not hardcoded)

## Monitoring

### CloudWatch Logs
```bash
# From local machine
aws logs tail /openclaw/agent/agent-one --follow --region eu-west-2

# Or use make target
make logs-london
```

### Metrics
Navigate to CloudWatch Console:
- Namespace: `OpenClaw/Agents`
- Dimensions: `Agent=agent-one`, `Environment=london`

### Alarms (setup)
```hcl
# Add to Terraform
resource "aws_cloudwatch_metric_alarm" "agent_unhealthy" {
  alarm_name  = "openclaw-agent-one-unhealthy"
  metric_name = "HealthCheckStatus"
  namespace   = "OpenClaw/Agents"
  # ... (see DEPLOYMENT.md)
}
```

## Cost Tracking

```bash
# Instance cost
# t3.medium: ~$30/month
# m7i-flex.large: ~$83/month

# NAT Gateway: ~$32/month (or $64 for HA)
# VPC Endpoints: ~$7/month each
# CloudWatch Logs: ~$0.50/GB ingested

# Total estimate: $100-150/month per agent
```

## Useful AWS CLI Commands

```bash
# Get instance ID
terraform output -json agent_instances | jq -r '.[keys[0]].instance_id'

# Get instance status
aws ec2 describe-instance-status --instance-ids i-xxxxx --region eu-west-2

# Get CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /openclaw --region eu-west-2

# List SSM parameters
aws ssm get-parameters-by-path --path /openclaw/agents/agent-one --region eu-west-2

# Test Bedrock access (from instance)
aws bedrock invoke-model \
  --model-id anthropic.claude-3-7-sonnet-20250219-v1:0 \
  --body '{"prompt":"Hello","max_tokens":100}' \
  --region eu-west-2 \
  output.json
```

## Development Workflow

1. **Make infrastructure changes**
   ```bash
   # Edit .tf files or .tfvars
   make plan-london
   make apply-london
   ```

2. **Test OpenClaw deployment**
   ```bash
   make connect-london
   # Test deployment script
   ./deploy-openclaw.sh ...
   ```

3. **Verify and monitor**
   ```bash
   # Check logs
   make logs-london
   
   # Test endpoint
   curl http://localhost:8080/health
   ```

4. **Iterate**
   - OpenClaw changes: Just re-run deploy script
   - Infrastructure changes: Terraform apply
   - No need to destroy/recreate for app updates!

## Emergency Procedures

### Agent is unresponsive
```bash
# Restart instance
aws ec2 reboot-instances --instance-ids i-xxxxx --region eu-west-2

# Or from console
# EC2 > Instances > Actions > Instance State > Reboot
```

### Completely start over
```bash
make destroy-london
make apply-london
make deploy-openclaw-london
```

### Rollback to previous OpenClaw version
```bash
make connect-london
cd /opt/openclaw
./deploy-openclaw.sh agent-one 2026.2.2 ghcr.io/openclaw/openclaw anthropic.claude-3-7-sonnet-20250219-v1:0
```
