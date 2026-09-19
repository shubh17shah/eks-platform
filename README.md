# eks-platform

Production-grade Kubernetes platform on AWS EKS, provisioned entirely as code.

## What this builds

- **Networking** — multi-AZ VPC (3 AZ), public/private subnets, NAT gateway
- **Cluster** — EKS with managed node groups, IRSA for pod-level IAM
- **Ingress** — AWS Load Balancer Controller, cert-manager for TLS, ExternalDNS
- **Delivery** — ArgoCD (app-of-apps), Helm charts for 10+ microservices
- **Service mesh** — Istio with mTLS and canary traffic splitting
- **Observability** — kube-prometheus-stack, custom Grafana dashboards as code
- **Scaling** — HPA, with a load test demonstrating it

## Stack

Terraform · AWS EKS · Kubernetes · Helm · ArgoCD · Istio · Prometheus · Grafana

## Layout

    terraform/     VPC, EKS, IAM, remote state (S3 + DynamoDB lock)
    charts/        Helm charts per service
    argocd/        app-of-apps manifests
    apps/          demo microservices
    docs/          architecture diagram, design decisions

## Usage

    make up      # provision everything
    make down    # tear down (EKS costs ~$0.10/hr for the control plane alone)

> **Cost warning:** always run `make down` when finished.

## Status

In progress.

## Design decisions

_To document: why managed node groups over self-managed, IRSA over node IAM roles,
ArgoCD over push-based CD, and the trade-offs of running Istio at this scale._
