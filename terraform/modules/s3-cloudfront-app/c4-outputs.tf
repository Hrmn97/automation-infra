# =============================================================================
# s3-cloudfront-app module — outputs
# =============================================================================

output "s3_bucket_id" {
  value       = aws_s3_bucket.app.id
  description = "S3 bucket name — push static assets here in CI."
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.app.arn
  description = "S3 bucket ARN."
}

output "s3_bucket_domain_name" {
  value       = aws_s3_bucket.app.bucket_domain_name
  description = "S3 bucket domain name."
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.app.id
  description = "CloudFront distribution ID — used by CI for cache invalidation after deploy."
}

output "cloudfront_distribution_arn" {
  value       = aws_cloudfront_distribution.app.arn
  description = "CloudFront distribution ARN."
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.app.domain_name
  description = "CloudFront distribution domain name (*.cloudfront.net)."
}

output "domain_name" {
  value       = local.domain_name
  description = "The resolved domain name for the app (e.g. admin-stage.servefirst.co.uk)."
}

output "app_url" {
  value       = "https://${local.domain_name}"
  description = "Full HTTPS URL for the app."
}

output "acm_certificate_arn" {
  value       = aws_acm_certificate.app.arn
  description = "ACM certificate ARN (us-east-1)."
}
