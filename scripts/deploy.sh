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
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker is required but not installed.${NC}" >&2; exit 1; }

# Get AWS region
AWS_REGION=${AWS_REGION:-us-east-1}
echo -e "${YELLOW}Using AWS region: $AWS_REGION${NC}"

# Navigate to terraform directory
cd terraform

# Check if infrastructure is deployed
if [ ! -f terraform.tfstate ] && [ ! -f .terraform/terraform.tfstate ]; then
    echo -e "${RED}Infrastructure not found. Please run 'tofu apply' first.${NC}"
    exit 1
fi

# Get ECR repository URL
echo -e "${YELLOW}Getting ECR repository URL...${NC}"
ECR_REPO=$(tofu output -raw ecr_repository_url)
echo "ECR Repository: $ECR_REPO"

# Navigate to api directory
cd ../api

# Authenticate Docker to ECR
echo -e "${YELLOW}Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REPO

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t seasats-api .

# Tag image
echo -e "${YELLOW}Tagging image...${NC}"
docker tag seasats-api:latest $ECR_REPO:latest

# Push to ECR
echo -e "${YELLOW}Pushing image to ECR...${NC}"
docker push $ECR_REPO:latest

# Update ECS services
echo -e "${YELLOW}Updating ECS services...${NC}"
aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-public-api \
  --force-new-deployment \
  --region $AWS_REGION \
  --no-cli-pager

aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-private-api \
  --force-new-deployment \
  --region $AWS_REGION \
  --no-cli-pager

echo
echo -e "${GREEN}Deployment complete!${NC}"
echo
echo "ECS services are being updated. This may take a few minutes."
echo "You can check the status with:"
echo "  aws ecs describe-services --cluster seasats-takehome-cluster --services seasats-takehome-public-api --region $AWS_REGION"
