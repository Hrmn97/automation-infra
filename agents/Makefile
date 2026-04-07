# Makefile for OpenClaw Agents Infrastructure
# Common Terraform operations

.PHONY: help init plan apply destroy fmt validate clean connect logs dashboard-london status-london restart-london

# Variables
TF := terraform
EXAMPLE_DIR := examples/basic

# AWS profile — set AGENTS_PROFILE in your shell (e.g. ~/.zshrc) to override
AWS_PROFILE ?= $(AGENTS_PROFILE)
export AWS_PROFILE

help: ## Show this help message
	@echo "OpenClaw Agents - Terraform Commands"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	$(TF) init

init-upgrade: ## Initialize Terraform with provider upgrade
	$(TF) init -upgrade

plan: ## Run Terraform plan
	$(TF) plan -out=tfplan

apply: ## Apply Terraform changes
	$(TF) apply tfplan

apply-auto: ## Apply Terraform changes without confirmation (DANGEROUS)
	$(TF) apply -auto-approve

destroy: ## Destroy all infrastructure (requires confirmation)
	$(TF) destroy

destroy-auto: ## Destroy all infrastructure without confirmation (VERY DANGEROUS)
	$(TF) destroy -auto-approve

fmt: ## Format Terraform files
	$(TF) fmt -recursive

validate: ## Validate Terraform configuration
	$(TF) validate

lint: fmt validate ## Run formatting and validation
	@echo "Linting complete"

clean: ## Clean Terraform cache and plans
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f tfplan
	rm -f terraform.tfstate.backup

output: ## Show Terraform outputs
	$(TF) output

output-json: ## Show Terraform outputs in JSON
	$(TF) output -json

connect: ## Connect to first agent via SSM (requires jq)
	@INSTANCE_ID=$$($(TF) output -json agent_instances | jq -r '.[keys[0]].instance_id'); \
	REGION=$${AWS_REGION:-$$(aws configure get region 2>/dev/null || echo "eu-west-2")}; \
	echo "Connecting to instance: $$INSTANCE_ID (region: $$REGION)"; \
	aws ssm start-session --target $$INSTANCE_ID --region $$REGION

logs: ## Tail CloudWatch logs for first agent (requires jq)
	@LOG_GROUP=$$($(TF) output -json agent_instances | jq -r '.[keys[0]].log_group_name'); \
	REGION=$${AWS_REGION:-$$(aws configure get region 2>/dev/null || echo "eu-west-2")}; \
	echo "Tailing logs: $$LOG_GROUP (region: $$REGION)"; \
	aws logs tail $$LOG_GROUP --since 1h --follow --region $$REGION

list-agents: ## List all deployed agents
	@$(TF) output -json agent_instances | jq -r 'to_entries[] | "\(.key): \(.value.instance_id) (\(.value.private_ip))"'

security-check: ## Run security validation checks
	@echo "Running security checks..."
	@echo "Checking for public IPs..."
	@$(TF) output -json agent_instances | jq -r '.[] | select(.public_ip != null) | "WARNING: Agent has public IP: \(.instance_id)"'
	@echo "Checking break-glass mode..."
	@$(TF) output -json network_security_summary | jq -r '.break_glass_mode'
	@echo "Security check complete"

cost-estimate: ## Estimate monthly costs (requires terraform-cost-estimation or infracost)
	@echo "Cost estimation requires infracost (https://www.infracost.io/)"
	@echo "Install: brew install infracost"
	@echo "Run: infracost breakdown --path ."

docs: ## Generate Terraform documentation (requires terraform-docs)
	@echo "Generating documentation..."
	@terraform-docs markdown table --output-file TERRAFORM.md .
	@terraform-docs markdown table --output-file modules/network/TERRAFORM.md modules/network/
	@terraform-docs markdown table --output-file modules/agent_ec2/TERRAFORM.md modules/agent_ec2/
	@echo "Documentation generated"

graph: ## Generate Terraform dependency graph (requires graphviz)
	$(TF) graph | dot -Tpng > graph.png
	@echo "Graph saved to graph.png"

# Example targets
example-init: ## Initialize example deployment
	cd $(EXAMPLE_DIR) && $(TF) init

example-plan: ## Plan example deployment
	cd $(EXAMPLE_DIR) && $(TF) plan

example-apply: ## Apply example deployment
	cd $(EXAMPLE_DIR) && $(TF) apply

example-destroy: ## Destroy example deployment
	cd $(EXAMPLE_DIR) && $(TF) destroy

# State management
state-list: ## List resources in state
	$(TF) state list

state-show: ## Show detailed state for a resource (usage: make state-show RESOURCE=aws_instance.example)
	$(TF) state show $(RESOURCE)

state-pull: ## Pull remote state
	$(TF) state pull

state-backup: ## Backup current state
	$(TF) state pull > terraform.tfstate.backup-$$(date +%Y%m%d-%H%M%S)

# Debugging
debug-plan: ## Run plan with debug logging
	TF_LOG=DEBUG $(TF) plan

debug-apply: ## Run apply with debug logging
	TF_LOG=DEBUG $(TF) apply

# Pre-deployment checks
pre-deploy: fmt validate security-check ## Run all pre-deployment checks
	@echo "Pre-deployment checks complete"
	@echo "Ready to deploy!"

# Workspace-specific targets
workspace-list: ## List all workspaces
	@$(TF) workspace list

