#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Retrieving VPN Configuration${NC}"
echo "=============================="
echo

cd terraform

# Get VPN server IP
VPN_IP=$(tofu output -raw vpn_server_public_ip 2>/dev/null)

if [ -z "$VPN_IP" ]; then
    echo -e "${RED}Could not find VPN server IP. Is the infrastructure deployed?${NC}"
    exit 1
fi

echo "VPN Server IP: $VPN_IP"
echo

# Check if SSH key exists
if [ ! -f "vpn_server_key" ]; then
    echo -e "${RED}SSH key not found at terraform/vpn_server_key${NC}"
    exit 1
fi

echo -e "${YELLOW}Waiting for VPN server to finish initialization (this may take 2-3 minutes)...${NC}"
echo "You can check cloud-init logs with:"
echo "  ssh -i terraform/vpn_server_key ubuntu@$VPN_IP 'sudo tail -f /var/log/cloud-init-output.log'"
echo

# Wait for SSH to be available
echo -e "${YELLOW}Waiting for SSH to be available...${NC}"
until ssh -i vpn_server_key -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VPN_IP "echo 'SSH ready'" 2>/dev/null; do
    echo -n "."
    sleep 5
done
echo
echo -e "${GREEN}SSH connection established!${NC}"
echo

# Wait for WireGuard to be configured
echo -e "${YELLOW}Waiting for WireGuard configuration to be ready...${NC}"
until ssh -i vpn_server_key -o StrictHostKeyChecking=no ubuntu@$VPN_IP "sudo test -f /root/client.conf" 2>/dev/null; do
    echo -n "."
    sleep 5
done
echo
echo -e "${GREEN}WireGuard configuration ready!${NC}"
echo

# Retrieve client configuration
echo -e "${YELLOW}Retrieving client configuration...${NC}"
ssh -i vpn_server_key -o StrictHostKeyChecking=no ubuntu@$VPN_IP "sudo cat /root/client.conf" > ../client.conf

echo -e "${GREEN}VPN client configuration saved to: client.conf${NC}"
echo

echo "To connect to the VPN:"
echo "  sudo wg-quick up ./client.conf"
echo
echo "To disconnect:"
echo "  sudo wg-quick down ./client.conf"
echo
echo "To test the VPN connection:"
echo "  curl http://private-api.seasats.local:5000/secure-status"
