# Seasats Take-Home Test - Infrastructure & API

A proof-of-concept implementation featuring a public REST API, VPN-secured endpoint, and metrics visualization dashboard deployed on AWS.

## Tech Stack

### Infrastructure
- **IaC**: OpenTofu/Terraform
- **Cloud Provider**: AWS
- **Compute**: ECS Fargate (containerized API)
- **Load Balancer**: Application Load Balancer (ALB)
- **Storage**: DynamoDB (serverless NoSQL)
- **VPN**: WireGuard on EC2
- **CDN/Frontend**: S3 + CloudFront
- **Container Registry**: Amazon ECR

### Application
- **API Framework**: Python Flask
- **Runtime**: Python 3.11
- **Container**: Docker
- **Frontend**: Vanilla HTML/JavaScript with Chart.js

### Network Architecture
- VPC with public/private subnets across 2 AZs
- Public API in public subnets behind ALB
- Private API in private subnets (VPN-only access)
- WireGuard VPN server for secure access
- NAT Gateway for private subnet internet access

## Project Structure

```
.
├── api/
│   ├── app.py              # Flask application
│   ├── requirements.txt    # Python dependencies
│   ├── Dockerfile          # Container definition
│   └── .dockerignore
├── frontend/
│   └── index.html          # Metrics dashboard
├── terraform/
│   ├── main.tf             # Terraform configuration
│   ├── vpc.tf              # Network resources
│   ├── ecs.tf              # ECS cluster and services
│   ├── security.tf         # Security groups
│   ├── storage.tf          # DynamoDB table
│   ├── iam.tf              # IAM roles and policies
│   ├── vpn.tf              # VPN server
│   ├── frontend.tf         # S3 and CloudFront
│   ├── outputs.tf          # Output values
│   ├── variables.tf        # Input variables
│   └── user_data/
│       └── wireguard.sh    # VPN server initialization
└── README.md
```

## Setup Instructions

### Prerequisites

1. **AWS Account** with appropriate credentials configured
2. **AWS CLI** installed and configured
3. **OpenTofu** or **Terraform** (>= 1.6)
4. **Docker** or **Podman** for building container images
5. **WireGuard client** for VPN connectivity

### Configuring AWS Region

**Important:** The deployment scripts automatically read the AWS region from your Terraform configuration. You do NOT need to set the `AWS_REGION` environment variable.

To deploy to a different region:

1. Edit `terraform/terraform.tfvars` and change the `aws_region` value:

   ```hcl
   aws_region = "us-west-2"  # Change from default us-east-1
   ```

2. The deployment scripts will automatically detect and use this region from Terraform outputs.

If you prefer to override this behavior, you can still set the `AWS_REGION` environment variable:

```bash
export AWS_REGION=us-west-2
```

### Step 1: Deploy Infrastructure

```bash
# Navigate to terraform directory
cd terraform

# Generate SSH key for VPN server
ssh-keygen -t rsa -b 4096 -f vpn_server_key -N ""

# Copy and customize variables (IMPORTANT: Set your desired AWS region here)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and change aws_region if needed (default: us-east-1)
# Example: aws_region = "us-west-2"

# Initialize Terraform
tofu init

# Review the planned infrastructure
tofu plan

# Deploy infrastructure
tofu apply

# Save the outputs
tofu output > ../outputs.txt
```

**Important outputs:**
- `public_api_url`: URL for accessing the public API
- `frontend_url`: CloudFront URL for the dashboard
- `vpn_server_public_ip`: VPN server IP address
- `ecr_repository_url`: ECR repository for Docker images

### Step 2: Build and Deploy API Container

**Note:** The deployment script automatically detects and uses either Podman or Docker. You can also run these commands manually:

