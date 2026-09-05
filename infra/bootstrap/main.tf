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
  # Credentials come from AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/
  # AWS_SESSION_TOKEN, exported by scripts/lib/aws_creds.sh — not
  # `profile`, since the `aws login` browser-session credential format
  # in ~/.aws/config isn't one the AWS Go SDK (which the provider uses)
  # recognizes yet. The `aws` CLI itself still works fine with --profile.

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
