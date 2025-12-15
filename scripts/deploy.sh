#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Seasats Take-Home Test - Deployment Script${NC}"
echo "=============================================="
echo

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }

# Load AWS credentials if not already set
if [ -z "$AWS_ACCESS_KEY_ID" ] || ! aws sts get-caller-identity &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo -e "${YELLOW}Loading AWS credentials...${NC}"
    eval "$("$SCRIPT_DIR/setup-aws-creds.sh")"
fi

# Detect container runtime (prefer podman, fallback to docker)
if command -v podman >/dev/null 2>&1; then
    CONTAINER_RUNTIME="podman"
    echo -e "${GREEN}Using Podman as container runtime${NC}"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_RUNTIME="docker"
    echo -e "${GREEN}Using Docker as container runtime${NC}"
else
    echo -e "${RED}Error: Neither Podman nor Docker is installed.${NC}" >&2
    echo -e "${RED}Please install either Podman or Docker to continue.${NC}" >&2
    echo -e "${YELLOW}  - Install Podman: https://podman.io/getting-started/installation${NC}" >&2
    echo -e "${YELLOW}  - Install Docker: https://docs.docker.com/get-docker/${NC}" >&2
    exit 1
fi

# Navigate to terraform directory
cd terraform

# Check if infrastructure is deployed
if [ ! -f terraform.tfstate ] && [ ! -f .terraform/terraform.tfstate ]; then
    echo -e "${RED}Infrastructure not found. Please run 'tofu apply' first.${NC}"
    exit 1
fi

# Get AWS region from Terraform output (falls back to AWS_REGION env var or us-east-1)
if AWS_REGION_FROM_TF=$(tofu output -raw aws_region 2>/dev/null); then
    AWS_REGION="$AWS_REGION_FROM_TF"
    echo -e "${GREEN}Using AWS region from Terraform: $AWS_REGION${NC}"
else
    AWS_REGION=${AWS_REGION:-us-east-1}
    echo -e "${YELLOW}Using AWS region from environment: $AWS_REGION${NC}"
fi

# Get ECR repository URL
echo -e "${YELLOW}Getting ECR repository URL...${NC}"
ECR_REPO=$(tofu output -raw ecr_repository_url)
echo "ECR Repository: $ECR_REPO"

# Navigate to api directory
cd ../api

# Authenticate container runtime to ECR
echo -e "${YELLOW}Authenticating $CONTAINER_RUNTIME to ECR...${NC}"
aws ecr get-login-password --region "$AWS_REGION" | "$CONTAINER_RUNTIME" login --username AWS --password-stdin "$ECR_REPO"

# Build container image
echo -e "${YELLOW}Building container image for linux/amd64...${NC}"
"$CONTAINER_RUNTIME" build --platform linux/amd64 -t seasats-api .

# Tag image
echo -e "${YELLOW}Tagging image...${NC}"
"$CONTAINER_RUNTIME" tag seasats-api:latest "$ECR_REPO:latest"

# Push to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
"$CONTAINER_RUNTIME" push "$ECR_REPO:latest"

# Update ECS services
echo -e "${YELLOW}Updating ECS services...${NC}"
aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-public-api \
  --force-new-deployment \
  --region "$AWS_REGION" \
  --no-cli-pager

aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-private-api \
  --force-new-deployment \
  --region "$AWS_REGION" \
  --no-cli-pager

echo
echo -e "${GREEN}Deployment complete!${NC}"
echo
echo "ECS services are being updated. This may take a few minutes."
echo "You can check the status with:"
echo "  aws ecs describe-services --cluster seasats-takehome-cluster --services seasats-takehome-public-api --region $AWS_REGION"