```bash
# Navigate to api directory
cd ../api

# Get ECR repository URL from Terraform outputs
ECR_REPO=$(cd ../terraform && tofu output -raw ecr_repository_url)
AWS_REGION="us-east-1"  # or your configured region

# Authenticate to ECR (use 'podman' or 'docker' based on what you have installed)
aws ecr get-login-password --region $AWS_REGION | podman login --username AWS --password-stdin $ECR_REPO

# Build the container image
podman build -t seasats-api .

# Tag the image
podman tag seasats-api:latest $ECR_REPO:latest

# Push to ECR
podman push $ECR_REPO:latest
```

**Or simply use the deployment script** which handles container runtime detection automatically:

```bash
./scripts/deploy.sh
```

### Step 3: Update ECS Services

After pushing the container, ECS Fargate will automatically pull and deploy the new image. You may need to force a new deployment:

```bash
aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-public-api \
  --force-new-deployment \
  --region us-east-1

aws ecs update-service \
  --cluster seasats-takehome-cluster \
  --service seasats-takehome-private-api \
  --force-new-deployment \
  --region us-east-1
```

### Step 4: Retrieve VPN Configuration

```bash
# Get VPN server IP from outputs
VPN_IP=$(cd terraform && tofu output -raw vpn_server_public_ip)

# SSH into VPN server (wait a few minutes for user_data script to complete)
ssh -i terraform/vpn_server_key ubuntu@$VPN_IP

# On the VPN server, retrieve the client configuration
sudo cat /root/client.conf
```

Copy the `client.conf` contents to your local machine and save it as `client.conf`.

### Step 5: Connect to VPN

```bash
# Install WireGuard (if not already installed)
# macOS: brew install wireguard-tools
# Ubuntu: sudo apt install wireguard

# Connect to VPN
sudo wg-quick up ./client.conf

# Verify connection
sudo wg show

# Test private API access
curl http://private-api.seasats.local:5000/secure-status
```

### Step 6: Deploy Frontend

```bash
# Get S3 bucket name
S3_BUCKET=$(cd terraform && tofu output -json | jq -r '.frontend_url.value' | sed 's|https://||' | cut -d'/' -f1)

# Note: The S3 bucket name is in the Terraform state
# You can find it with:
cd terraform
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend | grep bucket | grep -v arn | awk '{print $3}' | tr -d '"')

# Upload frontend files
cd ../frontend
aws s3 cp index.html s3://$S3_BUCKET/index.html --content-type "text/html"

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(cd ../terraform && tofu state show aws_cloudfront_distribution.frontend | grep "^[[:space:]]*id[[:space:]]" | awk '{print $3}' | tr -d '"')
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
```

### Step 7: Configure Dashboard

1. Open the CloudFront URL (from `frontend_url` output) in your browser
2. Enter the public API URL (from `public_api_url` output)
3. The private API URL should already be set to `http://private-api.seasats.local:5000`
4. Click "Save & Refresh Data"

## Testing

### Test Public Endpoint

```bash
# Get the public API URL
PUBLIC_API=$(cd terraform && tofu output -raw public_api_url)

# Test /status endpoint (should work without VPN)
curl $PUBLIC_API/status

# Expected response:
# {"count": 1, "random": 7}

# Hit it a few more times to increment the counter
curl $PUBLIC_API/status
curl $PUBLIC_API/status
```

### Test Secure Endpoint (VPN Required)

```bash
# Connect to VPN first
sudo wg-quick up ./client.conf

# Test /secure-status endpoint (only works via VPN)
curl http://private-api.seasats.local:5000/secure-status

# Expected response:
# {"count": 1, "random": 3}

# Disconnect from VPN
sudo wg-quick down ./client.conf

# This should now fail
curl http://private-api.seasats.local:5000/secure-status
```

### Test Metrics Dashboard

1. Open the frontend URL in your browser
2. Configure the API URL
3. You should see charts showing hit counts over time
4. Hit the endpoints a few times and refresh to see the charts update

## Architecture Decisions

### DynamoDB Schema
- **Simplified approach**: Single table storing time-series records
- **Schema**: `endpoint` (PK), `timestamp` (SK), `count` (attribute)
- Each API hit creates a new record with incremented count
- Latest record provides current counter value
- Time-range queries enable visualization

