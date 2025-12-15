#!/bin/bash
set -e

# Helper script to export AWS credentials from aws login cache
# This avoids the AWS CLI credential refresh bug by unsetting AWS_CONFIG_FILE
# Usage: eval $(./scripts/setup-aws-creds.sh)

# Find the most recent cache file
CACHE_FILE=$(find ~/.aws/login/cache -name "*.json" -type f 2>/dev/null | head -1)

if [ -z "$CACHE_FILE" ]; then
    echo "# No cached credentials found. Running 'aws login'..." >&2
    aws login >&2
    sleep 3
    CACHE_FILE=$(find ~/.aws/login/cache -name "*.json" -type f 2>/dev/null | head -1)
fi

# Extract credentials from the cache file using jq
if [ -f "$CACHE_FILE" ]; then
    ACCESS_KEY=$(jq -r '.accessToken.accessKeyId' "$CACHE_FILE")
    SECRET_KEY=$(jq -r '.accessToken.secretAccessKey' "$CACHE_FILE")
    SESSION_TOKEN=$(jq -r '.accessToken.sessionToken' "$CACHE_FILE")
    EXPIRES_AT=$(jq -r '.accessToken.expiresAt' "$CACHE_FILE")

    if [ "$ACCESS_KEY" != "null" ] && [ "$SECRET_KEY" != "null" ]; then
        # Check if credentials are expired
        EXPIRES_EPOCH=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$EXPIRES_AT" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)

        if [ "$EXPIRES_EPOCH" -lt "$NOW_EPOCH" ]; then
            echo "# Credentials expired. Running 'aws login'..." >&2
            aws login >&2
            sleep 3
            # Re-read the cache file
            ACCESS_KEY=$(jq -r '.accessToken.accessKeyId' "$CACHE_FILE")
            SECRET_KEY=$(jq -r '.accessToken.secretAccessKey' "$CACHE_FILE")
            SESSION_TOKEN=$(jq -r '.accessToken.sessionToken' "$CACHE_FILE")
        fi

        # Output credentials AND set AWS_CONFIG_FILE to empty to prevent refresh bug
        echo "export AWS_ACCESS_KEY_ID='$ACCESS_KEY'"
        echo "export AWS_SECRET_ACCESS_KEY='$SECRET_KEY'"
        echo "export AWS_SESSION_TOKEN='$SESSION_TOKEN'"
        echo "export AWS_DEFAULT_REGION='us-west-2'"
        echo "export AWS_CONFIG_FILE=''"
        exit 0
    fi
fi

echo "# Error: Could not read credentials from cache" >&2
exit 1
