# ---------------------------------------------------------------------------
# IRSA - IAM Roles for Service Accounts.
#
# Without IRSA, every pod on a node inherits that node's IAM role, so a
# compromised pod gets whatever the node can do. IRSA binds a role to a single
# Kubernetes ServiceAccount via the cluster's OIDC provider, giving pod-level
# least privilege.
#
# Here it backs the AWS Load Balancer Controller, which needs to create and
# manage ALBs in response to Ingress resources.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  oidc_provider_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    # Scope the trust to exactly one ServiceAccount in one namespace.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.project}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
  tags               = var.tags
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.project}-alb-controller"
  description = "Permissions for the AWS Load Balancer Controller"
  policy      = file("${path.module}/policies/alb-controller-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}
