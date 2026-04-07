#!/bin/bash
# validate-config.sh
# Pre-deployment validation script for OpenClaw Agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

echo "OpenClaw Agents - Configuration Validation"
echo "==========================================="
echo ""

# Check 1: Terraform installed
echo -n "Checking Terraform installation... "
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
    echo -e "${GREEN}✓${NC} Terraform $TF_VERSION"
else
    echo -e "${RED}✗${NC} Terraform not found"
    ((ERRORS++))
fi

# Check 2: AWS CLI installed
echo -n "Checking AWS CLI installation... "
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
    echo -e "${GREEN}✓${NC} AWS CLI $AWS_VERSION"
else
    echo -e "${RED}✗${NC} AWS CLI not found"
    ((ERRORS++))
fi

# Check 3: AWS credentials configured
echo -n "Checking AWS credentials... "
if aws sts get-caller-identity &> /dev/null; then
    AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER=$(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)
    echo -e "${GREEN}✓${NC} $AWS_USER (Account: $AWS_ACCOUNT)"
else
    echo -e "${RED}✗${NC} AWS credentials not configured"
    ((ERRORS++))
fi

# Check 4: Required tools (jq)
echo -n "Checking jq installation... "
if command -v jq &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} jq not found (optional but recommended)"
    ((WARNINGS++))
fi

# Check 5: Terraform configuration files exist
echo -n "Checking Terraform configuration... "
if [[ -f "$ROOT_DIR/main.tf" && -f "$ROOT_DIR/variables.tf" ]]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Missing main.tf or variables.tf"
    ((ERRORS++))
fi

# Check 6: terraform.tfvars exists
echo -n "Checking terraform.tfvars... "
if [[ -f "$ROOT_DIR/terraform.tfvars" ]]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} terraform.tfvars not found (using defaults or variables)"
    ((WARNINGS++))
fi

# Check 7: Terraform init
echo -n "Checking Terraform initialization... "
if [[ -d "$ROOT_DIR/.terraform" ]]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠${NC} Terraform not initialized (run: terraform init)"
    ((WARNINGS++))
fi

# Check 8: Terraform validate
echo -n "Running terraform validate... "
cd "$ROOT_DIR"
if terraform validate &> /dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC} Terraform validation failed"
    terraform validate
    ((ERRORS++))
fi

# Check 9: Bedrock service availability
if aws sts get-caller-identity &> /dev/null; then
    REGION=${AWS_REGION:-$(aws configure get region)}
    echo -n "Checking Bedrock availability in $REGION... "
    
    # Try to list Bedrock models (requires Bedrock enabled)
    if aws bedrock list-foundation-models --region "$REGION" &> /dev/null; then
        MODEL_COUNT=$(aws bedrock list-foundation-models --region "$REGION" --query 'length(modelSummaries)' --output text)
        echo -e "${GREEN}✓${NC} $MODEL_COUNT models available"
    else
        echo -e "${YELLOW}⚠${NC} Cannot access Bedrock (may need to enable in console)"
        ((WARNINGS++))
    fi
fi

# Check 10: VPC CIDR conflicts (if terraform.tfvars exists)
if [[ -f "$ROOT_DIR/terraform.tfvars" ]]; then
    echo -n "Checking VPC CIDR conflicts... "
    VPC_CIDR=$(grep '^vpc_cidr' "$ROOT_DIR/terraform.tfvars" | cut -d'"' -f2 || echo "")
    
    if [[ -n "$VPC_CIDR" ]] && aws ec2 describe-vpcs &> /dev/null; then
        EXISTING_CIDRS=$(aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --output text)
        
        if echo "$EXISTING_CIDRS" | grep -q "$VPC_CIDR"; then
            echo -e "${YELLOW}⚠${NC} VPC CIDR $VPC_CIDR already exists in account"
            ((WARNINGS++))
        else
            echo -e "${GREEN}✓${NC} No conflicts"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Skipped (no VPC CIDR in tfvars or cannot query AWS)"
    fi
fi

# Check 11: Agent configuration validation
if [[ -f "$ROOT_DIR/terraform.tfvars" ]]; then
    echo "Checking agent configurations..."
    
    # Check for latest tag (forbidden)
    if grep -q 'openclaw_version.*latest' "$ROOT_DIR/terraform.tfvars"; then
        echo -e "  ${RED}✗${NC} Found 'latest' tag in openclaw_version (must use pinned version)"
        ((ERRORS++))
    else
        echo -e "  ${GREEN}✓${NC} No 'latest' tags found"
    fi
    
    # Check for enable_marketplace = true (warning)
    if grep -q 'enable_marketplace.*true' "$ROOT_DIR/terraform.tfvars"; then
        echo -e "  ${YELLOW}⚠${NC} Marketplace enabled (security risk)"
        ((WARNINGS++))
    else
        echo -e "  ${GREEN}✓${NC} Marketplace disabled"
    fi
    
    # Check for break_glass_mode
    if grep -q 'break_glass_mode.*true' "$ROOT_DIR/terraform.tfvars"; then
        echo -e "  ${YELLOW}⚠${NC} Break-glass mode enabled (no internet access)"
        ((WARNINGS++))
    fi
fi

# Check 12: Cost estimation (if infracost available)
if command -v infracost &> /dev/null; then
    echo -n "Estimating costs... "
    COST=$(infracost breakdown --path "$ROOT_DIR" --format json 2>/dev/null | jq -r '.totalMonthlyCost' || echo "N/A")
    if [[ "$COST" != "N/A" ]]; then
        echo -e "${GREEN}✓${NC} Estimated monthly cost: \$$COST"
    else
        echo -e "${YELLOW}⚠${NC} Could not estimate costs"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary:"
echo "  Errors:   $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}✗ Validation failed with $ERRORS error(s)${NC}"
    echo "Please fix the errors before deploying."
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Validation passed with $WARNINGS warning(s)${NC}"
    echo "Review warnings before deploying."
    exit 0
else
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "Ready to deploy."
    exit 0
fi
