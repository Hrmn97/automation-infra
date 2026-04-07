# =============================================================================
# Bedrock Knowledge Base — RAW S3 → OpenSearch Serverless → Bedrock KB
#
# What this file provisions (in dependency order):
#   1. S3 "raw" bucket  — landing zone for unstructured docs to be ingested
#   2. S3 bucket policy — lets Bedrock KB role read and API task role write
#   3. IAM role + policy for Bedrock to access S3 and the AOSS collection
#   4. OpenSearch Serverless (AOSS) security policies (encryption + network)
#   5. AOSS collection  — the vector store backing the KB
#   6. AOSS access policy — grants Bedrock KB role and the deploying account
#      full index control
#   7. time_sleep (x2) — propagation guards: AOSS access policies and IAM
#      role policies need ~20–30 s before Bedrock/OpenSearch will honour them
#   8. opensearch_index — creates the kNN vector index inside the collection
#   9. aws_bedrockagent_knowledge_base — the KB itself (VECTOR / AOSS)
# =============================================================================

locals {
  kb_base_name           = "kb-servefirst-${var.environment}"
  kb_raw_bucket_name     = "servefirst-${var.environment}-kb-raw"
  kb_collection_name     = "kb-servefirst-${var.environment}"
  kb_vector_index_name   = "bedrock-knowledge-base-default-index"
  kb_vector_field        = "bedrock-knowledge-base-default-vector"
  kb_text_field          = "AMAZON_BEDROCK_TEXT_CHUNK"
  kb_metadata_field      = "AMAZON_BEDROCK_METADATA"
  kb_embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"

  # CORS: localhost only open in stage for local dev (port 5002 = local API)
  _kb_extra_origins  = var.environment == "stage" ? ["http://localhost:5002"] : []
  kb_allowed_origins = concat(["https://${var.fe_domain_name}"], local._kb_extra_origins)
}

# -----------------------------------------------------------------------------
# S3 Raw Bucket — document landing zone
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "kb_raw" {
  bucket        = lower(local.kb_raw_bucket_name)
  force_destroy = var.environment != "prod"

  tags = {
    Name        = "${var.environment}-kb-raw"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "knowledge-base"
  }
}

