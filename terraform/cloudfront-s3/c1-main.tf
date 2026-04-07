# ---------------------------------------------------------------------------
# NOTE: Provider declarations inside a module is an anti-pattern in Terraform.
# Modules should receive providers from the root module via the `providers`
# argument. These are kept here to avoid a breaking change — migrate when
# possible by removing these blocks and passing providers from the root.
# ---------------------------------------------------------------------------

provider "aws" {
  region  = "eu-west-2"
  profile = "sf-deploy"
}

# ACM certificates for CloudFront must be provisioned in us-east-1
provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
  profile = "sf-deploy"
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  # Dynamically resolves the front site domain per environment
  front_domain = var.environment == "prod" ? "front.servefirst.co.uk" : "front-${var.environment}.servefirst.co.uk"

  # CORS origins for resource buckets — localhost:3000 added in stage for local dev
  additional_origin = var.environment == "stage" ? ["http://localhost:3000"] : []
  allowed_origins = concat(
    ["https://${var.domain_name}", "https://${var.front_domain_name}"],
    local.additional_origin
  )
}

# ---------------------------------------------------------------------------
# IAM policy documents (data sources — no resources created here)
# ---------------------------------------------------------------------------

# Grants CloudFront OAI read access to the main app bucket
data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    sid     = "AllowCloudFrontOAI"
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.domain_name}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

