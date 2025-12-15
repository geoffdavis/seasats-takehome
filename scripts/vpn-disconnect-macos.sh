#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_CONF="$SCRIPT_DIR/../client.conf"

echo -e "${YELLOW}Removing DNS configuration...${NC}"

# Remove DNS configuration
sudo /usr/sbin/scutil <<EOF
remove State:/Network/Service/WireGuard-VPN/DNS
quit
EOF

# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo -e "${YELLOW}Disconnecting VPN...${NC}"

# Disconnect WireGuard
sudo wg-quick down "$CLIENT_CONF" 2>&1 | grep -v "Warning:.*world accessible" || true

echo
echo -e "${GREEN}VPN Disconnected!${NC}"
