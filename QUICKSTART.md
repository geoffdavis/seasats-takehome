# Quick Start Guide

This guide will get you up and running quickly. For detailed documentation, see [README.md](README.md).

## Prerequisites

- AWS account with credentials configured
- OpenTofu or Terraform installed
- Docker installed
- AWS CLI installed

## 1. Deploy Infrastructure (5 minutes)

```bash
# Navigate to terraform directory
cd terraform

# Generate SSH key for VPN server
ssh-keygen -t rsa -b 4096 -f vpn_server_key -N ""

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Initialize and deploy
tofu init
tofu apply

# Save important outputs
tofu output > ../outputs.txt
```

## 2. Build and Deploy API (3 minutes)

```bash
# From project root
./scripts/deploy.sh
```

Wait 2-3 minutes for ECS services to stabilize.

## 3. Deploy Frontend (1 minute)

```bash
./scripts/deploy-frontend.sh
```

## 4. Get VPN Configuration (2-3 minutes)

```bash
./scripts/get-vpn-config.sh
```

This will wait for the VPN server to initialize and save `client.conf` to the project root.

## 5. Test Everything

```bash
# Test public endpoints
./scripts/test-endpoints.sh

# Connect to VPN
sudo wg-quick up ./client.conf

# Test again to verify VPN-protected endpoint works
./scripts/test-endpoints.sh

# Disconnect from VPN
sudo wg-quick down ./client.conf
```

## 6. Access the Dashboard

1. Get the frontend URL from outputs:
   ```bash
   cd terraform
   tofu output frontend_url
   ```

2. Open the URL in your browser

3. Configure the API URL:
   - Public API URL: Get from `tofu output public_api_url`
   - Private API URL: `http://private-api.seasats.local:5000` (default)

4. Save and view the metrics!

## Accessing the Services

### Public API
```bash
PUBLIC_URL=$(cd terraform && tofu output -raw public_api_url)

# Test /status endpoint
curl $PUBLIC_URL/status

# View metrics
curl $PUBLIC_URL/metrics
```

### VPN-Protected API
```bash
# Connect to VPN first
sudo wg-quick up ./client.conf

# Access secure endpoint
curl http://private-api.seasats.local:5000/secure-status

# Disconnect
sudo wg-quick down ./client.conf
```

## Cleanup

```bash
cd terraform

# Delete S3 bucket contents
S3_BUCKET=$(tofu state show aws_s3_bucket.frontend | grep bucket | grep -v arn | awk '{print $3}' | tr -d '"')
aws s3 rm s3://$S3_BUCKET --recursive

# Destroy infrastructure
tofu destroy
```

## Troubleshooting

### ECS tasks not starting
Check CloudWatch logs:
```bash
aws logs tail /ecs/seasats-takehome-api --follow
```

### VPN not connecting
Check VPN server logs:
```bash
ssh -i terraform/vpn_server_key ubuntu@<VPN_IP> 'sudo journalctl -u wg-quick@wg0'
```

### Frontend not loading
- Wait 5-10 minutes for CloudFront distribution to deploy
- Check if files are in S3:
  ```bash
  aws s3 ls s3://$S3_BUCKET/
  ```

## Architecture Summary

```
Internet
  │
  ├─► ALB ──► Public ECS Service ──► /status (port 5000)
  │                                 └─► /metrics (public data)
  │
  └─► VPN Server (WireGuard)
         │
         └─► Private ECS Service ──► /secure-status (port 5000)
                                    └─► /metrics (secure data)

Both services access the same DynamoDB table
Frontend is served from CloudFront + S3
```

## Key Security Notes

1. **Application-level endpoint isolation**: Each ECS service (public/private) only exposes its designated endpoints via `API_MODE` environment variable
2. **Network-level security**: Private API security group only allows traffic from VPN CIDR (10.0.100.0/24)
3. **Data separation**: Metrics endpoint returns different data based on which service you query
4. **VPN encryption**: All traffic to private API is encrypted through WireGuard tunnel

## Next Steps

- Review the full [README.md](README.md) for detailed architecture decisions
- Check the "What I Would Improve" section for production considerations
- Explore the Terraform configuration in `terraform/`
