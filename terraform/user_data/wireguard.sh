#!/bin/bash
set -e

# Update and install WireGuard
apt-get update
apt-get install -y wireguard qrencode

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Generate server keys
cd /etc/wireguard
umask 077
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Generate client keys
wg genkey | tee client_private.key | wg pubkey > client_public.key

SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)
CLIENT_PRIVATE_KEY=$(cat client_private.key)
CLIENT_PUBLIC_KEY=$(cat client_public.key)

# Get the server's public IP
SERVER_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Create WireGuard server configuration
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.0.100.1/24
ListenPort = ${vpn_server_port}
PrivateKey = $SERVER_PRIVATE_KEY

# IP forwarding
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.100.2/32
EOF

# Create client configuration
cat > /root/client.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.100.2/24
DNS = 10.0.0.2

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:${vpn_server_port}
AllowedIPs = ${vpc_cidr}
PersistentKeepalive = 25
EOF

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Create a file with connection instructions
cat > /root/vpn-instructions.txt <<EOF
WireGuard VPN Configuration
===========================

Server Public IP: $SERVER_PUBLIC_IP
Server Public Key: $SERVER_PUBLIC_KEY
Client Configuration: /root/client.conf

To connect from your client:
1. Install WireGuard on your machine
2. Copy the client.conf file to your local machine
3. Run: wg-quick up /path/to/client.conf

To access the private API:
- URL: http://${private_api_dns}/secure-status
- Only accessible when VPN is connected

To disconnect:
- Run: wg-quick down /path/to/client.conf
EOF

echo "WireGuard VPN setup complete!"
