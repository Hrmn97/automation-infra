# SFTP User Management

This guide explains how to create and manage SFTP users for customer document uploads.

## Overview

AWS Transfer Family uses **SSH key-based authentication**. Here's the workflow:

1. **Customer generates** their SSH key pair (private + public)
2. **Customer keeps** their private key (never share)
3. **Customer sends you** their public key (safe to share)
4. **You create** their SFTP user with the public key
5. **Customer connects** using their private key

## For Customers: Generating SSH Keys

Send these instructions to your customers to generate their SSH key pair:

### On Mac/Linux:

```bash
# Generate a new SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/servefirst-sftp -C "company-name"

# This creates two files:
# ~/.ssh/servefirst-sftp      (PRIVATE KEY - keep secret!)
# ~/.ssh/servefirst-sftp.pub  (PUBLIC KEY - send to ServeFirst)
```

### On Windows (PowerShell):

```powershell
# Generate a new SSH key pair
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\servefirst-sftp -C "company-name"

# This creates two files:
# %USERPROFILE%\.ssh\servefirst-sftp      (PRIVATE KEY - keep secret!)
# %USERPROFILE%\.ssh\servefirst-sftp.pub  (PUBLIC KEY - send to ServeFirst)
```

**Customer should email you the `.pub` file (public key) only!**

## For Admins: Creating SFTP Users

### Prerequisites

1. Terraform infrastructure deployed (runs the `client-uploads.tf`)
2. AWS CLI configured with appropriate credentials
3. Customer's SSH public key file

### Creating a User

```bash
cd /Users/alanmayer/Developer/servefirst/sf-terraform/scripts

# For production
./create-sftp-user.sh prod acme-corp ~/Downloads/customer-key.pub

# For staging
./create-sftp-user.sh stage test-company ~/Downloads/customer-key.pub
```

### Script Parameters

- **environment**: `prod` or `stage`
- **username**: Customer identifier (lowercase, hyphens, e.g., `acme-corp`)
- **ssh-public-key-file**: Path to customer's public key file

### What the Script Does

1. ✅ Creates an IAM role for the customer with S3 access
2. ✅ Creates an IAM policy scoped to their bucket prefix
3. ✅ Creates the Transfer Family user
4. ✅ Adds their SSH public key
5. ✅ Sets up their home directory: `s3://BUCKET/username/`
6. ✅ Creates the S3 directory if it doesn't exist

### Security Model

Each customer gets:
- Their own IAM role
- Access **only** to their prefix: `s3://BUCKET/username/*`
- Cannot see or access other customers' files
- Cannot list the root bucket

## Connection Details for Customers

After running the script, share these details with the customer.

### Get the Server Endpoint

To find your SFTP server endpoint, run:

```bash
# For staging
aws transfer list-servers --query "Servers[?contains(Tags[?Key=='Name'].Value, 'stage-client-uploads-transfer')].[ServerId]" --output text

# For production  
aws transfer list-servers --query "Servers[?contains(Tags[?Key=='Name'].Value, 'prod-client-uploads-transfer')].[ServerId]" --output text
```

This returns something like: `s-1234567890abcdef0`

The full SFTP host is: `s-1234567890abcdef0.server.transfer.eu-west-2.amazonaws.com`

### Share With Customer

```
SFTP Server: s-1234567890abcdef0.server.transfer.eu-west-2.amazonaws.com
Username: acme-corp
Port: 22
Authentication: SSH Key

Connection command:
sftp -i ~/.ssh/servefirst-sftp acme-corp@s-1234567890abcdef0.server.transfer.eu-west-2.amazonaws.com
```

### SFTP Clients

Customers can use:
- **Command line**: `sftp` command (Mac/Linux)
- **GUI**: FileZilla, Cyberduck, WinSCP
- **Automated**: Any SFTP library (Python, Node.js, etc.)

### Example: FileZilla Setup

1. Edit → Settings → SFTP → Add key file (their private key)
2. Host: `sftp://s-xxxxx.server.transfer.eu-west-2.amazonaws.com`
3. Protocol: SFTP
4. Username: `acme-corp`
5. Password: (leave empty - uses key)
6. Port: 22

