output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.s3_distribution.domain_name
}
output "front_cloudfront_dist_id" {
  value = aws_cloudfront_distribution.s3_distribution_front.id
}

output "cloudfront_dist_id" {
  value = aws_cloudfront_distribution.s3_distribution.id
}

output "s3_domain_name" {
  value = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
}

output "website_address" {
  value = var.domain_name
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.s3_bucket.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.s3_bucket.id
}

output "s3_resource_buckets" {

  #value = values(aws_s3_bucket.s3_bucket_resources)[*].bucket_domain_name
  value = {
    for k, v in aws_s3_bucket.s3_bucket_resources :
    k => v.bucket_domain_name
  }
}
output "iam_resource_user_key" {
  value = aws_iam_access_key.resource_system_user_access.id
}
output "iam_resource_user_secret" {
  value = aws_iam_access_key.resource_system_user_access.secret
}