# ACM Certificate for ALB (self-signed)
resource "aws_acm_certificate" "alb" {
  private_key      = file("${path.module}/certs/alb-private-key.pem")
  certificate_body = file("${path.module}/certs/alb-certificate.pem")

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-cert"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Listener for ALB
resource "aws_lb_listener" "public_https" {
  load_balancer_arn = aws_lb.public.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.alb.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_api.arn
  }

  tags = local.common_tags
}
