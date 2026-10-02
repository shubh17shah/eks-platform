# ---------------------------------------------------------------------------
# Bootstrap: creates the S3 bucket + DynamoDB table that hold Terraform state
# for the main stack. Run this ONCE, with local state, before ../terraform.
#
#   cd bootstrap && terraform init && terraform apply
#
# Cost: S3 storage is pennies; DynamoDB on-demand is effectively free at this
# volume. Safe to leave running between sessions.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project}-tfstate-${random_id.suffix.hex}"
}

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = true # personal sandbox: allows clean teardown

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State files contain secrets in plaintext - encrypt at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Prevents two concurrent `terraform apply` runs corrupting state.
resource "aws_dynamodb_table" "lock" {
  name         = "${var.project}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}