### API Deployment Strategy
- **Two separate ECS services** from same container image:
  - Public API: In public subnets, behind ALB, accessible from internet
  - Private API: In private subnets, only accessible via VPN CIDR
- **Environment variable** `API_MODE` differentiates behavior if needed
- **Service discovery** provides DNS name for private API

### Security Model
- Infrastructure-enforced security via security groups
- Public API: Security group allows traffic from ALB only
- Private API: Security group only allows traffic from VPN CIDR (10.0.100.0/24)
- No application-level IP filtering needed

## Assumptions Made

1. **Single region deployment**: Deployed to us-east-1 for simplicity
2. **No custom domain**: Using ALB DNS and CloudFront domain
3. **No HTTPS on private API**: VPN provides encryption, HTTP within VPC
4. **Single VPN client**: Only one client certificate generated
5. **No authentication/authorization**: Public endpoints are truly public
6. **Short data retention**: Storing last 24 hours of metrics
7. **Minimal redundancy**: Single NAT Gateway (not HA for cost)
8. **No monitoring/alerting**: CloudWatch logs available but no alarms configured

## What I Would Improve With More Time

### Infrastructure
1. **High Availability**:
   - Deploy NAT Gateways in both AZs
   - Add health checks and auto-scaling for ECS services
   - Multi-region deployment with Route53 failover

2. **Security**:
   - Add WAF rules to ALB
   - Implement API rate limiting
   - Add authentication (Cognito or API keys)
   - Secrets management via AWS Secrets Manager
   - Enable VPC Flow Logs

3. **Monitoring & Observability**:
   - CloudWatch dashboards and alarms
   - X-Ray tracing for API requests
   - Log aggregation and analysis
   - Custom metrics for business KPIs

4. **Cost Optimization**:
   - Use Spot instances for VPN server
   - Implement DynamoDB auto-scaling or on-demand capacity
   - S3 lifecycle policies for old logs

### Application
1. **Race Condition Fix**:
   - Use DynamoDB atomic counters with UpdateItem
   - Separate counter table from time-series table
   - Use DynamoDB Streams to populate time-series asynchronously

2. **Performance**:
   - Add caching layer (ElastiCache/Redis)
   - Implement connection pooling for DynamoDB
   - Use DynamoDB batch operations for metrics queries

3. **Features**:
   - Add pagination for metrics endpoint
   - Support custom time ranges for visualization
   - Add more granular metrics (response times, error rates)
   - WebSocket support for real-time updates

### Operations
1. **CI/CD Pipeline**:
   - GitHub Actions or GitLab CI for automated builds
   - Automated testing before deployment
   - Blue/green deployments
   - Automated rollback on failures

2. **Infrastructure as Code**:
   - Remote state backend with S3 + DynamoDB locking
   - Modularize Terraform code for reusability
   - Add Terraform workspaces for multiple environments
   - Implement policy-as-code with Sentinel or OPA

3. **Documentation**:
   - API documentation with OpenAPI/Swagger
   - Architecture diagrams
   - Runbooks for common operations
   - Disaster recovery procedures

4. **Testing**:
   - Unit tests for API endpoints
   - Integration tests for DynamoDB interactions
   - Load testing to validate scalability
   - Security scanning (SAST/DAST)

5. **VPN Improvements**:
   - Support multiple VPN clients
   - Automated client certificate generation
   - Certificate revocation mechanism
   - VPN connection monitoring and auto-recovery

## Cleanup

To destroy all resources and avoid AWS charges:

```bash
# Delete S3 bucket contents first (Terraform can't delete non-empty buckets)
cd terraform
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend | grep bucket | grep -v arn | awk '{print $3}' | tr -d '"')
aws s3 rm s3://$S3_BUCKET --recursive

# Destroy all infrastructure
tofu destroy

# Confirm when prompted
```

## License

This is a proof-of-concept for interview purposes.