## Managing Existing Users

### Update User's SSH Key

Run the script again with the same username but a new public key file. It will update the existing user.

```bash
./create-sftp-user.sh prod acme-corp ~/Downloads/new-key.pub
```

### Delete a User

```bash
# Get the server ID
aws transfer list-servers

# Delete the user
aws transfer delete-user --server-id s-xxxxx --user-name acme-corp

# Optionally delete their IAM role and policy
aws iam detach-role-policy --role-name prod-sftp-acme-corp --policy-arn arn:aws:iam::ACCOUNT:policy/prod-sftp-acme-corp-s3-access
aws iam delete-policy --policy-arn arn:aws:iam::ACCOUNT:policy/prod-sftp-acme-corp-s3-access
aws iam delete-role --role-name prod-sftp-acme-corp
```

### List All SFTP Users

```bash
# Get the server ID first
SERVER_ID=$(aws transfer list-servers --query "Servers[?contains(Tags[?Key=='Name'].Value, 'prod-client-uploads-transfer')].ServerId" --output text)

# List users
aws transfer list-users --server-id $SERVER_ID
```

### View User Details

```bash
aws transfer describe-user --server-id s-xxxxx --user-name acme-corp
```

## Bucket Structure

```
servefirst-client-uploads/           (Production)
├── acme-corp/
│   ├── uploads/         # Customer uploads files here (write + read)
│   │   ├── invoice-2024-01.pdf
│   │   └── contract.docx
│   └── processed/       # You put processed files here (customer read-only)
│       └── result.pdf
├── widgets-inc/
│   ├── uploads/
│   │   └── data.csv
│   └── processed/
└── ...

stage-servefirst-client-uploads/     (Staging)
├── test-company/
│   ├── uploads/
│   │   └── test-file.pdf
│   └── processed/
└── ...
```

### Folder Permissions

- **`uploads/`** - Customer can:
  - ✅ Upload files (PUT)
  - ✅ Download files (GET)
  - ✅ View file versions
  - ❌ Delete files (protection against accidental deletion)

- **`processed/`** - Customer can:
  - ✅ Download files (GET)
  - ✅ View file versions
  - ❌ Upload files
  - ❌ Delete files

This structure enables a secure workflow where customers submit files, and you provide processed results.

## Monitoring

### View SFTP Logs

```bash
# CloudWatch Logs
aws logs tail /aws/transfer/prod-client-uploads --follow
```

### Check S3 Access Logs

Enable S3 access logging in Terraform if needed for audit purposes.

## Troubleshooting

### Customer Can't Connect

1. **Wrong endpoint**: Check the server endpoint URL
2. **Wrong key**: Ensure they're using the matching private key
3. **File permissions**: Private key must be `chmod 600` (Mac/Linux)
4. **Key format**: Ensure public key format is correct (starts with `ssh-rsa`, `ssh-ed25519`, etc.)

### Permission Denied

1. Check IAM role is attached correctly
2. Verify S3 bucket policy allows the IAM role
3. Check the home directory mapping is correct

### Can't See Files

Transfer Family users are automatically scoped to their home directory. They can't `cd ..` to see other directories - this is by design.

### Can't Upload to processed/ Folder

This is intentional - customers should only upload to `uploads/`. The `processed/` folder is for you to place files that customers can download.

### Want to Provide a File to Customer

Use the AWS CLI or Console to upload to their `processed/` folder:

```bash
aws s3 cp result.pdf s3://servefirst-client-uploads/acme-corp/processed/
```

## Cost Considerations

**AWS Transfer Family Pricing (as of 2024):**
- ~$0.30 per hour server is running (~$216/month per environment)
- ~$0.04 per GB uploaded/downloaded
- First 50 GB/month free

Consider stopping the staging server when not in use to save costs.

## Security Best Practices

1. ✅ Use SSH keys (never passwords)
2. ✅ Use strong key types (ed25519 or RSA 4096)
3. ✅ Rotate keys annually
4. ✅ Use unique keys per customer
5. ✅ Monitor CloudWatch logs for suspicious activity
6. ✅ Enable S3 versioning (already configured)
7. ✅ Enable S3 encryption (already configured)

