terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # See infra/bootstrap/main.tf for why this doesn't use `profile`.

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-ephemeral"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
