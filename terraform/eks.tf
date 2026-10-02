# ---------------------------------------------------------------------------
# EKS cluster + managed node group.
#
# COST NOTE: the control plane is $0.10/hour and has no free tier. It bills
# from creation until deletion. Always `terraform destroy` when finished -
# a forgotten cluster is ~$73/month.
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.26"

  cluster_name    = var.project
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = local.node_subnets

  # Public endpoint so you can reach the cluster from a laptop without a
  # bastion. Production would restrict this to known CIDRs or go private.
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Creates the OIDC provider that IRSA depends on - this is what lets a
  # ServiceAccount assume an IAM role, instead of granting permissions to
  # the whole node and every pod running on it.
  enable_irsa = true

  # Grants the identity running `terraform apply` cluster-admin, so the
  # kubernetes/helm providers can operate immediately after creation.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    eks-pod-identity-agent = { most_recent = true }
  }

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = {
    default = {
      name = "${var.project}-ng"

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Nodes sit in public subnets when NAT is disabled, so they need a
      # public IP to pull images and reach the control plane.
      subnet_ids = local.node_subnets

      disk_size = 20

      labels = {
        role = "general"
      }
    }
  }

  tags = var.tags
}
