output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Running control plane version"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC the cluster runs in"
  value       = module.vpc.vpc_id
}

output "node_subnets" {
  description = "Subnets the worker nodes were placed in"
  value       = local.node_subnets
}

output "nat_gateway_enabled" {
  description = "False means nodes are in public subnets to avoid NAT cost"
  value       = var.enable_nat_gateway
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
