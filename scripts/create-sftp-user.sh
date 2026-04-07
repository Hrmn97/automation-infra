#!/bin/bash

# Script to create an AWS Transfer Family SFTP user with S3 bucket access
# Usage: ./create-sftp-user.sh <environment> <username> <ssh-public-key-file>
#
# Example: ./create-sftp-user.sh prod acme-corp ~/.ssh/acme-corp.pub

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ "$#" -ne 3 ]; then
    echo -e "${RED}Error: Invalid number of arguments${NC}"
    echo "Usage: $0 <environment> <username> <ssh-public-key-file>"
    echo ""
    echo "Arguments:"
    echo "  environment         - prod or stage"
    echo "  username           - SFTP username (e.g., acme-corp)"
    echo "  ssh-public-key-file - Path to customer's SSH public key file"
    echo ""
    echo "Example:"
    echo "  $0 prod acme-corp ~/.ssh/acme-corp.pub"
    exit 1
fi

ENVIRONMENT=$1
USERNAME=$2
SSH_KEY_FILE=$3

# Validate environment
if [[ "$ENVIRONMENT" != "prod" && "$ENVIRONMENT" != "stage" ]]; then
    echo -e "${RED}Error: Environment must be 'prod' or 'stage'${NC}"
    exit 1
fi

# Set bucket name based on environment
if [ "$ENVIRONMENT" == "prod" ]; then
    BUCKET_NAME="servefirst-client-uploads"
else
    BUCKET_NAME="stage-servefirst-client-uploads"
fi

# Validate SSH key file exists
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo -e "${RED}Error: SSH public key file not found: $SSH_KEY_FILE${NC}"
    exit 1
fi

# Read the SSH public key
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_FILE")

