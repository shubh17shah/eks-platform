variable "project" {
  description = "Project name, used as a resource name prefix"
  type        = string
  default     = "eks-platform"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across"
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (EKS requires at least 2 AZs)."
  }
}

variable "kubernetes_version" {
  description = "EKS control plane version"
  type        = string
  default     = "1.31"
}

# --- cost controls -------------------------------------------------------

variable "enable_nat_gateway" {
  description = <<-EOT
    Place worker nodes in PRIVATE subnets behind a NAT Gateway.
    Costs roughly $32/month per NAT, billed whether or not traffic flows.
    Left false for this sandbox; a production deployment would set it true.
  EOT
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is ~70% cheaper and fine for a sandbox."
  type        = string
  default     = "SPOT"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_desired_size" {
  description = "Desired worker node count"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum worker node count"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker node count"
  type        = number
  default     = 4
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

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version"
  type        = string
  default     = "7.7.7"
}

variable "bootstrap_gitops" {
  description = <<-EOT
    Apply argocd/root-app.yaml after installing ArgoCD, handing the cluster over
    to GitOps. Requires kubectl and awscli on the machine running terraform.
    Set false if you prefer to apply the root Application by hand.
  EOT
  type        = bool
  default     = true
}
