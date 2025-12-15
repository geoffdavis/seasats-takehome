#!/bin/bash
set -e

# Wrapper script to run OpenTofu commands with AWS credentials from 1Password

# Default to UUID for AWS Access Key - S3 - Personal item
ITEM_REF="${OP_ITEM_REF:-op://Private/b6mkfpo5e6osyijoy7ccjrxf7a}"

if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI (op) is not installed"
    echo "Install with: brew install 1password-cli"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "Usage: $0 <tofu-command> [args...]"
    echo ""
    echo "Examples:"
    echo "  $0 init"
    echo "  $0 plan"
    echo "  $0 apply"
    echo "  $0 destroy"
    echo ""
    echo "Environment variables:"
    echo "  OP_ITEM_REF=op://Private/b6mkfpo5e6osyijoy7ccjrxf7a"
    exit 1
fi

# Use 1Password CLI to inject credentials and run command
op run --env-file=<(cat <<EOF
AWS_ACCESS_KEY_ID=$ITEM_REF/access key id
AWS_SECRET_ACCESS_KEY=$ITEM_REF/secret access key
AWS_REGION=us-west-2
EOF
) -- bash -c "cd terraform && tofu $*"
