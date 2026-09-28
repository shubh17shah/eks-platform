# ---------------------------------------------------------------------------
# ArgoCD install + GitOps bootstrap.
#
# Chicken-and-egg: ArgoCD manages every other platform component declaratively,
# but something has to install ArgoCD itself. Terraform does that here, then
# applies ONLY the root Application. From that point on ArgoCD owns the cluster
# and Terraform stays out of Kubernetes entirely.
#
# This is the standard "app of apps" bootstrap: one imperative step to plant
# the seed, everything after it declarative and self-healing.
# ---------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Wait for the CRDs and server to be ready before we apply the root app,
  # otherwise the Application kind does not exist yet.
  wait          = true
  wait_for_jobs = true
  timeout       = 900

  values = [yamlencode({
    # Sandbox sizing: these defaults assume beefy nodes. On 2x t3.small the
    # stock requests will leave pods Pending, so trim them down.
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }
    server = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      # No ingress/LoadBalancer by default - an ALB costs ~$16/month.
      # Reach the UI with: kubectl -n argocd port-forward svc/argocd-server 8080:443
      service   = { type = "ClusterIP" }
      extraArgs = ["--insecure"] # TLS terminates at the ALB when ingress is enabled
    }
    dex = {
      enabled = false # no SSO in a sandbox; saves a pod
    }
    notifications = {
      enabled = false
    }
    applicationSet = {
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
      }
    }
  })]

  depends_on = [module.eks]
}

# Plant the root Application. Everything else - cert-manager, Istio,
# kube-prometheus-stack, the ALB controller and all 12 microservices - is
# pulled in by this one manifest via the app-of-apps pattern.
resource "null_resource" "argocd_root_app" {
  count = var.bootstrap_gitops ? 1 : 0

  triggers = {
    root_app_sha = filesha256("${path.module}/../argocd/root-app.yaml")
    cluster      = module.eks.cluster_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}
      kubectl apply -f ${path.module}/../argocd/root-app.yaml
      echo ""
      echo "ArgoCD bootstrapped. Get the admin password with:"
      echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
      echo "Then port-forward the UI:"
      echo "  kubectl -n argocd port-forward svc/argocd-server 8080:443"
    EOT
  }

  depends_on = [helm_release.argocd]
}
