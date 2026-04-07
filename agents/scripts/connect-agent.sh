#!/bin/bash
# connect-agent.sh
# Helper script to connect to an OpenClaw agent via SSM Session Manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    echo "Install: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Get agent instances from Terraform output
cd "$ROOT_DIR"

if ! terraform output -json agent_instances &> /dev/null; then
    echo "Error: Cannot get Terraform outputs. Have you deployed the infrastructure?"
    echo "Run: terraform apply"
    exit 1
fi

AGENTS=$(terraform output -json agent_instances | jq -r 'keys[]' 2>/dev/null)

if [[ -z "$AGENTS" ]]; then
    echo "Error: No agents found in Terraform state"
    exit 1
fi

# If agent name provided as argument, use it
if [[ $# -eq 1 ]]; then
    AGENT_NAME="$1"
else
    # Show menu of agents
    echo "Available agents:"
    echo ""
    
    i=1
    declare -a AGENT_ARRAY
    while IFS= read -r agent; do
        INSTANCE_ID=$(terraform output -json agent_instances | jq -r ".\"$agent\".instance_id")
        PRIVATE_IP=$(terraform output -json agent_instances | jq -r ".\"$agent\".private_ip")
        echo "  $i) $agent ($INSTANCE_ID - $PRIVATE_IP)"
        AGENT_ARRAY[$i]="$agent"
        ((i++))
    done <<< "$AGENTS"
    
    echo ""
    read -p "Select agent (1-$((i-1))): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -ge "$i" ]]; then
        echo "Error: Invalid selection"
        exit 1
    fi
    
    AGENT_NAME="${AGENT_ARRAY[$selection]}"
fi

# Get instance details
INSTANCE_ID=$(terraform output -json agent_instances | jq -r ".\"$AGENT_NAME\".instance_id")
PRIVATE_IP=$(terraform output -json agent_instances | jq -r ".\"$AGENT_NAME\".private_ip")

# Get region from AWS CLI config, environment variable, or default to eu-west-2
AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "eu-west-2")}

if [[ "$INSTANCE_ID" == "null" || -z "$INSTANCE_ID" ]]; then
    echo "Error: Agent '$AGENT_NAME' not found"
    exit 1
fi

echo -e "${GREEN}Connecting to: $AGENT_NAME${NC}"
echo "  Instance ID: $INSTANCE_ID"
echo "  Private IP:  $PRIVATE_IP"
echo "  Region:      $AWS_REGION"
echo ""
echo "Once connected, you can:"
echo "  - View logs:       sudo journalctl -u openclaw-agent -f"
echo "  - Check Docker:    sudo docker ps"
echo "  - Check health:    curl http://localhost:8080/health"
echo "  - Container logs:  sudo docker logs -f openclaw-agent-$AGENT_NAME"
echo ""

# Check instance state
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null || echo "unknown")

if [[ "$INSTANCE_STATE" != "running" ]]; then
    echo -e "${YELLOW}Warning: Instance is in '$INSTANCE_STATE' state${NC}"
    read -p "Continue anyway? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Start SSM session
echo "Starting SSM session..."
echo ""

aws ssm start-session \
    --target "$INSTANCE_ID" \
    --region "$AWS_REGION"
