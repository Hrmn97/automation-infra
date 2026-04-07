# OpenClaw Agents Infrastructure - Documentation Index

Complete production-grade Terraform infrastructure for running isolated OpenClaw agent runtimes on AWS EC2 with Bedrock integration.

## 📚 Documentation

Start here based on your role and goal:

### For First-Time Users
1. **[QUICKSTART.md](QUICKSTART.md)** - Get running in 15 minutes
2. **[README.md](README.md)** - Complete user guide
3. **[DEPLOYMENT.md](DEPLOYMENT.md)** - Step-by-step deployment guide

### For Security Teams
1. **[SECURITY.md](SECURITY.md)** - Security architecture and threat model
2. **[AGENTS.md](AGENTS.md)** - Architecture overview
3. Review IAM policies in `modules/agent_ec2/iam.tf`

### For Platform Engineers
1. **[AGENTS.md](AGENTS.md)** - Architecture and integration patterns
2. **[DEPLOYMENT.md](DEPLOYMENT.md)** - Operational procedures
3. **[Makefile](Makefile)** - Common operations

### For Developers
1. **[README.md](README.md)** - Configuration reference
2. **[examples/basic/](examples/basic/)** - Example deployments
3. Module documentation:
   - `modules/network/` - VPC foundation
   - `modules/agent_ec2/` - Agent instances

## 📁 Repository Structure

```
agents/
├── 📄 INDEX.md                  # This file
├── 📄 README.md                 # Complete user guide
├── 📄 QUICKSTART.md             # 15-minute quick start
├── 📄 DEPLOYMENT.md             # Detailed deployment guide
├── 📄 SECURITY.md               # Security architecture
├── 📄 AGENTS.md                 # Architecture overview
├── 📄 Makefile                  # Common operations
├── 📄 .gitignore                # Git ignore rules
│
├── 🔧 Terraform Root Module
│   ├── versions.tf              # Terraform & provider versions
│   ├── variables.tf             # Input variables
│   ├── main.tf                  # Root orchestration
│   └── outputs.tf               # Outputs (instance IDs, SSM commands, etc.)
│
├── 📦 modules/
│   ├── network/                 # VPC, subnets, NAT, VPC endpoints
│   │   ├── main.tf              # VPC, subnets, route tables, KMS
│   │   ├── vpc_endpoints.tf     # VPC endpoints for AWS services
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   └── agent_ec2/               # Reusable agent instance module
│       ├── main.tf              # EC2 instance, security group, CloudWatch
│       ├── iam.tf               # IAM role, policies (Bedrock, logs, secrets)
│       ├── user_data.sh         # Bootstrap: Docker, OpenClaw, systemd
│       ├── variables.tf
│       └── outputs.tf
│
├── 🔨 scripts/
│   ├── validate-config.sh       # Pre-deployment validation
│   └── connect-agent.sh         # Helper to connect via SSM
│
└── 📚 examples/
    └── basic/                   # Basic deployment example
        ├── main.tf
        ├── variables.tf
        └── terraform.tfvars.example
```

## 🚀 Quick Reference

### Deploy
```bash
cd terraform/agents
cp examples/basic/terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Configure agents
terraform init
terraform apply
```

### Connect
```bash
./scripts/connect-agent.sh
# Or: aws ssm start-session --target <instance-id>
```

### Monitor
```bash
# Logs
aws logs tail /openclaw/agent/research-agent --follow

# Metrics
terraform output agent_instances
```

### Update
```bash
# Edit terraform.tfvars (change openclaw_version or add agents)
terraform plan
terraform apply
```

### Destroy
```bash
terraform destroy
```

## 📖 Key Concepts

### Network Architecture
- **VPC**: Dedicated 10.100.0.0/16 (customizable)
- **Subnets**: 2 AZs, public (NAT only) + private (agents)
- **Egress**: NAT Gateway or break-glass (air-gapped)
- **VPC Endpoints**: SSM, Bedrock, CloudWatch, Secrets Manager, S3

