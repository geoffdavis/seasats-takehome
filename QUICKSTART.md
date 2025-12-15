# Quick Start Guide

Get everything running in ~15 minutes. For detailed documentation, see [README.md](README.md).

## Prerequisites

- AWS account with CLI configured (`aws login`)
- OpenTofu or Terraform installed
- Docker or Podman installed
- Cloudflare account with API token (for SSL certificates)

## Deploy Everything

```bash
# 1. Set up AWS credentials
source <(./scripts/setup-aws-creds.sh)

# 2. Set Cloudflare API token
export TF_VAR_cloudflare_api_token=$(op read "op://Automation/Cloudflare API Token/token")

# 3. Deploy infrastructure
cd terraform
ssh-keygen -t rsa -b 4096 -f vpn_server_key -N ""
cp terraform.tfvars.example terraform.tfvars
tofu init
tofu apply

# 4. Deploy API and frontend (wait in between for ECS to stabilize)
cd ..
./scripts/deploy.sh
sleep 120  # Wait for ECS tasks to start
./scripts/deploy-frontend.sh

# 5. Get VPN configuration
./scripts/get-vpn-config.sh
```

## Access the Application

1. **Get your URLs:**
   ```bash
   cd terraform
   tofu output frontend_url     # Frontend: https://seasats.geoffdavis.com
   tofu output public_api_url   # Public API: https://seasats-api.geoffdavis.com
   ```

2. **Open the frontend** - the dashboard will show public API metrics

4. **For VPN-protected private API:**
   ```bash
   # Connect to VPN (macOS: use WireGuard.app, or command line)
   sudo wg-quick up ./client.conf

   # Access private endpoint
   curl http://private-api.seasats.local:5000/secure-status

   # Disconnect when done
   sudo wg-quick down ./client.conf
   ```

## Test It Works

```bash
./scripts/test-endpoints.sh
```

## Cleanup

```bash
source <(./scripts/setup-aws-creds.sh)
cd terraform
S3_BUCKET=$(tofu output -raw frontend_s3_url | cut -d/ -f3 | cut -d. -f1)
aws s3 rm s3://$S3_BUCKET --recursive
tofu destroy
```

## Troubleshooting

**Credentials expired?**
```bash
source <(./scripts/setup-aws-creds.sh)
```

**ECS tasks not starting?**
```bash
aws logs tail /ecs/seasats-takehome-api --follow
```

**Want details?** See [README.md](README.md) for:

- Architecture overview
- Security model
- Known issues and workarounds
- Production recommendations