# Validate it looks like a public key
if [[ ! "$SSH_PUBLIC_KEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
    echo -e "${RED}Error: File does not appear to be a valid SSH public key${NC}"
    echo "Public keys should start with 'ssh-rsa', 'ssh-ed25519', or 'ssh-ecdsa'"
    exit 1
fi

echo -e "${GREEN}Creating SFTP user: $USERNAME${NC}"
echo "Environment: $ENVIRONMENT"
echo "Bucket: $BUCKET_NAME"
echo "Home Directory: /$BUCKET_NAME/$USERNAME/"
echo ""

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
AWS_REGION=${AWS_REGION:-eu-west-2}

echo "AWS Account: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
echo ""

# IAM Role name
ROLE_NAME="${ENVIRONMENT}-sftp-${USERNAME}"

# Check if role already exists
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Warning: IAM role $ROLE_NAME already exists. Skipping role creation.${NC}"
else
    echo "Creating IAM role: $ROLE_NAME"
    
    # Create trust policy for Transfer Family
    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "transfer.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
    
    # Create the IAM role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "SFTP access for $USERNAME in $ENVIRONMENT" \
        --tags "Key=Environment,Value=$ENVIRONMENT" "Key=Service,Value=sftp" "Key=Customer,Value=$USERNAME" \
        --output text > /dev/null
    
    echo -e "${GREEN}✓ IAM role created${NC}"
fi

# Create/Update the IAM policy for S3 access
POLICY_NAME="${ROLE_NAME}-s3-access"

echo "Creating IAM policy: $POLICY_NAME"

# S3 access policy - scoped to user's prefix with folder-based permissions
S3_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowListingOfUserFolder",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}",
      "Condition": {
        "StringLike": {
          "s3:prefix": [
            "${USERNAME}/*",
            "${USERNAME}"
          ]
        }
      }
    },
    {
      "Sid": "AllowUploadToUploadsFolder",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/${USERNAME}/uploads/*"
    },
    {
      "Sid": "AllowReadFromProcessedFolder",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/${USERNAME}/processed/*"
    }
  ]
}
EOF
)

# Check if policy exists
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
    echo -e "${YELLOW}Policy already exists. Creating new version...${NC}"
    
    # Delete old versions if we're at the limit (5 versions max)
    VERSION_COUNT=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'length(Versions)' --output text)
    if [ "$VERSION_COUNT" -ge 5 ]; then
        OLDEST_VERSION=$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --query 'Versions[-1].VersionId' --output text)
        aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$OLDEST_VERSION"
    fi
    
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document "$S3_POLICY" \
        --set-as-default
else
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document "$S3_POLICY" \
        --description "S3 access for SFTP user $USERNAME" \
        --output text > /dev/null
fi

echo -e "${GREEN}✓ IAM policy created/updated${NC}"

# Attach policy to role
echo "Attaching policy to role..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" \
    --output text > /dev/null 2>&1 || echo -e "${YELLOW}Policy may already be attached${NC}"

echo -e "${GREEN}✓ Policy attached to role${NC}"

# Get Transfer Server ID
echo "Finding Transfer Family server..."
# List all servers and check each one's tags
TRANSFER_SERVER_ID=""
for server_id in $(aws transfer list-servers --query 'Servers[].ServerId' --output text); do
    server_name=$(aws transfer list-tags-for-resource --arn "arn:aws:transfer:${AWS_REGION}:${AWS_ACCOUNT_ID}:server/${server_id}" \
        --query "Tags[?Key=='Name'].Value" --output text 2>/dev/null)
    if [ "$server_name" == "${ENVIRONMENT}-client-uploads-transfer" ]; then
        TRANSFER_SERVER_ID=$server_id
        break
    fi
done

if [ -z "$TRANSFER_SERVER_ID" ]; then
    echo -e "${RED}Error: Could not find Transfer Family server for environment: $ENVIRONMENT${NC}"
    echo "Please ensure the Terraform infrastructure is deployed."
    exit 1
fi

echo "Transfer Server ID: $TRANSFER_SERVER_ID"
echo ""

# Check if user already exists
if aws transfer describe-user \
    --server-id "$TRANSFER_SERVER_ID" \
    --user-name "$USERNAME" &>/dev/null; then
    
    echo -e "${YELLOW}User $USERNAME already exists. Updating configuration...${NC}"
    
    # Update existing user
    aws transfer update-user \
        --server-id "$TRANSFER_SERVER_ID" \
        --user-name "$USERNAME" \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --home-directory-type LOGICAL \
        --home-directory-mappings "[{\"Entry\":\"/\",\"Target\":\"/${BUCKET_NAME}/${USERNAME}\"}]" \
        --output text > /dev/null
    
    echo -e "${GREEN}✓ User updated${NC}"
    
    # Import/update SSH key
    echo "Updating SSH public key..."
    
    # Get existing keys from describe-user
    EXISTING_KEYS=$(aws transfer describe-user \
        --server-id "$TRANSFER_SERVER_ID" \
        --user-name "$USERNAME" \
        --output json | jq -r '.User.SshPublicKeys[]?.SshPublicKeyId // empty')
    
    # Delete old keys
    if [ -n "$EXISTING_KEYS" ]; then
        for KEY_ID in $EXISTING_KEYS; do
            aws transfer delete-ssh-public-key \
                --server-id "$TRANSFER_SERVER_ID" \
                --user-name "$USERNAME" \
                --ssh-public-key-id "$KEY_ID" \
                --output text > /dev/null 2>&1
        done
    fi
    
    # Import new key
    aws transfer import-ssh-public-key \
        --server-id "$TRANSFER_SERVER_ID" \
        --user-name "$USERNAME" \
        --ssh-public-key-body "$SSH_PUBLIC_KEY" \
        --output text > /dev/null
    
    echo -e "${GREEN}✓ SSH key updated${NC}"
else
    echo "Creating new Transfer Family user..."
    
    # Create new user
    aws transfer create-user \
        --server-id "$TRANSFER_SERVER_ID" \
        --user-name "$USERNAME" \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --home-directory-type LOGICAL \
        --home-directory-mappings "[{\"Entry\":\"/\",\"Target\":\"/${BUCKET_NAME}/${USERNAME}\"}]" \
        --ssh-public-key-body "$SSH_PUBLIC_KEY" \
        --tags "Key=Environment,Value=$ENVIRONMENT" "Key=Customer,Value=$USERNAME" \
        --output text > /dev/null
    
    echo -e "${GREEN}✓ User created${NC}"
fi

# Create the user's directories in S3 (if they don't exist)
echo "Creating S3 folder structure..."

# Create uploads folder (customer can upload here)
aws s3api put-object \
    --bucket "$BUCKET_NAME" \
    --key "${USERNAME}/uploads/" \
    --content-length 0 \
    --output text > /dev/null 2>&1

# Create processed folder (customer can download from here)
aws s3api put-object \
    --bucket "$BUCKET_NAME" \
    --key "${USERNAME}/processed/" \
    --content-length 0 \
    --output text > /dev/null 2>&1

echo -e "${GREEN}✓ S3 folders created (uploads/ and processed/)${NC}"

# Get server endpoint
# For PUBLIC endpoints, there's no custom address, so we use the server ID directly
ENDPOINT_TYPE=$(aws transfer describe-server \
    --server-id "$TRANSFER_SERVER_ID" \
    --query 'Server.EndpointType' \
    --output text)

if [ "$ENDPOINT_TYPE" == "PUBLIC" ]; then
    SERVER_ENDPOINT="${TRANSFER_SERVER_ID}.server.transfer.${AWS_REGION}.amazonaws.com"
else
    # For VPC endpoints, get the custom address
    SERVER_ENDPOINT=$(aws transfer describe-server \
        --server-id "$TRANSFER_SERVER_ID" \
        --query 'Server.EndpointDetails.VpcEndpointId' \
        --output text)
    SERVER_ENDPOINT="${SERVER_ENDPOINT}.vpce.transfer.${AWS_REGION}.amazonaws.com"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SFTP User Created Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Connection Details to share with customer:"
echo "-------------------------------------------"
echo "SFTP Server: ${SERVER_ENDPOINT}"
echo "Username: $USERNAME"
echo "Port: 22 (standard SFTP)"
echo "Authentication: SSH Key (they use their private key)"
echo "Home Directory: /${BUCKET_NAME}/${USERNAME}/"
echo ""
echo "Folder Structure:"
echo "  - uploads/    (Customer can upload files here)"
echo "  - processed/  (Customer can download files from here - read-only)"
echo ""
echo "Example connection command:"
echo "  sftp -i /path/to/their/private/key ${USERNAME}@${SERVER_ENDPOINT}"
echo ""
echo "Example usage:"
echo "  sftp> cd uploads"
echo "  sftp> put myfile.pdf"
echo "  sftp> cd ../processed"
echo "  sftp> get result.pdf"
echo ""
echo "Resources Created:"
echo "  - IAM Role: $ROLE_NAME"
echo "  - IAM Policy: $POLICY_NAME"
echo "  - Transfer User: $USERNAME"
echo "  - S3 Structure: s3://${BUCKET_NAME}/${USERNAME}/uploads/"
echo "                  s3://${BUCKET_NAME}/${USERNAME}/processed/"
echo ""

