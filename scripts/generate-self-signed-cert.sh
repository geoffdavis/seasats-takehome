#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$SCRIPT_DIR/../terraform/certs"

echo -e "${GREEN}Generating Self-Signed SSL Certificates${NC}"
echo "========================================"
echo

# Create certs directory
mkdir -p "$CERT_DIR"

# Get ALB DNS name from terraform
cd "$SCRIPT_DIR/../terraform"
ALB_DNS=$(tofu output -raw public_api_url 2>/dev/null | sed 's|http://||')
CLOUDFRONT_DNS=$(tofu output -raw frontend_url 2>/dev/null | sed 's|http://||')

echo -e "${YELLOW}Generating certificate for ALB...${NC}"
echo "ALB DNS: $ALB_DNS"

# Generate private key
openssl genrsa -out "$CERT_DIR/alb-private-key.pem" 2048

# Generate certificate signing request
openssl req -new -key "$CERT_DIR/alb-private-key.pem" \
  -out "$CERT_DIR/alb-csr.pem" \
  -subj "/C=US/ST=State/L=City/O=Seasats/CN=seasats-alb" \
  -addext "subjectAltName=DNS:$ALB_DNS"

# Generate self-signed certificate (valid for 365 days)
openssl x509 -req -days 365 \
  -in "$CERT_DIR/alb-csr.pem" \
  -signkey "$CERT_DIR/alb-private-key.pem" \
  -out "$CERT_DIR/alb-certificate.pem" \
  -extensions v3_req \
  -extfile <(cat <<EOF
[v3_req]
subjectAltName=DNS:$ALB_DNS
EOF
)

echo
echo -e "${YELLOW}Generating certificate for CloudFront...${NC}"
echo "CloudFront DNS: $CLOUDFRONT_DNS"

# Generate private key for CloudFront
openssl genrsa -out "$CERT_DIR/cloudfront-private-key.pem" 2048

# Generate certificate signing request for CloudFront
openssl req -new -key "$CERT_DIR/cloudfront-private-key.pem" \
  -out "$CERT_DIR/cloudfront-csr.pem" \
  -subj "/C=US/ST=State/L=City/O=Seasats/CN=seasats-cdn" \
  -addext "subjectAltName=DNS:$CLOUDFRONT_DNS"

# Generate self-signed certificate for CloudFront (valid for 365 days)
openssl x509 -req -days 365 \
  -in "$CERT_DIR/cloudfront-csr.pem" \
  -signkey "$CERT_DIR/cloudfront-private-key.pem" \
  -out "$CERT_DIR/cloudfront-certificate.pem" \
  -extensions v3_req \
  -extfile <(cat <<EOF
[v3_req]
subjectAltName=DNS:$CLOUDFRONT_DNS
EOF
)

# Create certificate chain (self-signed, so cert is also the CA)
cp "$CERT_DIR/alb-certificate.pem" "$CERT_DIR/alb-certificate-chain.pem"
cp "$CERT_DIR/cloudfront-certificate.pem" "$CERT_DIR/cloudfront-certificate-chain.pem"

echo
echo -e "${GREEN}Certificates generated successfully!${NC}"
echo
echo "Certificate files created:"
echo "  ALB Certificate: $CERT_DIR/alb-certificate.pem"
echo "  ALB Private Key: $CERT_DIR/alb-private-key.pem"
echo "  CloudFront Certificate: $CERT_DIR/cloudfront-certificate.pem"
echo "  CloudFront Private Key: $CERT_DIR/cloudfront-private-key.pem"
echo
echo -e "${YELLOW}Note: These are self-signed certificates. Browsers will show a security warning.${NC}"
echo "You will need to accept the warning to access the sites."
