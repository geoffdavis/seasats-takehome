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

# Load AWS credentials if not already set
if [ -z "$AWS_ACCESS_KEY_ID" ] || ! aws sts get-caller-identity &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo -e "${YELLOW}Loading AWS credentials...${NC}"
    eval "$("$SCRIPT_DIR/setup-aws-creds.sh")"
fi

AWS_REGION=${AWS_DEFAULT_REGION:-us-west-2}

cd terraform

# Get S3 bucket name from Terraform state
echo -e "${YELLOW}Getting S3 bucket name from Terraform state...${NC}"
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend 2>/dev/null | grep "bucket " | grep -v arn | awk '{print $3}' | tr -d '"')

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Could not find S3 bucket. Is the infrastructure deployed?${NC}"
    exit 1
fi

echo "S3 Bucket: $S3_BUCKET"

# Get public API URL from Terraform output
echo -e "${YELLOW}Getting public API URL...${NC}"
PUBLIC_API_URL=$(tofu output -raw public_api_url)
echo "Public API URL: $PUBLIC_API_URL"

# Get private API IP by querying DNS through the VPN
echo -e "${YELLOW}Getting private API IP address...${NC}"
PRIVATE_API_IP=$(dig @10.0.0.2 private-api.seasats.local +short | head -1)
if [ -z "$PRIVATE_API_IP" ]; then
    echo -e "${YELLOW}Warning: Could not resolve private API IP, using DNS name${NC}"
    PRIVATE_API_URL="http://private-api.seasats.local:5000"
else
    echo "Private API IP: $PRIVATE_API_IP"
    PRIVATE_API_URL="http://$PRIVATE_API_IP:5000"
fi

# Create a temporary copy of index.html with API URLs injected
echo -e "${YELLOW}Injecting API URLs into frontend...${NC}"
cd ../frontend
cp index.html index.html.tmp
# Use @ as delimiter to avoid issues with slashes and pipes in URLs
sed -i.bak "s@let apiUrl = localStorage.getItem('apiUrl') || '';@let apiUrl = localStorage.getItem('apiUrl') || '$PUBLIC_API_URL';@" index.html.tmp
sed -i.bak "s@let privateApiUrl = localStorage.getItem('privateApiUrl') || 'http://private-api.seasats.local:5000';@let privateApiUrl = localStorage.getItem('privateApiUrl') || '$PRIVATE_API_URL';@" index.html.tmp
sed -i.bak "s@id=\"apiUrl\" placeholder=\"[^\"]*\" value=\"\">@id=\"apiUrl\" placeholder=\"http://your-alb-dns-name.region.elb.amazonaws.com\" value=\"$PUBLIC_API_URL\">@" index.html.tmp
sed -i.bak "s@id=\"privateApiUrl\" placeholder=\"[^\"]*\" value=\"http://private-api.seasats.local:5000\">@id=\"privateApiUrl\" placeholder=\"http://private-api.seasats.local:5000\" value=\"$PRIVATE_API_URL\">@" index.html.tmp

# Upload frontend files
echo -e "${YELLOW}Uploading frontend files...${NC}"
aws s3 cp index.html.tmp "s3://$S3_BUCKET/index.html" --content-type "text/html"

# Clean up temporary file
rm index.html.tmp index.html.tmp.bak

# Get CloudFront distribution ID
echo -e "${YELLOW}Getting CloudFront distribution ID...${NC}"
cd ../terraform
DISTRIBUTION_ID=$(tofu state show aws_cloudfront_distribution.frontend 2>/dev/null | grep "^[[:space:]]*id[[:space:]]" | awk '{print $3}' | tr -d '"')

if [ -z "$DISTRIBUTION_ID" ]; then
    echo -e "${YELLOW}Could not find CloudFront distribution ID. Skipping cache invalidation.${NC}"
else
    echo "CloudFront Distribution: $DISTRIBUTION_ID"
    echo -e "${YELLOW}Creating CloudFront invalidation...${NC}"
    aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths "/*" --region "$AWS_REGION"
fi

echo
echo -e "${GREEN}Frontend deployed successfully!${NC}"
echo
echo "Frontend URLs:"
echo "  CloudFront: $(tofu output -raw frontend_url 2>/dev/null || echo 'N/A')"
echo "  S3 Direct:  http://${S3_BUCKET}.s3-website-${AWS_REGION}.amazonaws.com"
echo
echo -e "${YELLOW}Note: Use the S3 Direct URL to avoid HTTPS redirect issues${NC}"
