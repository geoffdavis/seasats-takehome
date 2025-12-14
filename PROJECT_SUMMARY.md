# Seasats Take-Home Test - Project Summary

## Overview

This project implements a proof-of-concept infrastructure featuring:
- Public REST API with hit counter
- VPN-secured API endpoint
- Real-time metrics visualization dashboard
- Complete infrastructure as code with OpenTofu

## Project Structure

```
seasats-takehome/
├── api/                      # Flask API application
│   ├── app.py                # Main application with endpoint logic
│   ├── Dockerfile            # Container definition
│   ├── requirements.txt      # Python dependencies
│   └── .dockerignore
│
├── terraform/                # Infrastructure as Code
│   ├── main.tf               # Provider and common config
│   ├── variables.tf          # Input variables
│   ├── outputs.tf            # Output values
│   ├── vpc.tf                # Network infrastructure
│   ├── security.tf           # Security groups
│   ├── ecs.tf                # ECS cluster and services
│   ├── storage.tf            # DynamoDB table
│   ├── iam.tf                # IAM roles and policies
│   ├── vpn.tf                # VPN server EC2 instance
│   ├── frontend.tf           # S3 and CloudFront
│   └── user_data/
│       └── wireguard.sh      # VPN server initialization script
│
├── frontend/                 # Metrics Dashboard
│   └── index.html            # Static webpage with Chart.js
│
├── scripts/                  # Deployment automation
│   ├── deploy.sh             # Build and deploy API container
│   ├── deploy-frontend.sh   # Upload frontend to S3
│   ├── get-vpn-config.sh     # Retrieve VPN client config
│   └── test-endpoints.sh     # Test all API endpoints
│
├── requirements/             # Original requirements
│   └── Seasats_Network_Infra_Take_Home_Test.pdf
│
├── README.md                 # Comprehensive documentation
├── QUICKSTART.md             # Quick deployment guide
├── ARCHITECTURE.md           # Deep dive into design decisions
└── PROJECT_SUMMARY.md        # This file
```

## Key Features Implemented

### Task 1: Public REST API ✅
- **Endpoint**: `/status`
- **Returns**: `{"count": <incrementing_int>, "random": <1-10>}`
- **Accessible**: From internet via Application Load Balancer
- **Implementation**: Flask on ECS Fargate, DynamoDB for state

### Task 2: Secure Endpoint via VPN ✅
- **Endpoint**: `/secure-status`
- **Returns**: Same structure as `/status`
- **Accessible**: Only via WireGuard VPN connection
- **Implementation**: Separate ECS service in private subnet, security group restricts to VPN CIDR
- **Deliverables**:
  - `client.conf` (generated via `scripts/get-vpn-config.sh`)
  - Works with any WireGuard client

### Task 3: Public Webpage ✅
- **URL**: CloudFront distribution
- **Features**:
  - Plots `/status` hit count over time (always visible)
  - Plots `/secure-status` hit count over time (only when VPN connected)
  - Auto-refresh every 30 seconds
  - Configurable API endpoints
- **Implementation**: Static HTML + Chart.js served from S3 + CloudFront

## Technical Decisions

### Infrastructure
- **OpenTofu/Terraform**: Infrastructure as code for reproducibility
- **AWS**: Cloud provider using personal account
- **ECS Fargate**: Serverless containers, no server management
- **DynamoDB**: Serverless database, pay-per-request
- **WireGuard**: Modern VPN with simple configuration

### Application
- **Python Flask**: Minimal framework, easy to understand
- **Single Container**: Same image for both services, different env var
- **Dual-Service Architecture**: Public and private services for security isolation

### Security Model
- **Network-Level**: Security groups restrict access by IP range
- **Application-Level**: Endpoints check `API_MODE` environment variable
- **Defense in Depth**: Multiple layers of security

### Data Schema
- **Simplified Time-Series**: Each hit creates new DynamoDB record
- **No Atomic Counters**: Trade-off for simplicity (noted in improvements)
- **24-Hour Retention**: Query recent data for visualization

## Security Architecture

### Public Endpoints
```
Internet → ALB → Public ECS (10.0.0.x) → /status, /metrics
                    ↓
                 DynamoDB
```

### VPN-Protected Endpoints
```
Client → VPN Tunnel → VPN Server (10.0.100.1) → Private ECS (10.0.10.x) → /secure-status, /metrics
                                                        ↓
                                                    DynamoDB
```

**Security Enforcement**:
1. Private ECS in private subnets (no internet route)
2. Security group: Only allow 10.0.100.0/24 (VPN clients)
3. Application logic: Returns 404 if wrong `API_MODE`

## Deployment Process

1. **Infrastructure** (5 min):
   ```bash
   cd terraform
   ssh-keygen -t rsa -b 4096 -f vpn_server_key -N ""
   tofu init && tofu apply
   ```

