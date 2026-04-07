# =============================================================================
# s3-cloudfront-app module — core infrastructure
#
# This module requires TWO AWS provider configurations passed from the caller:
#   aws           — primary region (eu-west-2) for S3, Route53, etc.
#   aws.us-east-1 — us-east-1 for ACM certificates (CloudFront requirement)
#
# Provisions:
#   S3 bucket (private, OAI-only) → versioning + SSE + lifecycle rules
#   CloudFront OAI → bucket policy
#   ACM certificate (us-east-1) + DNS validation
#   CloudFront distribution (HTTPS-only, SPA error routing, optional sec headers)
#   Route53 A alias record → CloudFront
# =============================================================================

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us-east-1]
    }
  }
}

locals {
  display_name = var.app_display_name != "" ? var.app_display_name : title(replace(var.app_name, "-", " "))

  # Domain: prod → <app>.servefirst.co.uk, others → <app>-<env>.servefirst.co.uk
  domain_name = var.domain_name != "" ? var.domain_name : (
    var.environment == "prod"
    ? "${var.app_name}.${var.hosted_zone}"
    : "${var.app_name}-${var.environment}.${var.hosted_zone}"
  )

  # S3 bucket name matches domain (convention shared with cloudfront-s3 stack)
  bucket_name = local.domain_name

  tags = merge(var.common_tags, {
    Name        = "${var.environment}-${var.app_name}"
    Service     = var.app_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# -----------------------------------------------------------------------------
# Route53 — hosted zone lookup
# -----------------------------------------------------------------------------

data "aws_route53_zone" "zone" {
  name         = var.hosted_zone
  private_zone = false
}

# -----------------------------------------------------------------------------
# S3 Bucket — private, served only via CloudFront OAI
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "app" {
  bucket = local.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "app" {
  bucket = aws_s3_bucket.app.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_multipart_upload_days
    }
  }
}

# -----------------------------------------------------------------------------
# CloudFront Origin Access Identity
# -----------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_identity" "app" {
  comment = "access-identity-${local.bucket_name}.s3.amazonaws.com"
}

# -----------------------------------------------------------------------------
# S3 Bucket Policy — OAI read-only access
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "s3_policy" {
  statement {
    sid     = "CloudFrontOAIRead"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.app.iam_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "app" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.s3_policy.json

  depends_on = [aws_s3_bucket_public_access_block.app]
}

# -----------------------------------------------------------------------------
# ACM Certificate — MUST be in us-east-1 for CloudFront
# -----------------------------------------------------------------------------

resource "aws_acm_certificate" "app" {
  provider          = aws.us-east-1
  domain_name       = local.domain_name
  validation_method = "DNS"
  tags              = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
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
  zone_id         = data.aws_route53_zone.zone.zone_id
}

resource "aws_acm_certificate_validation" "app" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# -----------------------------------------------------------------------------
# CloudFront Response Headers Policy — security headers (optional)
# -----------------------------------------------------------------------------

resource "aws_cloudfront_response_headers_policy" "security" {
  count   = var.enable_security_headers ? 1 : 0
  name    = "${var.environment}-${var.app_name}-security-headers"
  comment = "Security headers for ${local.display_name} (${var.environment})"

  custom_headers_config {
    items {
      header   = "Server"
      value    = "-"
      override = true
    }
  }

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }

    # XSS auditor disabled — modern browsers ignore it and it causes false positives
    xss_protection {
      protection = false
      override   = true
    }

    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    content_type_options {
      override = true
    }

    # CSP only added when the caller provides one — each SPA has different needs
    dynamic "content_security_policy" {
      for_each = var.custom_csp != "" ? [var.custom_csp] : []
      content {
        content_security_policy = content_security_policy.value
        override                = true
      }
    }
  }
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# -----------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "app" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object
  aliases             = [local.domain_name]
  price_class         = var.price_class
  wait_for_deployment = false
  tags                = local.tags

  origin {
    domain_name = "${local.bucket_name}.s3.amazonaws.com"
    origin_id   = "${var.environment}-${var.app_name}-s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.app.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "${var.environment}-${var.app_name}-s3"
    viewer_protocol_policy   = "redirect-to-https"
    min_ttl                  = var.min_ttl
    default_ttl              = var.default_ttl
    max_ttl                  = var.max_ttl
    response_headers_policy_id = var.enable_security_headers ? aws_cloudfront_response_headers_policy.security[0].id : null

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # SPA routing — S3 returns 403 for missing paths when using OAI;
  # serve index.html so the React router handles the route client-side.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = var.spa_error_page
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    error_caching_min_ttl = 0
    response_page_path    = var.spa_error_page
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.app.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_s3_bucket.app]
}

# -----------------------------------------------------------------------------
# Route53 — A alias record → CloudFront
# -----------------------------------------------------------------------------

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.app.domain_name
    zone_id                = aws_cloudfront_distribution.app.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_cloudfront_distribution.app]
}
