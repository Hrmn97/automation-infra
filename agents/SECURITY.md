# Security Architecture

## Overview

This document describes the security architecture and guardrails implemented for the OpenClaw Agent infrastructure.

## Defense in Depth

### Layer 1: Network Isolation

**VPC Architecture**
- Dedicated VPC with RFC1918 private addressing (10.100.0.0/16)
- Agent instances in private subnets only (NO public IPs)
- Public subnets used ONLY for NAT Gateways
- Multi-AZ deployment for resilience

**Egress Control**
- Default: NAT Gateway for outbound HTTPS only
- Break-glass mode: NO internet access (air-gapped)
- VPC Endpoints for AWS services (bypass NAT)
- Security groups: zero inbound, HTTPS outbound only

**VPC Endpoints (Interface)**
- SSM, EC2Messages, SSMMessages (Session Manager access)
- CloudWatch Logs (log shipping)
- Secrets Manager (secrets retrieval)
- Bedrock Runtime (LLM API calls)
- S3 Gateway Endpoint (cheaper than interface)

### Layer 2: IAM Permissions (Least Privilege)

**Per-Agent IAM Role**
- Separate role per agent instance
- NO shared roles or credentials
- NO API keys stored (Bedrock via IAM)
- Short-lived credentials via IMDSv2

**Scoped Permissions**
```
CloudWatch Logs:
  ✓ PutLogEvents to /openclaw/agent/{agent-name} ONLY
  ✗ NO read access to other agents' logs
  ✗ NO CreateLogGroup (pre-created by Terraform)

Secrets:
  ✓ GetSecretValue for /openclaw/agents/{agent-name}/* ONLY
  ✗ NO access to other agents' secrets
  ✗ NO ListSecrets (prevent enumeration)

Bedrock:
  ✓ InvokeModel for SPECIFIC model ARN ONLY
  ✓ ONLY in allowed regions (eu-west-2, us-east-1, us-west-2)
  ✗ NO access to other models
  ✗ NO bedrock:CreateModel, UpdateModel, DeleteModel
```

**Condition Keys**
```hcl
Condition = {
  StringEquals = {
    "aws:RequestedRegion" = ["eu-west-2", "us-east-1"]
  }
}
```

### Layer 3: Instance Hardening

**IMDSv2 Enforcement**
- Prevents SSRF attacks (e.g., compromised agent accessing instance metadata)
- Requires session token before metadata access
- Configured via `http_tokens = "required"`

**Encrypted Storage**
- gp3 volumes with EBS encryption
- KMS encryption for CloudWatch Logs (optional but recommended)
- No unencrypted data at rest

**Latest AMI**
- Amazon Linux 2023 (AL2023)
- Automatic security updates via dnf-automatic
- Minimal attack surface (no unnecessary packages)

**No SSH Access**
- SSM Session Manager ONLY
- No SSH keys, no port 22
- All access logged to CloudWatch

### Layer 4: Container Security

**Docker Configuration**
- Rootless mode (planned)
- Read-only filesystem where possible
- No new privileges (`no-new-privileges:true`)
- Resource limits (CPU, memory)

**OpenClaw Configuration**
- Sandbox mode enabled
- Network isolation within container
- Third-party marketplace DISABLED by default
- Secrets via AWS Parameter Store (not environment variables)

### Layer 5: Monitoring & Auditing

**CloudWatch Logs**
- Separate log group per agent
- 30-day retention (configurable)
- KMS encryption
- Logs: agent runtime, cloud-init, systemd

**CloudTrail**
- All IAM/API calls logged
- Immutable audit trail
- Monitors for:
  - Unauthorized API calls (Bedrock models not in allowlist)
  - Secrets access outside namespace
  - SSM Session Manager connections

**VPC Flow Logs** (optional)
- All network traffic logged
- Detect unexpected egress (e.g., DNS tunneling)
- Identify compromised instances

## Threat Model

### Threats Mitigated

| Threat | Mitigation |
|--------|-----------|
| **Agent compromise** | Network isolation, IAM scoping, no lateral movement |
| **Credential theft** | No API keys, IMDSv2, short-lived STS credentials |
| **SSRF attacks** | IMDSv2 required, no public IPs |
| **Data exfiltration** | Egress restricted to HTTPS, VPC Flow Logs |
| **Unauthorized model access** | Bedrock IAM policy scoped to specific model ARNs |
| **Secrets leakage** | Parameter Store scoped to agent namespace, KMS encryption |
| **Lateral movement** | Separate security groups, no agent-to-agent communication |
| **Supply chain attacks** | Pinned OpenClaw version, verified container images |

