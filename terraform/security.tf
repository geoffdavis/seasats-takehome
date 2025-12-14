# Security Group for Public API (ALB)
resource "aws_security_group" "public_alb" {
  name        = "${local.project_name}-public-alb-sg"
  description = "Security group for public API load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-alb-sg"
  })
}

# Security Group for Public API ECS Tasks
resource "aws_security_group" "public_api" {
  name        = "${local.project_name}-public-api-sg"
  description = "Security group for public API ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.public_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-api-sg"
  })
}

# Security Group for Private API (accessible only from VPN)
resource "aws_security_group" "private_api" {
  name        = "${local.project_name}-private-api-sg"
  description = "Security group for private API accessible via VPN"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from VPN clients"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-api-sg"
  })
}

# Security Group for VPN Server
resource "aws_security_group" "vpn_server" {
  name        = "${local.project_name}-vpn-server-sg"
  description = "Security group for WireGuard VPN server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "WireGuard VPN"
    from_port   = var.vpn_server_port
    to_port     = var.vpn_server_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH for management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpn-server-sg"
  })
}
