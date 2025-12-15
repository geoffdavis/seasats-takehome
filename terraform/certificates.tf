# Data source for Cloudflare zone
data "cloudflare_zone" "main" {
  name = var.domain_name
}

# ACM Certificate for ALB (us-west-2)
resource "aws_acm_certificate" "alb" {
  domain_name       = "seasats-api.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Cloudflare DNS records for ALB certificate validation
resource "cloudflare_record" "alb_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.alb.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zone.main.id
  name    = trimsuffix(each.value.name, ".${var.domain_name}.")
  type    = each.value.type
  content = trimsuffix(each.value.record, ".")
  ttl     = 60
}

# Wait for ACM certificate validation
resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for record in cloudflare_record.alb_cert_validation : record.hostname]
}

# ACM Certificate for CloudFront (must be in us-east-1)
resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us_east_1
  domain_name       = "seasats.${var.domain_name}"
  validation_method = "DNS"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cloudfront-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Cloudflare DNS records for CloudFront certificate validation
resource "cloudflare_record" "cloudfront_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zone.main.id
  name    = trimsuffix(each.value.name, ".${var.domain_name}.")
  type    = each.value.type
  content = trimsuffix(each.value.record, ".")
  ttl     = 60
}

# Wait for CloudFront certificate validation
resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in cloudflare_record.cloudfront_cert_validation : record.hostname]
}

# Cloudflare DNS record for ALB
resource "cloudflare_record" "alb" {
  zone_id = data.cloudflare_zone.main.id
  name    = "seasats-api"
  type    = "CNAME"
  content = aws_lb.public.dns_name
  ttl     = 300
  proxied = false # Must be false for ACM validation
}

# Cloudflare DNS record for CloudFront
resource "cloudflare_record" "cloudfront" {
  zone_id = data.cloudflare_zone.main.id
  name    = "seasats"
  type    = "CNAME"
  content = aws_cloudfront_distribution.frontend.domain_name
  ttl     = 300
  proxied = false # Must be false for CloudFront
}

# HTTPS Listener for ALB
resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.alb.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_api.arn
  }

  tags = local.common_tags
}
