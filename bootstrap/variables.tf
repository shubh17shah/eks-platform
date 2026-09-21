variable "project" {
  description = "Project name, used as a prefix for created resources"
  type        = string
  default     = "eks-platform"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project   = "eks-platform"
    ManagedBy = "terraform"
    Owner     = "shubh17shah"
  }
}
