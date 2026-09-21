output "state_bucket" {
  description = "Copy this into terraform/backend.tf"
  value       = aws_s3_bucket.state.id
}

output "lock_table" {
  description = "DynamoDB table used for state locking"
  value       = aws_dynamodb_table.lock.name
}

output "backend_config" {
  description = "Paste this block into terraform/backend.tf"
  value       = <<-EOT

    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.state.id}"
        key            = "eks-platform/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.lock.name}"
        encrypt        = true
      }
    }
  EOT
}
