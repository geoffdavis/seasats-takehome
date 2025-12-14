#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}Testing API Endpoints${NC}"
echo "====================="
echo

cd terraform

# Get public API URL
PUBLIC_API=$(tofu output -raw public_api_url 2>/dev/null)

if [ -z "$PUBLIC_API" ]; then
    echo -e "${RED}Could not find public API URL. Is the infrastructure deployed?${NC}"
    exit 1
fi

echo -e "${BLUE}Public API URL: $PUBLIC_API${NC}"
echo

# Test public /status endpoint
echo -e "${YELLOW}Testing public /status endpoint...${NC}"
echo "Request: curl $PUBLIC_API/status"
RESPONSE=$(curl -s $PUBLIC_API/status)
echo -e "${GREEN}Response: $RESPONSE${NC}"
echo

# Test that /secure-status returns 404 on public API
echo -e "${YELLOW}Testing that /secure-status is blocked on public API...${NC}"
echo "Request: curl $PUBLIC_API/secure-status"
RESPONSE=$(curl -s -w "\nHTTP Status: %{http_code}" $PUBLIC_API/secure-status)
echo -e "${GREEN}Response: $RESPONSE${NC}"
echo "Expected: Should return 404 with error message"
echo

# Test /metrics endpoint
echo -e "${YELLOW}Testing /metrics endpoint...${NC}"
echo "Request: curl $PUBLIC_API/metrics"
RESPONSE=$(curl -s $PUBLIC_API/metrics)
echo -e "${GREEN}Response: $RESPONSE${NC}"
echo

# Test private API (only works if VPN is connected)
echo -e "${YELLOW}Testing VPN-protected /secure-status endpoint...${NC}"
echo "Request: curl http://private-api.seasats.local:5000/secure-status"
echo -e "${BLUE}Note: This will only work if you're connected to the VPN${NC}"
if curl -s --connect-timeout 5 http://private-api.seasats.local:5000/secure-status > /dev/null 2>&1; then
    RESPONSE=$(curl -s http://private-api.seasats.local:5000/secure-status)
    echo -e "${GREEN}Response: $RESPONSE${NC}"
    echo -e "${GREEN}✓ VPN is connected and working!${NC}"
else
    echo -e "${YELLOW}Could not connect to private API (VPN not connected)${NC}"
    echo "To connect to VPN, run: sudo wg-quick up ./client.conf"
fi
echo

# Test that /status returns 404 on private API
echo -e "${YELLOW}Testing that /status is blocked on private API...${NC}"
echo "Request: curl http://private-api.seasats.local:5000/status"
if curl -s --connect-timeout 5 http://private-api.seasats.local:5000/status > /dev/null 2>&1; then
    RESPONSE=$(curl -s -w "\nHTTP Status: %{http_code}" http://private-api.seasats.local:5000/status)
    echo -e "${GREEN}Response: $RESPONSE${NC}"
    echo "Expected: Should return 404 with error message"
else
    echo -e "${YELLOW}Could not connect to private API (VPN not connected)${NC}"
fi
echo

echo -e "${GREEN}Testing complete!${NC}"
