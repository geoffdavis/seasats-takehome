#!/bin/bash
echo "Checking ALB certificate (us-west-2)..."
aws acm describe-certificate \
  --certificate-arn $(aws acm list-certificates --region us-west-2 --query 'CertificateSummaryList[?DomainName==`seasats-api.geoffdavis.com`].CertificateArn' --output text) \
  --region us-west-2 \
  --query 'Certificate.Status' --output text

echo -e "\nChecking CloudFront certificate (us-east-1)..."
aws acm describe-certificate \
  --certificate-arn $(aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[?DomainName==`seasats.geoffdavis.com`].CertificateArn' --output text) \
  --region us-east-1 \
  --query 'Certificate.Status' --output text
