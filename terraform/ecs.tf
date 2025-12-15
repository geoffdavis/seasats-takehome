# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project_name}-cluster"

  tags = local.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${local.project_name}-api"
  retention_in_days = 7

  tags = local.common_tags
}

# ECR Repository for API container
resource "aws_ecr_repository" "api" {
  name                 = "${local.project_name}-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  tags = local.common_tags
}

# Public ALB
resource "aws_lb" "public" {
  name               = "${local.project_name}-public-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.public_alb.id]
  subnets            = aws_subnet.public[*].id

  tags = local.common_tags
}

# Public ALB Target Group
resource "aws_lb_target_group" "public_api" {
  name        = "${local.project_name}-public-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

# Public ALB Listener - HTTP
resource "aws_lb_listener" "public" {
  load_balancer_arn = aws_lb.public.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_api.arn
  }
}

# HTTP to HTTPS redirect rule (only for custom domain)
resource "aws_lb_listener_rule" "redirect_http_to_https" {
  listener_arn = aws_lb_listener.public.arn
  priority     = 1

  condition {
    host_header {
      values = ["seasats-api.${var.domain_name}"]
    }
  }

  action {
    type = "redirect"

    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }

  depends_on = [aws_acm_certificate_validation.alb]
}

# ECS Task Definition for Public API
resource "aws_ecs_task_definition" "public_api" {
  family                   = "${local.project_name}-public-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DYNAMODB_TABLE"
          value = aws_dynamodb_table.api_metrics.name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "API_MODE"
          value = "public"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "public-api"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ECS Service for Public API
resource "aws_ecs_service" "public_api" {
  name            = "${local.project_name}-public-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.public_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.public_api.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.public_api.arn
    container_name   = "api"
    container_port   = 5000
  }

  depends_on = [aws_lb_listener.public]

  tags = local.common_tags
}

# ECS Task Definition for Private API (VPN-only)
resource "aws_ecs_task_definition" "private_api" {
  family                   = "${local.project_name}-private-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "api"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "DYNAMODB_TABLE"
          value = aws_dynamodb_table.api_metrics.name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "API_MODE"
          value = "private"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "private-api"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ECS Service for Private API
resource "aws_ecs_service" "private_api" {
  name            = "${local.project_name}-private-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.private_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.private_api.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.private_api.arn
  }

  tags = local.common_tags
}

# Service Discovery for Private API
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "seasats.local"
  description = "Private DNS namespace for service discovery"
  vpc         = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_service_discovery_service" "private_api" {
  name = "private-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = local.common_tags
}
