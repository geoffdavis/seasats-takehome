output "public_api_url" {
  description = "URL for the public API"
  value       = "http://${aws_lb.public.dns_name}"
}

output "frontend_url" {
  description = "URL for the frontend webpage"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "vpn_server_public_ip" {
  description = "Public IP of the VPN server"
  value       = aws_eip.vpn.public_ip
}

output "private_api_internal_dns" {
  description = "Internal DNS name for private API (accessible via VPN)"
  value       = "private-api.seasats.local:5000"
}

output "ecr_repository_url" {
  description = "ECR repository URL for the API container"
  value       = aws_ecr_repository.api.repository_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table name for API metrics"
  value       = aws_dynamodb_table.api_metrics.name
}

output "vpn_server_instance_id" {
  description = "VPN server EC2 instance ID"
  value       = aws_instance.vpn.id
}