workspace-show: ## Show current workspace
	@echo "Current workspace: $$($(TF) workspace show)"

# London workspace targets
plan-london: ## Plan London deployment
	@echo "Planning for workspace: london"
	$(TF) workspace select london
	$(TF) plan -var-file="london.tfvars" -out=tfplan

apply-london: ## Apply London deployment
	@echo "Applying for workspace: london"
	$(TF) workspace select london
	$(TF) apply -var-file="london.tfvars"

destroy-london: ## Destroy London deployment
	@echo "Destroying workspace: london"
	$(TF) workspace select london
	$(TF) destroy -var-file="london.tfvars"

connect-london: ## Connect to London agent
	@$(TF) workspace select london
	@echo "Connecting to London agent..."
	@./scripts/connect-agent.sh

sftp-london: ## Setup SFTP tunnel to London agent (port 2222)
	@$(TF) workspace select london
	@./scripts/sftp-tunnel.sh agent-one

dashboard-london: ## Port-forward to OpenClaw dashboard (London)
	@$(TF) workspace select london
	@INSTANCE_ID=$$($(TF) output -json agent_instances | jq -r '."agent-one".instance_id'); \
	PORT=$$($(TF) output -json agent_instances | jq -r '."agent-one".openclaw_config.gateway_port'); \
	echo "========================================"; \
	echo "OpenClaw Dashboard - Port Forwarding"; \
	echo "========================================"; \
	echo ""; \
	echo "Instance:  $$INSTANCE_ID"; \
	echo "Port:      $$PORT"; \
	echo ""; \
	echo "Once connected, open in your browser:"; \
	echo "  http://localhost:$$PORT/"; \
	echo ""; \
	echo "To get the auth token:"; \
	echo "  terraform output -json gateway_auth_tokens"; \
	echo ""; \
	echo "Starting port forward (Ctrl+C to stop)..."; \
	echo ""; \
	aws ssm start-session --target $$INSTANCE_ID \
	  --document-name AWS-StartPortForwardingSession \
	  --parameters "{\"portNumber\":[\"$$PORT\"],\"localPortNumber\":[\"$$PORT\"]}" \
	  --region eu-west-2

status-london: ## Show OpenClaw status on London agent
	@$(TF) workspace select london
	@INSTANCE_ID=$$($(TF) output -json agent_instances | jq -r '."agent-one".instance_id'); \
	AGENT_NAME="agent-one"; \
	echo "Checking OpenClaw status on $$AGENT_NAME ($$INSTANCE_ID)..."; \
	aws ssm send-command \
	  --instance-ids $$INSTANCE_ID \
	  --document-name "AWS-RunShellScript" \
	  --parameters '{"commands":["sudo su - agent-one -c \"openclaw status\"","sudo systemctl status openclaw-gateway.service --no-pager"]}' \
	  --region eu-west-2 \
	  --output text

logs-london: ## Tail London agent logs
	@$(TF) workspace select london
	@LOG_GROUP=$$($(TF) output -json agent_instances | jq -r '.[keys[0]].log_group_name'); \
	echo "Tailing London logs: $$LOG_GROUP"; \
	aws logs tail $$LOG_GROUP --since 1h --follow --region eu-west-2

restart-london: ## Restart OpenClaw service on London agent
	@$(TF) workspace select london
	@INSTANCE_ID=$$($(TF) output -json agent_instances | jq -r '."agent-one".instance_id'); \
	echo "Restarting OpenClaw service on $$INSTANCE_ID..."; \
	COMMAND_ID=$$(aws ssm send-command \
	  --instance-ids $$INSTANCE_ID \
	  --document-name "AWS-RunShellScript" \
	  --parameters '{"commands":["sudo systemctl restart openclaw-gateway.service","sleep 2","sudo systemctl status openclaw-gateway.service --no-pager"]}' \
	  --region eu-west-2 \
	  --output text \
	  --query 'Command.CommandId'); \
	echo "Command ID: $$COMMAND_ID"; \
	echo "Waiting for command to complete..."; \
	sleep 5; \
	aws ssm get-command-invocation \
	  --command-id $$COMMAND_ID \
	  --instance-id $$INSTANCE_ID \
	  --region eu-west-2 \
	  --query 'StandardOutputContent' \
	  --output text

# US East workspace targets
plan-us: ## Plan US East deployment
	@echo "Planning for workspace: us-east"
	$(TF) workspace select us-east
	$(TF) plan -var-file="us-east.tfvars" -out=tfplan

apply-us: ## Apply US East deployment
	@echo "Applying for workspace: us-east"
	$(TF) workspace select us-east
	$(TF) apply -var-file="us-east.tfvars"

destroy-us: ## Destroy US East deployment
	@echo "Destroying workspace: us-east"
	$(TF) workspace select us-east
	$(TF) destroy -var-file="us-east.tfvars"

connect-us: ## Connect to US East agent
	@$(TF) workspace select us-east
	@echo "Connecting to US East agent..."
	@./scripts/connect-agent.sh

logs-us: ## Tail US East agent logs
	@$(TF) workspace select us-east
	@LOG_GROUP=$$($(TF) output -json agent_instances | jq -r '.[keys[0]].log_group_name'); \
	echo "Tailing US East logs: $$LOG_GROUP"; \
	aws logs tail $$LOG_GROUP --follow --region us-east-1

# Convenience aliases
p: plan
a: apply
d: destroy
f: fmt
v: validate
c: connect
l: logs
