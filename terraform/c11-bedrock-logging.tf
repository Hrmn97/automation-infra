# =============================================================================
# Bedrock Model Invocation Logging — Account-Level Singleton
#
# IMPORTANT: aws_bedrock_model_invocation_logging_configuration is an
# account-level singleton — AWS allows exactly ONE per region per account.
# All resources here are intentionally environment-agnostic so that both
# stage and prod workspaces produce identical plans and never conflict.
#
# All Bedrock invocations in eu-west-2 are logged to the same destinations
# regardless of which workspace is active.  To distinguish environments in
# log data, filter on the IAM role ARN (e.g. stage-ecsTaskRole vs
# prod-ecsTaskRole) — not on the log group name.
#
# =============================================================================

locals {
  bedrock_log_group_name = "/aws/bedrock/modelinvocations"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "bedrock_invocations" {
  name              = local.bedrock_log_group_name
  retention_in_days = 30

  tags = {
    Name      = "bedrock-invocations"
    ManagedBy = "terraform"
    # "shared" signals this is account-wide, not per-workspace
    Environment = "shared"
    Purpose     = "Bedrock Model Invocation Logs"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# IAM Role + Policies for Bedrock → CloudWatch + S3
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bedrock_logging" {
  name = "bedrock-logging-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "bedrock-logging-role"
    ManagedBy   = "terraform"
    Environment = "shared"
  }
}

resource "aws_iam_role_policy" "bedrock_logging_cw" {
  name = "bedrock-logging-cloudwatch-policy"
  role = aws_iam_role.bedrock_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.bedrock_invocations.arn}:*"
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_logging_s3" {
  name = "bedrock-logging-s3-policy"
  role = aws_iam_role.bedrock_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
      ]
      Resource = [
        aws_s3_bucket.bedrock_logs.arn,
        "${aws_s3_bucket.bedrock_logs.arn}/*",
      ]
    }]
  })
}

# -----------------------------------------------------------------------------
# S3 Bucket — request/response payloads + large-payload overflow
#
# No env prefix: this is the one shared bucket for all workspaces.
# force_destroy = false + prevent_destroy guard against accidental wipe.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "bedrock_logs" {
  bucket        = "servefirst-bedrock-logs"
  force_destroy = false

  tags = {
    Name        = "bedrock-logs"
    ManagedBy   = "terraform"
    Environment = "shared"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "bedrock_logs" {
  bucket = aws_s3_bucket.bedrock_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    # Empty filter = applies to all objects (required by AWS provider ≥ 4.x)
    filter {}

    expiration {
      days = 90
    }
  }
}

# -----------------------------------------------------------------------------
# Bedrock Model Invocation Logging Configuration
#
# Logs both to CloudWatch (searchable, short-term) and S3 (long-term, cheap).
# Large payloads (>256 KB) that exceed CloudWatch limits overflow to S3 as well.
# -----------------------------------------------------------------------------

resource "aws_bedrock_model_invocation_logging_configuration" "main" {
  logging_config {
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.bedrock_logs.id
        key_prefix  = "large-payloads/"
      }
    }

    s3_config {
      bucket_name = aws_s3_bucket.bedrock_logs.id
      key_prefix  = "invocation-logs/"
    }

    text_data_delivery_enabled      = true  # Claude etc.
    image_data_delivery_enabled     = false # no image models in use
    embedding_data_delivery_enabled = true  # Titan Embed
  }

  # Explicit ordering: IAM policies must exist before Bedrock tries to write
  depends_on = [
    aws_iam_role_policy.bedrock_logging_cw,
    aws_iam_role_policy.bedrock_logging_s3,
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "bedrock_logging" {
  value = {
    log_group_name    = aws_cloudwatch_log_group.bedrock_invocations.name
    log_group_arn     = aws_cloudwatch_log_group.bedrock_invocations.arn
    s3_bucket         = aws_s3_bucket.bedrock_logs.id
    s3_bucket_arn     = aws_s3_bucket.bedrock_logs.arn
    role_arn          = aws_iam_role.bedrock_logging.arn
    logging_config_id = aws_bedrock_model_invocation_logging_configuration.main.id
  }
  description = "Bedrock logging infrastructure details — consumed by c21-outputs.tf."
}