# Grants CloudFront OAI read access to each resource bucket (one policy per bucket)
data "aws_iam_policy_document" "s3_bucket_policy_resources" {
  for_each = toset(var.buckets)

  statement {
    sid     = "AllowCloudFrontOAI"
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.domain_name}.${each.key}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

# Grants CloudFront OAI read access to the front site bucket
data "aws_iam_policy_document" "s3_bucket_policy_front" {
  statement {
    sid     = "AllowCloudFrontOAI"
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.front_domain}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

# ---------------------------------------------------------------------------
# Route53 — look up the hosted zone (skipped when use_default_domain = true)
# ---------------------------------------------------------------------------

data "aws_route53_zone" "domain_name" {
  count        = var.use_default_domain ? 0 : 1
  name         = var.hosted_zone
  private_zone = false
}

# ---------------------------------------------------------------------------
# Main app S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "s3_bucket" {
  bucket = var.domain_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id

  # Remove old versions after 90 days to control storage costs
  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Clean up stalled multipart uploads after 7 days
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Resource S3 buckets (images, reports, etc.) — one set per var.buckets entry
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "s3_bucket_resources" {
  for_each = toset(var.buckets)
  bucket   = "${var.domain_name}.${each.key}"
  tags     = var.tags
}

resource "aws_s3_bucket_versioning" "s3_bucket_resources" {
  for_each = toset(var.buckets)
  bucket   = aws_s3_bucket.s3_bucket_resources[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "s3_bucket_resources" {
  for_each = toset(var.buckets)
  bucket   = aws_s3_bucket.s3_bucket_resources[each.key].id
  policy   = data.aws_iam_policy_document.s3_bucket_policy_resources[each.key].json
}

# CORS — allows the frontend app to upload/retrieve files directly
resource "aws_s3_bucket_cors_configuration" "s3_bucket_resources" {
  for_each = toset(var.buckets)
  bucket   = aws_s3_bucket.s3_bucket_resources[each.key].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST", "PUT", "DELETE"]
    allowed_origins = local.allowed_origins
    expose_headers  = []
    max_age_seconds = 0
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket_resources" {
  for_each = toset(var.buckets)
  bucket   = aws_s3_bucket.s3_bucket_resources[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_resources" {
  for_each                = toset(var.buckets)
  bucket                  = aws_s3_bucket.s3_bucket_resources[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Front site S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "s3_bucket_front" {
  bucket = local.front_domain
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "s3_bucket_front" {
  bucket = aws_s3_bucket.s3_bucket_front.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_bucket_front" {
  bucket = aws_s3_bucket.s3_bucket_front.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "s3_bucket_front" {
  bucket = aws_s3_bucket.s3_bucket_front.id
  policy = data.aws_iam_policy_document.s3_bucket_policy_front.json
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_bucket_front" {
  bucket = aws_s3_bucket.s3_bucket_front.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "s3_bucket_front" {
  bucket                  = aws_s3_bucket.s3_bucket_front.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# IAM — system user for API server access to S3 and SQS
# ---------------------------------------------------------------------------

resource "aws_iam_user" "resource_system_user" {
  name = "${var.environment}-resource-system-user"
  path = "/system/"
  tags = merge(var.tags, { Name = "${var.environment}-resource-system-user" })
}

resource "aws_iam_access_key" "resource_system_user_access" {
  user = aws_iam_user.resource_system_user.name
}

resource "aws_iam_group" "resource_system_group" {
  name = "${var.environment}-resource-system-group"
  path = "/system/"
}

resource "aws_iam_user_group_membership" "resource_system_user_membership" {
  user   = aws_iam_user.resource_system_user.name
  groups = [aws_iam_group.resource_system_group.name]
}

# Policy grants the API server: bucket listing, object CRUD on resource buckets,
# and SQS access for the screen-saver logs queues.
# TODO: Move SQS queue ARNs to variables so they aren't hardcoded here.
resource "aws_iam_policy" "s3_resource_policy" {
  name        = "${var.environment}-s3-bucket-resource-policy"
  description = "Grants the API server access to resource S3 buckets and SQS log queues"
  path        = "/system/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListResourceBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [for b in aws_s3_bucket.s3_bucket_resources : b.arn]
      },
      {
        Sid    = "CRUDResourceObjects"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = [for b in aws_s3_bucket.s3_bucket_resources : "${b.arn}/*"]
      },
      {
        Sid    = "ScreenSaverSQSAccess"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ListQueues"
        ]
        Resource = [
          "arn:aws:sqs:*:*:screen-saver-logs-queue",
          "arn:aws:sqs:*:*:screen-saver-logs-dlq"
        ]
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "s3_resource_policy_attach" {
  group      = aws_iam_group.resource_system_group.name
  policy_arn = aws_iam_policy.s3_resource_policy.arn
}

# ---------------------------------------------------------------------------
# CloudFront Origin Access Identity
# Single OAI shared across both distributions — restricts S3 access to CloudFront only
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-${var.domain_name}.s3.amazonaws.com"
}

# ---------------------------------------------------------------------------
# ACM SSL certificates — main app
# Skipped entirely when use_default_domain = true
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "fe_certificate" {
  count             = var.use_default_domain ? 0 : 1
  provider          = aws.us-east-1
  domain_name       = var.domain_name
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_record" {
  for_each = var.use_default_domain ? {} : {
    for dvo in aws_acm_certificate.fe_certificate[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain_name[0].zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  count                   = var.use_default_domain ? 0 : 1
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.fe_certificate[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_record : record.fqdn]
}

# ---------------------------------------------------------------------------
# ACM SSL certificates — front site
# Skipped entirely when use_default_domain = true
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "fe_certificate_front" {
  count             = var.use_default_domain ? 0 : 1
  provider          = aws.us-east-1
  domain_name       = local.front_domain
  validation_method = "DNS"
}

resource "aws_route53_record" "cert_record_front" {
  for_each = var.use_default_domain ? {} : {
    for dvo in aws_acm_certificate.fe_certificate_front[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.domain_name[0].zone_id
}

resource "aws_acm_certificate_validation" "cert_front" {
  count                   = var.use_default_domain ? 0 : 1
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.fe_certificate_front[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_record_front : record.fqdn]
}

# ---------------------------------------------------------------------------
# Security headers policy — applied to both CloudFront distributions
# ---------------------------------------------------------------------------

resource "aws_cloudfront_response_headers_policy" "remove_server_header" {
  name    = "${var.environment}-security-headers-policy"
  comment = "Security headers: CSP, HSTS, XSS protection, framing, and server header removal"

  custom_headers_config {
    items {
      header   = "Server"
      value    = "-"
      override = true
    }
  }

  security_headers_config {
    # HSTS — force HTTPS for 1 year across all subdomains
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      # preload intentionally omitted — enables browser preload list submission separately if desired
      override = true
    }

    # Disabled — the legacy XSS filter is considered harmful on modern browsers; CSP handles XSS
    xss_protection {
      protection = false
      override   = true
    }

    # Prevents embedding in external iframes; Chargebee iframes are scoped via frame-src in CSP
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    # Prevents MIME-type sniffing attacks
    content_type_options {
      override = true
    }

    # CSP — whitelists all external origins the React app depends on.
    # If the app breaks after a deployment, check the browser console for CSP violations
    # and add the blocked origin to the relevant directive.
    # Note: 'unsafe-inline' is required for the React production chunk and Heap Analytics
    # inline initialization — tighten with nonces in a future iteration.
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' https://maps.googleapis.com https://js.chargebee.com https://www.gstatic.com https://cdn.heapanalytics.com https://kit.fontawesome.com https://apis.google.com",
        "style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com https://fonts.googleapis.com https://cdn.jsdelivr.net",
        "font-src 'self' data: https://cdnjs.cloudflare.com https://fonts.gstatic.com https://cdn.jsdelivr.net https://ka-f.fontawesome.com",
        "img-src 'self' data: https:",
        "connect-src 'self' blob: data: https://*.servefirst.co.uk https://maps.googleapis.com https://heapanalytics.com https://*.googleapis.com https://*.firebaseio.com https://*.cloudfunctions.net https://*.chargebee.com https://ka-f.fontawesome.com https://s3.eu-west-2.amazonaws.com https://*.s3.eu-west-2.amazonaws.com https://quickchart.io",
        "frame-src https://js.chargebee.com https://*.chargebee.com https://*.firebaseapp.com",
        "worker-src 'self' blob:",
        "media-src 'self' https://servefirst.shopmetrics.com https://*.research-cloud.com",
        "object-src 'none'",
      ])
      override = true
    }
  }
}

# ---------------------------------------------------------------------------
# CloudFront distribution — main app
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on          = [aws_s3_bucket.s3_bucket]
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = var.use_default_domain ? [] : [var.domain_name]
  price_class         = var.price_class
  wait_for_deployment = false
  tags                = var.tags

  # Origin: main app S3 bucket
  origin {
    domain_name = "${var.domain_name}.s3.amazonaws.com"
    origin_id   = "${var.environment}-s3-cloudfront"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  # Origin: API server — proxied via /api/* cache behaviour
  origin {
    domain_name = "${var.environment == "stage" ? "stage" : ""}api.servefirst.co.uk"
    origin_id   = "${var.environment == "stage" ? "stage" : ""}api.servefirst.co.uk"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.1", "TLSv1.2"]
    }
  }

  # Origins: one per resource bucket (images, reports, etc.)
  dynamic "origin" {
    for_each = var.buckets
    content {
      domain_name = "${var.domain_name}.${origin.value}.s3.amazonaws.com"
      origin_id   = "${var.environment}-s3-cloudfront-${origin.value}"

      s3_origin_config {
        origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
      }
    }
  }

  # Default behaviour — serves the React SPA from the main S3 bucket
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "${var.environment}-s3-cloudfront"
    viewer_protocol_policy     = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.remove_server_header.id
    min_ttl                    = 0
    default_ttl                = 86400
    max_ttl                    = 31536000

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # Cache behaviours: /resources/{bucket}/* → corresponding resource bucket
  dynamic "ordered_cache_behavior" {
    for_each = var.buckets
    iterator = buckets
    content {
      path_pattern               = "/resources/${buckets.value}/*"
      allowed_methods            = ["GET", "HEAD"]
      cached_methods             = ["GET", "HEAD"]
      target_origin_id           = "${var.environment}-s3-cloudfront-${buckets.value}"
      viewer_protocol_policy     = "redirect-to-https"
      response_headers_policy_id = aws_cloudfront_response_headers_policy.remove_server_header.id
      min_ttl                    = 0
      default_ttl                = 86400
      max_ttl                    = 31536000

      forwarded_values {
        query_string = false
        cookies { forward = "none" }
      }
    }
  }

  # Cache behaviour: /api/* → API server (all methods allowed, not cached)
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "${var.environment == "stage" ? "stage" : ""}api.servefirst.co.uk"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.remove_server_header.id

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  # Single viewer_certificate block — switches between default CloudFront cert and ACM cert
  viewer_certificate {
    cloudfront_default_certificate = var.use_default_domain ? true : null
    acm_certificate_arn            = var.use_default_domain ? null : aws_acm_certificate_validation.cert[0].certificate_arn
    ssl_support_method             = var.use_default_domain ? null : "sni-only"
    minimum_protocol_version       = var.use_default_domain ? null : "TLSv1.2_2021"
  }

  # SPA fallback — returns index.html on 403 so React Router handles the path client-side
  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = "/"
  }
}

# ---------------------------------------------------------------------------
# Route53 A record — main app (skipped when use_default_domain = true)
# ---------------------------------------------------------------------------

resource "aws_route53_record" "route53_record" {
  count      = var.use_default_domain ? 0 : 1
  depends_on = [aws_cloudfront_distribution.s3_distribution]
  zone_id    = data.aws_route53_zone.domain_name[0].zone_id
  name       = var.domain_name
  type       = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# CloudFront distribution — front site
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "s3_distribution_front" {
  depends_on          = [aws_s3_bucket.s3_bucket_front]
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = [local.front_domain]
  price_class         = var.price_class
  wait_for_deployment = false
  tags                = var.tags

  origin {
    domain_name = "${local.front_domain}.s3.amazonaws.com"
    origin_id   = "${var.environment}-front-s3-cloudfront"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "${var.environment}-front-s3-cloudfront"
    viewer_protocol_policy     = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.remove_server_header.id
    min_ttl                    = 0
    default_ttl                = 86400
    max_ttl                    = 31536000

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.use_default_domain ? true : null
    acm_certificate_arn            = var.use_default_domain ? null : aws_acm_certificate_validation.cert_front[0].certificate_arn
    ssl_support_method             = var.use_default_domain ? null : "sni-only"
    minimum_protocol_version       = var.use_default_domain ? null : "TLSv1.2_2021"
  }

  # SPA fallback — returns index.html on 403 so React Router handles the path client-side
  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = "/"
  }
}

# ---------------------------------------------------------------------------
# Route53 A record — front site
# ---------------------------------------------------------------------------

resource "aws_route53_record" "route53_record_front" {
  depends_on = [aws_cloudfront_distribution.s3_distribution_front]
  zone_id    = data.aws_route53_zone.domain_name[0].zone_id
  name       = local.front_domain
  type       = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution_front.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution_front.hosted_zone_id
    evaluate_target_health = false
  }
}
