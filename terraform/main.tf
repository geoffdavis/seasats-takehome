terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  project_name = "seasats-takehome"
  common_tags = {
    Project = local.project_name
    ManagedBy = "OpenTofu"
  }
}