2. **API Application** (3 min):
   ```bash
   ./scripts/deploy.sh
   ```

3. **Frontend** (1 min):
   ```bash
   ./scripts/deploy-frontend.sh
   ```

4. **VPN Configuration** (2-3 min):
   ```bash
   ./scripts/get-vpn-config.sh
   ```

5. **Testing**:
   ```bash
   ./scripts/test-endpoints.sh
   ```

## Answer to Your Question

**Q: "Doesn't this application allow someone to query /secure-status without being connected to the VPN?"**

**A: No, it's properly secured through a dual-service architecture:**

1. **Two Separate ECS Services**:
   - Public service (behind ALB): Only serves `/status`
   - Private service (in private subnet): Only serves `/secure-status`

2. **Application-Level Filtering**:
   - Public service has `API_MODE=public`, returns 404 for `/secure-status`
   - Private service has `API_MODE=private`, returns 404 for `/status`

3. **Network-Level Security**:
   - Private service is NOT publicly routable (no public IP, private subnet)
   - Security group only allows traffic from VPN CIDR (10.0.100.0/24)
   - Even if you knew the private IP, you can't reach it without VPN

4. **VPN Requirement**:
   - WireGuard assigns client IP in 10.0.100.0/24
   - Only those IPs can reach private service
   - Without VPN, your traffic never reaches private subnets

This provides **defense in depth**: multiple security layers must all be bypassed to access `/secure-status` without VPN.

## Testing the Security

```bash
# Without VPN - /secure-status should fail
curl http://private-api.seasats.local:5000/secure-status
# Result: Connection timeout or DNS failure

# Try via public API - should get 404
PUBLIC_URL=$(cd terraform && tofu output -raw public_api_url)
curl $PUBLIC_URL/secure-status
# Result: {"error": "Not found"} with HTTP 404

# Connect to VPN
sudo wg-quick up ./client.conf

# Now it works
curl http://private-api.seasats.local:5000/secure-status
# Result: {"count": 1, "random": 7}

# But /status doesn't work on private API
curl http://private-api.seasats.local:5000/status
# Result: {"error": "Not found"} with HTTP 404
```

## What Would Be Improved for Production

See [README.md](README.md#what-i-would-improve-with-more-time) for full list, but key items:

1. **Fix race condition**: Use DynamoDB atomic counters
2. **High availability**: Multi-AZ NAT, auto-scaling, failover
3. **Monitoring**: CloudWatch dashboards, alarms, X-Ray tracing
4. **Security**: WAF, VPC Flow Logs, Secrets Manager
5. **CI/CD**: Automated testing and deployment pipeline
6. **VPN**: Support multiple clients, certificate management

## Cost Analysis

Monthly cost for this POC: ~$85
- ECS Fargate: $15
- ALB: $20
- NAT Gateway: $35
- EC2 (VPN): $8
- DynamoDB: $1
- S3/CloudFront: $1
- Data transfer: $5

## Cleanup

```bash
cd terraform
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend | grep bucket | grep -v arn | awk '{print $3}' | tr -d '"')
aws s3 rm s3://$S3_BUCKET --recursive
tofu destroy
```

## Documentation

- **[README.md](README.md)**: Complete setup and documentation
- **[QUICKSTART.md](QUICKSTART.md)**: Fast deployment guide
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: Deep dive into design decisions
- **[terraform/README.md](terraform/README.md)**: Infrastructure documentation

## Deliverables

As requested in the assignment:

1. ✅ **Public URLs**:
   - API: From `tofu output public_api_url`
   - Webpage: From `tofu output frontend_url`

2. ✅ **VPN Client Config & Certificate**:
   - Generated via `./scripts/get-vpn-config.sh`
   - Saved as `client.conf` in project root
   - Contains both configuration and embedded keys

3. ✅ **README**:
   - Tech stack documented
   - Setup + testing instructions provided
   - Assumptions listed
   - Improvements section included

## Time Investment

Total time to build: ~4-6 hours
- Infrastructure design & implementation: 2 hours
- Application development: 1 hour
- Frontend & visualization: 1 hour
- Documentation: 1-2 hours
- Testing & refinement: 1 hour

## Key Assumptions

1. Single region deployment (us-east-1)
2. No custom domain needed
3. Single VPN client sufficient
4. 24-hour metrics retention adequate
5. No authentication/authorization required
6. Public endpoints truly public (no rate limiting)
7. Low traffic volume (pay-per-request pricing)
8. Development/POC environment (not HA)

## Contact & Support

For issues or questions:
- Review documentation files
- Check CloudWatch logs: `aws logs tail /ecs/seasats-takehome-api --follow`
- SSH to VPN server: `ssh -i terraform/vpn_server_key ubuntu@<VPN_IP>`
- Test endpoints: `./scripts/test-endpoints.sh`