### Security Model
- **Zero Inbound**: No SSH, no public IPs
- **Least Privilege IAM**: Per-agent roles, scoped to specific Bedrock models
- **Isolation**: Separate SG, IAM, logs, secrets per agent
- **Encryption**: IMDSv2, EBS encrypted, KMS for logs

### Agent Lifecycle
1. **Bootstrap**: cloud-init installs Docker, pulls OpenClaw image
2. **Configuration**: Auto-generated config with Bedrock provider
3. **Runtime**: systemd service with auto-restart
4. **Logging**: CloudWatch Logs + local journald
5. **Access**: SSM Session Manager only

## 🔐 Security Checklist

Before deploying to production:

- [ ] Review [SECURITY.md](SECURITY.md)
- [ ] Verify `enable_marketplace = false` for all agents
- [ ] Verify Bedrock model IDs are approved
- [ ] Enable KMS encryption for CloudWatch Logs
- [ ] Set up CloudWatch alarms (CPU, API errors, egress)
- [ ] Configure S3 backend for Terraform state
- [ ] Review IAM policies (least privilege)
- [ ] Test SSM Session Manager access
- [ ] Enable VPC Flow Logs (optional but recommended)
- [ ] Document incident response procedures

## 💰 Cost Management

| Component | Monthly Cost (EU-West-2) | Optimization |
|-----------|--------------------------|--------------|
| NAT Gateway | ~$35 | Use break-glass mode |
| VPC Endpoints (8) | ~$60 | Reduce count, use NAT for some |
| EC2 t3.medium | ~$35 | Use t3.small or stop when idle |
| EBS gp3 30GB | ~$3 | Minimal, already optimized |
| CloudWatch Logs | ~$5 | Reduce retention to 7 days |
| **Total** | **~$138** | Can reduce to ~$60-80 |

## 🛠️ Common Operations

### Using Makefile
```bash
make help           # Show all commands
make plan           # Plan deployment
make apply          # Apply changes
make connect        # Connect to first agent
make logs           # Tail logs
make list-agents    # List all agents
make security-check # Run security checks
```

### Using Scripts
```bash
./scripts/validate-config.sh  # Pre-deployment validation
./scripts/connect-agent.sh     # Interactive SSM connection
```

### Manual Operations
```bash
# List all resources
terraform state list

# Show specific resource
terraform state show module.agents[\"research-agent\"].aws_instance.agent

# Get outputs
terraform output -json agent_instances | jq

# Format code
terraform fmt -recursive

# Validate configuration
terraform validate
```

## 📞 Support

### Troubleshooting
1. Check [QUICKSTART.md#Troubleshooting](QUICKSTART.md#troubleshooting)
2. Review CloudWatch Logs: `aws logs tail /openclaw/agent/<name> --follow`
3. Connect to instance: `./scripts/connect-agent.sh`
4. Check cloud-init logs: `/var/log/cloud-init-output.log`

### Common Issues

| Issue | Solution |
|-------|----------|
| Can't connect via SSM | Check VPC endpoints, security groups, instance state |
| Bedrock access denied | Verify model access in Bedrock console, check IAM policy |
| Agent won't start | Check cloud-init logs, Docker status, systemd service |
| High costs | Stop instances when idle, use break-glass mode, reduce endpoints |
| Terraform errors | Run `terraform validate`, check AWS credentials, review logs |

### Getting Help
- **Terraform Issues**: `TF_LOG=DEBUG terraform apply`
- **AWS Issues**: Check CloudTrail, VPC Flow Logs
- **Agent Issues**: Check CloudWatch Logs, connect via SSM
- **Security Issues**: See [SECURITY.md](SECURITY.md)

## 🗺️ Roadmap

- [ ] Auto Scaling Groups for agent pools
- [ ] Internal ALB for agent APIs
- [ ] Egress proxy with domain allowlist
- [ ] AMI baking pipeline (Packer)
- [ ] Runtime threat detection (Falco/GuardDuty)
- [ ] Secrets rotation automation
- [ ] Multi-region deployment
- [ ] Cost anomaly detection
- [ ] Patch management (SSM Patch Manager)

## 📜 License

Internal use - ServeFirst

---

**Need help?** Start with [QUICKSTART.md](QUICKSTART.md) for a guided walkthrough.