resource "aws_s3_bucket_versioning" "kb_raw" {
  bucket = aws_s3_bucket.kb_raw.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb_raw" {
  bucket = aws_s3_bucket.kb_raw.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "kb_raw" {
  bucket                  = aws_s3_bucket.kb_raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "kb_raw" {
  bucket = aws_s3_bucket.kb_raw.id
  rule { object_ownership = "BucketOwnerPreferred" }

  depends_on = [aws_s3_bucket_public_access_block.kb_raw]
}

resource "aws_s3_bucket_cors_configuration" "kb_raw" {
  bucket = aws_s3_bucket.kb_raw.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = local.kb_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# -----------------------------------------------------------------------------
# IAM Role — lets Bedrock read from S3 + write to AOSS + invoke Titan Embed
# -----------------------------------------------------------------------------

resource "aws_iam_role" "bedrock_kb_role" {
  name = "${var.environment}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.environment}-bedrock-kb-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

data "aws_iam_policy_document" "bedrock_kb_role" {
  # Read raw docs from S3
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.kb_raw.arn,
      "${aws_s3_bucket.kb_raw.arn}/*",
    ]
  }

  # Full AOSS access for index operations
  statement {
    effect = "Allow"
    actions = [
      "aoss:APIAccessAll",
      "aoss:ListCollections",
      "aoss:BatchGetCollection",
    ]
    resources = [
      aws_opensearchserverless_collection.kb.arn,
      "${aws_opensearchserverless_collection.kb.arn}/*",
    ]
  }

  # Invoke Titan Embed to vectorise chunks
  statement {
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.kb_embedding_model_arn]
  }
}

resource "aws_iam_role_policy" "bedrock_kb_role" {
  name   = "${var.environment}-bedrock-kb-access"
  role   = aws_iam_role.bedrock_kb_role.id
  policy = data.aws_iam_policy_document.bedrock_kb_role.json
}

# -----------------------------------------------------------------------------
# S3 Bucket Policy — bucket-side enforcement (defence-in-depth)
# Bedrock KB role: read-only.  API task role: read + write + delete.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kb_bucket" {
  statement {
    sid = "AllowBedrockKbRoleRead"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.bedrock_kb_role.arn]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:GetObjectAttributes",
    ]
    resources = ["${aws_s3_bucket.kb_raw.arn}/*"]
  }

  statement {
    sid = "AllowBedrockKbRoleList"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.bedrock_kb_role.arn]
    }
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.kb_raw.arn]
  }

  statement {
    sid = "AllowApiTaskRoleWrite"
    principals {
      type        = "AWS"
      identifiers = [module.api_setup.ecs_task_role_arn]
    }
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.kb_raw.arn}/*"]
  }

  statement {
    sid = "AllowApiTaskRoleList"
    principals {
      type        = "AWS"
      identifiers = [module.api_setup.ecs_task_role_arn]
    }
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.kb_raw.arn]
  }
}

resource "aws_s3_bucket_policy" "kb_raw" {
  bucket = aws_s3_bucket.kb_raw.id
  policy = data.aws_iam_policy_document.kb_bucket.json

  depends_on = [module.api_setup]
}

# -----------------------------------------------------------------------------
# OpenSearch Serverless (AOSS) — encryption, network, collection, access
# -----------------------------------------------------------------------------

# Encryption policy — AWS-owned KMS key (simplest; can be swapped for CMK)
resource "aws_opensearchserverless_security_policy" "kb_encryption" {
  name = "${var.environment}-kb-encryption"
  type = "encryption"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.kb_collection_name}"]
    }]
    AWSOwnedKey = true
  })
}

# Network policy — public endpoint for both data and dashboard access.
# The collection is still auth-gated via the access policy below.
resource "aws_opensearchserverless_security_policy" "kb_network" {
  name = "${var.environment}-kb-network"
  type = "network"

  policy = jsonencode([
    {
      Rules = [{
        ResourceType = "collection"
        Resource     = ["collection/${local.kb_collection_name}"]
      }]
      AllowFromPublic = true
    },
    {
      Rules = [{
        ResourceType = "dashboard"
        Resource     = ["collection/${local.kb_collection_name}"]
      }]
      AllowFromPublic = true
    },
  ])
}

resource "aws_opensearchserverless_collection" "kb" {
  name = local.kb_collection_name
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.kb_encryption,
    aws_opensearchserverless_security_policy.kb_network,
  ]
}

# Data access policy — Bedrock KB role gets full index ops.
# Admin access is granted to stable IAM ARNs rather than
# data.aws_caller_identity.current.arn, which resolves to whoever is
# running Terraform (a different ARN for local runs vs CI), causing a
# spurious policy diff on every plan and potentially locking out the other
# identity.
locals {
  opensearch_admin_principals = [
    "arn:aws:iam::${var.project_id}:user/deploy",                   # local / manual runs
    "arn:aws:iam::${var.project_id}:role/github-actions-terraform", # CI runs (GitHub Actions)
  ]
}

resource "aws_opensearchserverless_access_policy" "kb" {
  name = "${var.environment}-kb-access"
  type = "data"

  policy = jsonencode([{
    Description = "Bedrock KB role + stable admin access"
    Rules = [{
      ResourceType = "index"
      Resource     = ["index/${local.kb_collection_name}/*"]
      Permission = [
        "aoss:CreateIndex",
        "aoss:DeleteIndex",
        "aoss:DescribeIndex",
        "aoss:ReadDocument",
        "aoss:WriteDocument",
        "aoss:UpdateIndex",
      ]
    }]
    Principal = concat(
      [aws_iam_role.bedrock_kb_role.arn],
      local.opensearch_admin_principals,
    )
  }])
}

# AOSS access policies take ~30 s to propagate after creation.
# Without this guard, opensearch_index creation races and fails with 403.
resource "time_sleep" "opensearch_access_policy_propagation" {
  create_duration = "30s"

  # Re-trigger whenever the policy document changes
  triggers = {
    policy_version = aws_opensearchserverless_access_policy.kb.policy_version
  }

  lifecycle { create_before_destroy = true }

  depends_on = [aws_opensearchserverless_access_policy.kb]
}

# -----------------------------------------------------------------------------
# Vector Index
#
# kNN index with:
#   - HNSW graph (faiss engine) — fast approximate nearest-neighbour search
#   - 1024 dimensions — matches Titan Embed Text v2 output size
#   - innerproduct space_type — equivalent to dot-product (Bedrock default)
#
# IMPORTANT: Use "innerproduct", NOT "l2" (Euclidean). Wrong space_type
# silently breaks semantic search (scores look valid but rankings are wrong).
#
# If apply fails here on first run, wait 60–90 s for the collection to become
# ACTIVE, then re-run terraform apply.
# -----------------------------------------------------------------------------

resource "opensearch_index" "kb" {
  name               = local.kb_vector_index_name
  number_of_shards   = "2"
  number_of_replicas = "0"
  index_knn          = true
  force_destroy      = true

  mappings = jsonencode({
    properties = {
      "${local.kb_vector_field}" = {
        type      = "knn_vector"
        dimension = 1024
        method = {
          name       = "hnsw"
          engine     = "faiss"
          space_type = "innerproduct"
          parameters = { m = 16, ef_construction = 512 }
        }
      }
      "${local.kb_text_field}"     = { type = "text", index = true }
      "${local.kb_metadata_field}" = { type = "text", index = false }
    }
  })

  depends_on = [
    aws_opensearchserverless_collection.kb,
    time_sleep.opensearch_access_policy_propagation,
  ]
}

# IAM role policy also needs ~20 s to propagate before Bedrock will accept it
resource "time_sleep" "bedrock_kb_iam_propagation" {
  create_duration = "20s"

  depends_on = [
    aws_iam_role_policy.bedrock_kb_role,
    opensearch_index.kb,
  ]
}

# -----------------------------------------------------------------------------
# Bedrock Knowledge Base
# -----------------------------------------------------------------------------

resource "aws_bedrockagent_knowledge_base" "kb" {
  name        = local.kb_base_name
  role_arn    = aws_iam_role.bedrock_kb_role.arn
  description = "ServeFirst ${var.environment} knowledge base"

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = local.kb_embedding_model_arn
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.kb.arn
      vector_index_name = local.kb_vector_index_name
      field_mapping {
        vector_field   = local.kb_vector_field
        text_field     = local.kb_text_field
        metadata_field = local.kb_metadata_field
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_kb_role,
    opensearch_index.kb,
    time_sleep.bedrock_kb_iam_propagation,
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "kb_id" {
  value       = aws_bedrockagent_knowledge_base.kb.id
  description = "Bedrock Knowledge Base ID — passed as BEDROCK_KB_ID env var to the API service."
}

output "kb_arn" {
  value       = aws_bedrockagent_knowledge_base.kb.arn
  description = "Bedrock Knowledge Base ARN — used in IAM policies for bedrock:Retrieve."
}

output "kb_raw_bucket_name" {
  value       = aws_s3_bucket.kb_raw.id
  description = "Name of the raw-documents S3 bucket."
}

output "kb_collection_endpoint" {
  value       = aws_opensearchserverless_collection.kb.collection_endpoint
  description = "AOSS collection endpoint — consumed by the opensearch provider in c1."
}
