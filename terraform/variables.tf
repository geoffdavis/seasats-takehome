variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpn_client_cidr" {
  description = "CIDR block for VPN clients"
  type        = string
  default     = "10.0.100.0/24"
}

variable "vpn_server_port" {
  description = "WireGuard VPN server port"
  type        = number
  default     = 51820
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS management"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for SSL certificates"
  type        = string
  default     = "geoffdavis.com"
}