### Residual Risks

| Risk | Likelihood | Impact | Mitigation Plan |
|------|-----------|--------|-----------------|
| **OpenClaw 0-day** | Medium | High | Security updates, runtime sandboxing, consider Falco |
| **Bedrock API abuse** | Low | Medium | CloudWatch alarms on API usage, cost alerts |
| **Misconfiguration** | Medium | Medium | Terraform validation, PR reviews, automated testing |
| **Insider threat** | Low | High | CloudTrail, SSM session logging, MFA enforcement |

## Compliance

### SOC 2 / ISO 27001

- ✅ Encryption at rest (EBS, CloudWatch Logs)
- ✅ Encryption in transit (TLS 1.2+)
- ✅ Least privilege access (IAM)
- ✅ Audit logging (CloudTrail, CloudWatch)
- ✅ Network segmentation (VPC, security groups)
- ✅ No shared credentials
- ✅ Automated security updates

### GDPR / Data Residency

- Configure `allowed_bedrock_regions` to EU-only:
  ```hcl
  allowed_bedrock_regions = ["eu-west-2", "eu-west-1"]
  ```
- Enable VPC Flow Logs to S3 in EU region
- Set CloudWatch Logs retention to 30 days max

## Security Checklists

### Pre-Deployment

- [ ] Review `terraform.tfvars` - no hardcoded secrets
- [ ] Verify `break_glass_mode = false` if internet needed
- [ ] Verify `enable_marketplace = false` for all agents
- [ ] Verify Bedrock model IDs are approved
- [ ] Enable KMS encryption for CloudWatch Logs
- [ ] Configure S3 backend for Terraform state (encrypted)
- [ ] Review IAM policies - least privilege?
- [ ] Test SSM Session Manager access

### Post-Deployment

- [ ] Verify no public IPs assigned
- [ ] Verify NAT Gateway IPs are allowlisted (if needed)
- [ ] Test agent connectivity to Bedrock
- [ ] Verify CloudWatch Logs streaming
- [ ] Review VPC Flow Logs for unexpected traffic
- [ ] Set up CloudWatch alarms:
  - High CPU (>80% for 5 min)
  - High Bedrock API errors
  - Unusual egress traffic
- [ ] Document SSM access procedures
- [ ] Schedule security updates (monthly AMI refresh)

### Incident Response

If an agent is compromised:

1. **Isolate**
   ```bash
   # Remove all egress
   aws ec2 revoke-security-group-egress \
     --group-id <sg-id> \
     --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}]'
   ```

2. **Investigate**
   ```bash
   # Review CloudWatch Logs
   aws logs filter-log-events \
     --log-group-name /openclaw/agent/<agent-name> \
     --start-time <timestamp>
   
   # Review CloudTrail
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=ResourceName,AttributeValue=<instance-id>
   
   # Capture VPC Flow Logs
   aws logs get-log-events \
     --log-group-name /aws/vpc/flowlogs/...
   ```

3. **Terminate**
   ```bash
   # Terminate instance
   terraform destroy -target=module.agents[\"<agent-name>\"]
   
   # Rotate secrets
   aws secretsmanager rotate-secret --secret-id /openclaw/agents/<agent-name>/...
   ```

4. **Rebuild**
   ```bash
   # Deploy fresh instance
   terraform apply -target=module.agents[\"<agent-name>\"]
   ```

## Security Hardening Roadmap

- [ ] **Runtime Security**: Integrate Falco or AWS GuardDuty for runtime threat detection
- [ ] **Egress Proxy**: Deploy Squid proxy with domain allowlist
- [ ] **WAF**: Add AWS WAF if exposing agents via ALB
- [ ] **Secrets Rotation**: Automate rotation of Parameter Store secrets
- [ ] **Image Scanning**: Add ECR vulnerability scanning for OpenClaw images
- [ ] **Patch Management**: Integrate AWS Systems Manager Patch Manager
- [ ] **Config Rules**: Add AWS Config rules for compliance checks
- [ ] **Security Hub**: Enable AWS Security Hub for centralized findings
- [ ] **MFA**: Enforce MFA for SSM Session Manager access

## Contact

For security issues, contact: [security@servefirst.co.uk](mailto:security@servefirst.co.uk)
