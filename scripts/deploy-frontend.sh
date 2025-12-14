#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Deploying Frontend to S3${NC}"
echo "==========================="
echo

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }

AWS_REGION=${AWS_REGION:-us-east-1}

cd terraform

# Get S3 bucket name from Terraform state
echo -e "${YELLOW}Getting S3 bucket name from Terraform state...${NC}"
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend 2>/dev/null | grep "bucket " | grep -v arn | awk '{print $3}' | tr -d '"')

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Could not find S3 bucket. Is the infrastructure deployed?${NC}"
    exit 1
fi

echo "S3 Bucket: $S3_BUCKET"

# Upload frontend files
echo -e "${YELLOW}Uploading frontend files...${NC}"
cd ../frontend
aws s3 cp index.html s3://$S3_BUCKET/index.html --content-type "text/html"

# Get CloudFront distribution ID
echo -e "${YELLOW}Getting CloudFront distribution ID...${NC}"
cd ../terraform
DISTRIBUTION_ID=$(tofu state show aws_cloudfront_distribution.frontend 2>/dev/null | grep "^[[:space:]]*id[[:space:]]" | awk '{print $3}' | tr -d '"')

if [ -z "$DISTRIBUTION_ID" ]; then
    echo -e "${YELLOW}Could not find CloudFront distribution ID. Skipping cache invalidation.${NC}"
else
    echo "CloudFront Distribution: $DISTRIBUTION_ID"
    echo -e "${YELLOW}Creating CloudFront invalidation...${NC}"
    aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*" --region $AWS_REGION
fi

echo
echo -e "${GREEN}Frontend deployed successfully!${NC}"
echo
echo "Frontend URL:"
tofu output frontend_url
