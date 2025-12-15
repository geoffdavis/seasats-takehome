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
# Get the ALB DNS name directly from Terraform state
ALB_DNS=$(tofu state show aws_lb.public 2>/dev/null | grep "dns_name " | head -1 | awk '{print $3}' | tr -d '"')
if [ -n "$ALB_DNS" ]; then
    # Use HTTP for the ALB (HTTPS requires certificate validation)
    PUBLIC_API_URL="http://$ALB_DNS"
    echo "Using ALB URL: $PUBLIC_API_URL"
else
    echo -e "${RED}Could not find ALB DNS name${NC}"
    exit 1
fi

# Check if custom domain is available and working
CUSTOM_DOMAIN=$(tofu output -raw public_api_custom_domain 2>/dev/null || echo "")
if [ -n "$CUSTOM_DOMAIN" ] && curl -sf "$CUSTOM_DOMAIN/health" &>/dev/null; then
    PUBLIC_API_URL="$CUSTOM_DOMAIN"
    echo "Custom domain is available, using: $PUBLIC_API_URL"
fi

# Use DNS name for private API (requires VPN with DNS configuration)
echo -e "${YELLOW}Using private API DNS name...${NC}"
PRIVATE_API_URL="http://private-api.seasats.local:5000"
echo "Private API URL: $PRIVATE_API_URL"

# Get the custom domain URL for redirect (prefer custom domain over CloudFront)
REDIRECT_URL=$(tofu output -raw frontend_custom_domain 2>/dev/null || echo "")
if [ -z "$REDIRECT_URL" ]; then
    # Fallback to CloudFront URL if custom domain not available
    REDIRECT_URL=$(tofu output -raw frontend_url 2>/dev/null || echo "")
fi

# Create a temporary copy of index.html with API URLs injected
echo -e "${YELLOW}Injecting API URLs into frontend...${NC}"
cd ../frontend
cp index.html index.html.tmp

# Add redirect to HTTPS custom domain if accessed via non-custom domain
if [ -n "$REDIRECT_URL" ]; then
    echo "Will redirect non-custom domains to: $REDIRECT_URL"
    # Extract custom domain hostname from REDIRECT_URL
    CUSTOM_DOMAIN_HOST=$(echo "$REDIRECT_URL" | sed 's|https://||' | sed 's|http://||' | cut -d'/' -f1)
    # Add a script at the top of the body to redirect to custom domain
    sed -i.bak "s@<body>@<body>\n<script>\n// Redirect S3 and CloudFront domains to custom domain\nif (window.location.hostname !== '$CUSTOM_DOMAIN_HOST') {\n    window.location.href = '$REDIRECT_URL';\n}\n</script>@" index.html.tmp
fi

# Use @ as delimiter to avoid issues with slashes and pipes in URLs
# Replace localStorage.getItem with hardcoded values and force them to be used
sed -i.bak "s@let apiUrl = localStorage.getItem('apiUrl') || '';@let apiUrl = '$PUBLIC_API_URL'; // Hardcoded by deployment script@" index.html.tmp
sed -i.bak "s@let privateApiUrl = localStorage.getItem('privateApiUrl') || 'http://private-api.seasats.local:5000';@let privateApiUrl = '$PRIVATE_API_URL'; // Hardcoded by deployment script@" index.html.tmp
# Hide the entire configuration section
sed -i.bak 's@<div class="config-section">@<div class="config-section" style="display: none;">@' index.html.tmp
# Comment out the saveConfig function to prevent localStorage writes
sed -i.bak "s@localStorage.setItem('apiUrl', apiUrl);@// localStorage.setItem('apiUrl', apiUrl); // Disabled - using deployment-time values@" index.html.tmp
sed -i.bak "s@localStorage.setItem('privateApiUrl', privateApiUrl);@// localStorage.setItem('privateApiUrl', privateApiUrl); // Disabled - using deployment-time values@" index.html.tmp

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
