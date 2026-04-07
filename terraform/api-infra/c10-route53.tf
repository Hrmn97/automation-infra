# ============================================================
# c10-dns.tf
# Route 53: ACM DNS Validation Records, API A Record, and
# SendGrid Inbound Parse MX Record
# ============================================================

# ------------------------------------------------------------
# Hosted Zone Data Source
# Looks up the existing Route 53 zone for the domain.
# ------------------------------------------------------------

data "aws_route53_zone" "zone" {
  name         = var.hosted_zone
  private_zone = false
}

# ------------------------------------------------------------
# ACM Certificate Validation Records
# Creates the CNAME records that ACM requires to prove
# domain ownership. for_each iterates over each SAN in the cert.
# ------------------------------------------------------------

resource "aws_route53_record" "api_record" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true # Safe to re-use if record already exists
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.zone.zone_id
}

# ------------------------------------------------------------
# API A Record — alias to the ALB
# Routes domain traffic to the ALB; health evaluation enabled
# so Route 53 won't route to an unhealthy load balancer.
# ------------------------------------------------------------

resource "aws_route53_record" "A_record_public_alb" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_alb.main.dns_name
    zone_id                = aws_alb.main.zone_id
    evaluate_target_health = true
  }
}

# ------------------------------------------------------------
# SendGrid Inbound Parse MX Record
# Routes inbound emails for the parse subdomain through
# SendGrid's mail exchange server (priority 10).
# ------------------------------------------------------------

resource "aws_route53_record" "sendgrid_parse_mx" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.sendgrid_parse_subdomain
  type    = "MX"
  ttl     = 3600
  records = ["10 mx.sendgrid.net"]
}
