# Cost

This project is designed to run "as close to free as possible" — but **the
EKS control plane has no free tier and bills the instant it exists.** Read
this before running `make up`, and run `make down` the moment you're done.

Everything below is for **region `ap-south-1`**, the variable defaults in
`terraform/variables.tf`, and a cluster left applied but otherwise idle (no
real traffic, no manually-added load balancers).

## Breakdown, per resource

| Resource                                  | Qty | Hourly       | Daily       | Monthly (~730h) | Why it costs this |
|--------------------------------------------|----:|-------------:|------------:|-----------------:|---|
| EKS control plane                          |   1 | $0.100       | $2.40       | **$73.00**       | Flat AWS fee, no free tier. Bills from `terraform apply` until the cluster is deleted, regardless of usage. |
| `t3.small` SPOT nodes                      |   2 | ~$0.014      | ~$0.34      | ~$10.66          | Estimate: on-demand `t3.small` in `ap-south-1` is ~$0.021/hr; SPOT typically runs 60–70% cheaper. **Actual SPOT price varies by AZ and time** — check the [EC2 Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/) or Pricing Calculator for live numbers. |
| EBS gp3 root volumes (20 GiB × 2 nodes)    |   2 | ~$0.005      | ~$0.12      | ~$3.65           | `disk_size = 20` in `eks.tf`, gp3 baseline storage rate ≈ $0.091/GiB-month in `ap-south-1`. |
| Public IPv4 addresses                      |   2 | $0.010       | $0.24       | $7.30            | Since Feb 2024, **AWS bills $0.005/hr for every public IPv4 address**, including auto-assigned ones. Nodes need these because `enable_nat_gateway = false` puts them in public subnets — the NAT-avoidance saving is bigger than this cost, but it isn't literally free. |
| NAT Gateway                                |   0 | $0.000       | $0.00       | $0.00            | Disabled (`enable_nat_gateway = false`, the project default). If flipped to `true`: per `variables.tf`'s own estimate, roughly **+$32/month**, billed hourly whether or not traffic flows, plus per-GB data processing. |
| S3 state bucket + DynamoDB lock table      |   1+1 | ~$0.000    | ~$0.00      | <$0.05           | A few KB of versioned state; DynamoDB is `PAY_PER_REQUEST` and idle outside `terraform apply`/`plan`. Created once by `bootstrap/`, safe to leave running indefinitely. |
| ALB (AWS Load Balancer Controller)         |   0 | n/a          | n/a         | n/a              | **Not created yet** — `irsa.tf` provisions the controller's IRSA role, and `argocd/apps/platform/aws-load-balancer-controller.yaml` + `charts/values/api-gateway.yaml` (`api-gateway`, the only one of 12 services with `ingress.enabled: true`) fully define it, but nothing has run against a live cluster yet (see docs/DESIGN-DECISIONS.md). Budget for when it goes live: **exactly 1 ALB** (not 12 — only `api-gateway` has Ingress on), ~$0.0225/hr + LCU charges (roughly **$18–25/month** baseline) plus a public IP per AZ. |
| Platform add-ons (cert-manager, Istio, kube-prometheus-stack, metrics-server) | — | $0 extra | $0 extra | $0 extra | Fully defined in `argocd/apps/platform/`, but these are pods on the **existing** 2 nodes, not new AWS resources — no separate line item. They do compete for the ~2.8GiB total allocatable RAM across both `t3.small` nodes; see docs/DESIGN-DECISIONS.md §8 for why only 2 of 12 services run an Istio sidecar. |
| **Total, as currently applied**            |     | **~$0.13**   | **~$3.10**  | **~$94.60**      | Control plane + nodes + EBS + public IPs. Excludes NAT (disabled) and the ALB (not deployed). |

Run `make cost` for this same table from the CLI without opening this file.

### Assumptions behind the estimates

- On-demand `t3.small` in `ap-south-1` ≈ $0.021/hr; SPOT discount assumed at
  ~65% off. Spot pricing is a live auction — treat the SPOT line as a
  ballpark, not a quote.
- gp3 EBS storage ≈ $0.091/GiB-month in `ap-south-1` (baseline 3,000 IOPS /
  125 MiB/s throughput, both included at that size — no extra IOPS/throughput
  purchased).
- Public IPv4 pricing ($0.005/hr/address) is AWS's published, region-uniform
  rate as of the Feb 2024 change — the one figure here that isn't a regional
  estimate.
- Figures exclude data transfer (egress), which is usage-dependent and
  expected to be near-zero for a sandbox cluster with no production traffic.

## The "forgot to destroy" scenario

This is the actual failure mode this project is trying to design against —
worth internalizing the numbers so `make down` isn't optional in practice:

| Forgotten for... | Cost (~$0.13/hr all-in, no ALB/NAT) |
|---|---:|
| A weekend (2 days)   | ~$6.24   |
| A week               | ~$21.84  |
| A month              | ~$94.60  |
| A year (worst case)  | ~$1,135  |

And it can get worse than the "idle" number above:

- **If the ALB controller (or anything else) is installed with `kubectl`/
  `helm` outside Terraform** and creates a `LoadBalancer`-type Service or
  Ingress, `terraform destroy` has no idea it exists. The ALB — and the ENIs
  it attaches to your subnets — keeps billing *and* can block the VPC or
  subnets from deleting cleanly, leaving Terraform's destroy partially
  failed and more resources stranded than you started with.
- **NAT Gateway, if ever flipped on for a test,** adds ~$32/month billed
  hourly regardless of traffic — easy to forget it's back on if
  `enable_nat_gateway` gets toggled during experimentation and not toggled
  back.
- Root EBS volumes are deleted with their instance on termination by
  default for this node group, so orphaned volumes aren't expected — but
  it's cheap insurance to check (see checklist below).

## Teardown checklist

1. **Delete anything installed outside Terraform first.** If you
   `kubectl apply`'d or `helm install`'d an Ingress, a `LoadBalancer`
   Service, ArgoCD, or Istio by hand, tear those down (`kubectl delete`,
   `helm uninstall`) *before* running `terraform destroy` — otherwise their
   ALBs/ENIs aren't tracked by Terraform and can survive the destroy,
   silently billing and blocking VPC deletion.
2. **`make down`** — runs `terraform destroy -auto-approve` in `terraform/`.
3. **`make destroy-check`** — confirms, via the AWS CLI, that there's no
   `eks-platform` EKS cluster, no tagged EC2 instances, no load balancers,
   and no NAT gateways left in `ap-south-1`. Every line should read `PASS`.
4. **Leave `bootstrap/`'s S3 bucket + DynamoDB table alone** unless you're
   fully done with the project — they cost pennies to keep running, and
   destroying them means redoing the `backend_config` paste-in
   (`terraform/backend.tf`) the next time you provision.
5. **Check AWS Cost Explorer the next day.** Billing has some lag; a same-day
   `destroy-check` PASS is a strong signal but not a substitute for
   confirming in the console once the numbers catch up.
6. If you're fully retiring the project, `cd bootstrap && terraform destroy`
   removes the state bucket and lock table too (the bucket has
   `force_destroy = true`, so it deletes even if it isn't empty).

See [DESIGN-DECISIONS.md](./DESIGN-DECISIONS.md) for why NAT Gateway is
disabled, why nodes run in public subnets instead, and what a production
deployment would change.
