#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_CONF="$SCRIPT_DIR/../client.conf"

if [ ! -f "$CLIENT_CONF" ]; then
    echo -e "${RED}Error: client.conf not found at $CLIENT_CONF${NC}"
    echo "Run ./scripts/get-vpn-config.sh first"
    exit 1
fi

echo -e "${GREEN}Connecting to VPN...${NC}"

# Start WireGuard
sudo wg-quick up "$CLIENT_CONF" 2>&1 | grep -v "Warning:.*world accessible" || true

# Get the interface name (should be utun8 or similar)
INTERFACE=$(sudo wg show interfaces | grep utun | head -1)

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}Error: WireGuard interface not found${NC}"
    exit 1
fi

echo -e "${YELLOW}Configuring DNS for interface $INTERFACE...${NC}"

# Configure DNS using scutil
# This creates a DNS configuration for the WireGuard interface with search domain scoping
sudo /usr/sbin/scutil <<EOF
d.init
d.add ServerAddresses * 10.0.0.2
d.add SearchDomains * seasats.local
d.add DomainName seasats.local
d.add SupplementalMatchDomains * seasats.local
set State:/Network/Service/WireGuard-VPN/DNS
quit
EOF

# Refresh DNS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true

echo
echo -e "${GREEN}VPN Connected!${NC}"
echo
echo "DNS Configuration:"
scutil --dns | grep -A 5 "resolver.*seasats.local" || echo -e "${YELLOW}Note: DNS resolver for seasats.local configured${NC}"
echo
echo "Test DNS resolution:"
dig @10.0.0.2 private-api.seasats.local +short
echo
echo -e "${YELLOW}To disconnect, run:${NC}"
echo "  ./scripts/vpn-disconnect-macos.sh"
