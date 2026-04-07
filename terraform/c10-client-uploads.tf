# =============================================================================
# Client Uploads — S3 Bucket + AWS Transfer Family (SFTP)
#
# What this file provisions:
#   1. S3 bucket that stores all files uploaded by clients (PDFs, docs, etc.)
#   2. Bucket hardening: versioning, AES-256 SSE, full public-access block,
#      and BucketOwnerPreferred ownership controls.
#   3. CloudWatch log group + IAM role so Transfer Family can ship SFTP
#      session logs.
#   4. AWS Transfer Family SFTP server (non-prod only — prod uses a
#      separately managed server to avoid Terraform managing prod SFTP users).
# =============================================================================

locals {
  # prod keeps the legacy unqualified name; all other envs get a prefix.
  client_uploads_bucket_name = (
    var.environment == "prod"
    ? "servefirst-client-uploads"
    : "${var.environment}-servefirst-client-uploads"
  )
}

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "client_uploads" {
  bucket        = local.client_uploads_bucket_name
  force_destroy = var.environment != "prod"

  tags = {
    Name        = "${var.environment}-client-uploads"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "client-uploads"
  }
}

resource "aws_s3_bucket_versioning" "client_uploads" {
  bucket = aws_s3_bucket.client_uploads.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "client_uploads" {
  bucket = aws_s3_bucket.client_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "client_uploads" {
  bucket = aws_s3_bucket.client_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "client_uploads" {
  bucket = aws_s3_bucket.client_uploads.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }

  # Ownership controls must be set before the public-access block takes effect.
  depends_on = [aws_s3_bucket_public_access_block.client_uploads]
}

# -----------------------------------------------------------------------------
# Transfer Family — CloudWatch logging
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "transfer_logs" {
  name              = "/aws/transfer/${var.environment}-client-uploads"
  retention_in_days = 30

  tags = {
    Name        = "${var.environment}-transfer-logs"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "transfer_logging" {
  name = "${var.environment}-transfer-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "transfer.amazonaws.com" }
    }]
  })

  tags = {
    Name        = "${var.environment}-transfer-logging-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "transfer_logging" {
  name = "${var.environment}-transfer-logging-policy"
  role = aws_iam_role.transfer_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
      ]
      # Scoped to the specific log group rather than "*"
      Resource = "${aws_cloudwatch_log_group.transfer_logs.arn}:*"
    }]
  })
}

# -----------------------------------------------------------------------------
# Transfer Family SFTP Server
#
# NOTE: SFTP users are managed OUTSIDE Terraform to avoid storing SSH keys or
# passwords in state.  To add a user:
#   1. Create an IAM role granting access to the user's S3 prefix.
#   2. Run:
#        aws transfer create-user \
#          --server-id <SERVER_ID> \
#          --user-name <USER> \
#          --role <IAM_ROLE_ARN> \
#          --home-directory "/${local.client_uploads_bucket_name}/<USER>" \
#          --ssh-public-key-body "ssh-rsa ..."
#   See sf-terraform/agents/SFTP_ACCESS.md for full runbook.
#
# Skipped in prod (count=0): prod server is managed separately so Terraform
# cannot accidentally destroy prod SFTP sessions during a plan/apply.
# -----------------------------------------------------------------------------

resource "aws_transfer_server" "client_uploads" {
  count = var.environment == "prod" ? 0 : 1

  identity_provider_type = "SERVICE_MANAGED"
  protocols              = ["SFTP"]
  endpoint_type          = "PUBLIC"
  security_policy_name   = "TransferSecurityPolicy-2024-01"
  logging_role           = aws_iam_role.transfer_logging.arn

  tags = {
    Name        = "${var.environment}-client-uploads-sftp"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "client-uploads"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "client_uploads_bucket_name" {
  value       = aws_s3_bucket.client_uploads.id
  description = "Name of the client-uploads S3 bucket."
}

output "client_uploads_bucket_arn" {
  value       = aws_s3_bucket.client_uploads.arn
  description = "ARN of the client-uploads S3 bucket — used in ECS task IAM policies."
}

output "transfer_server_id" {
  value       = length(aws_transfer_server.client_uploads) > 0 ? aws_transfer_server.client_uploads[0].id : null
  description = "Transfer Family server ID (null in prod)."
}

output "transfer_server_endpoint" {
  value       = length(aws_transfer_server.client_uploads) > 0 ? aws_transfer_server.client_uploads[0].endpoint : null
  description = "SFTP endpoint hostname (null in prod)."
}
