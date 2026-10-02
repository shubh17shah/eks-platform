# ---------------------------------------------------------------------------
# VPC spanning multiple AZs.
#
# COST NOTE: enable_nat_gateway defaults to false, so worker nodes run in
# PUBLIC subnets with public IPs. This avoids ~$32/month of NAT Gateway cost
# that is billed hourly whether or not traffic flows.
#
# A production build would flip enable_nat_gateway to true, putting nodes in
# private subnets with egress through NAT. The code supports both paths; only
# the variable changes. See docs/DESIGN-DECISIONS.md.
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 per subnet: 4094 usable IPs, enough headroom for pod ENIs.
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Nodes land in private subnets only when NAT is enabled; otherwise public.
  node_subnets = var.enable_nat_gateway ? module.vpc.private_subnets : module.vpc.public_subnets
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # Single NAT (not one per AZ) when enabled - still ~$32/mo, but not ~$96.
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.enable_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required so the AWS Load Balancer Controller can auto-discover subnets
  # when creating internet-facing and internal load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb"               = "1"
    "kubernetes.io/cluster/${var.project}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"      = "1"
    "kubernetes.io/cluster/${var.project}" = "shared"
  }

  tags = var.tags
}
