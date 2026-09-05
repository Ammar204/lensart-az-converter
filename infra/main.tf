terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudFront accepts ACM certificates ONLY from us-east-1, regardless of where
# the bucket lives. This alias exists for that one resource.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
