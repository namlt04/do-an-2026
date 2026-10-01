# main.tf
# Provider + VPC. Bo ma nay mo ta ha tang cho mot ung dung web se len AWS.
# Bai lab la PHAN TICH TINH: chi validate/scan cuc bo, KHONG terraform apply len cloud that.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.72.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
  # Che do mo ta - khong can credential that vi chi validate/scan.
  # (Cac tham so duoi giup provider khong co gang goi API khi validate.)
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  access_key                  = "mock"
  secret_key                  = "mock"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ptit-devsecops-vpc"
  }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-1a"

  tags = {
    Name = "ptit-app-subnet"
  }
}
