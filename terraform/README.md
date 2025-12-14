# Infrastructure Setup

This directory contains OpenTofu/Terraform configuration for the Seasats take-home test infrastructure.

## Prerequisites

1. OpenTofu or Terraform installed
2. AWS CLI configured with credentials
3. SSH key pair for VPN server access

## Setup Steps

### 1. Generate SSH Key for VPN Server

```bash
ssh-keygen -t rsa -b 4096 -f vpn_server_key -N ""
```

This creates `vpn_server_key` (private) and `vpn_server_key.pub` (public) in the terraform directory.

### 2. Initialize Terraform

```bash
tofu init
# or
terraform init
```

### 3. Plan Infrastructure

```bash
tofu plan
# or
terraform plan
```

### 4. Apply Infrastructure

```bash
tofu apply
# or
terraform apply
```

## Architecture

### Network
- VPC: 10.0.0.0/16
- 2 Public Subnets (for public API, VPN server, NAT)
- 2 Private Subnets (for private/secure API)
- Internet Gateway for public access
- NAT Gateway for private subnet internet access

### Services
- **Public API**: ECS Fargate service behind ALB, accessible from internet
- **Private API**: ECS Fargate service in private subnets, only accessible via VPN
- **VPN Server**: EC2 instance running WireGuard in public subnet
- **Frontend**: S3 + CloudFront for static website
- **Database**: DynamoDB for metrics storage

### Security
- Public API: Security group allows 80/443 from internet
- Private API: Security group only allows port 5000 from VPN CIDR (10.0.100.0/24)
- VPN Server: Security group allows UDP 51820 from internet

## Outputs

After applying, important outputs include:
- `public_api_url`: URL for the public API
- `frontend_url`: URL for the frontend webpage
- `vpn_server_public_ip`: IP address of VPN server
- `ecr_repository_url`: ECR repository for pushing Docker images

## Next Steps

1. Build and push the API Docker image to ECR
2. SSH into VPN server and retrieve client.conf
3. Upload frontend files to S3
4. Test connectivity
