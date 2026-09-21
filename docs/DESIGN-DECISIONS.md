# Design Decisions

This document is the "why," not the "what" — the README covers what this repo
builds. Each section below states the decision, the alternatives considered,
why this one won, and what would change if this were a real production
platform instead of a cost-constrained portfolio project.

**Implementation status, honestly:** two layers of this repo are fully
written, and they haven't met a live AWS account yet. `terraform/`
provisions the VPC, the EKS cluster, one managed node group, and the IRSA
IAM role/policy for the AWS Load Balancer Controller — but nobody has run
`terraform apply` against a real account (no state file exists). Separately,
`charts/microservice/` (one generic Helm chart) plus `charts/values/`
(10 per-service values files) and `argocd/` (a full app-of-apps: namespaces,
metrics-server, cert-manager, Istio, kube-prometheus-stack, the ALB
controller, and 10 microservice Applications, all sync-wave ordered) are
completely written out. What's still missing is the glue between the two
layers: nothing in this repo installs ArgoCD itself into the cluster (no
Terraform `helm_release`, no bootstrap script) — that's a manual, one-time
`helm install` this repo doesn't automate, after which
`kubectl apply -f argocd/root-app.yaml` hands control to ArgoCD. One value
also has to be hand-edited before the ALB controller Application will work:
`REPLACE_WITH_ACCOUNT_ID` in
`argocd/apps/platform/aws-load-balancer-controller.yaml`, because a static
GitOps manifest can't reach into Terraform state to read the account ID or
role ARN itself. Each section below says plainly what's built vs. what's
still just well-reasoned intent.

---

## 1. Managed node groups over self-managed nodes or Fargate

**Decision:** `eks.tf` uses `eks_managed_node_groups` (SPOT, `t3.small`,
AL2023 AMI) — real EC2 instances that AWS provisions and patches through a
managed node group, not a self-managed Auto Scaling Group and not Fargate
profiles. *(Implemented.)*

**Alternatives considered:**
- **Fargate** — no nodes to manage, pay per pod per second.
- **Self-managed ASG** — a launch template + Auto Scaling Group you wire up
  yourself, full control over the AMI and bootstrap process.

**Why managed node groups:**
Fargate bills per vCPU/GB-second per pod, rounded up, with no bin-packing
across pods — for a demo running several small services plus sidecars and
controllers, that's typically *more* expensive than two small SPOT EC2
boxes sharing the cost. Fargate also doesn't run DaemonSets, which rules out
node-level tooling this platform wants (node-exporter for Prometheus, and
eventually Istio's per-node components), and pod startup on Fargate is
noticeably slower (a new ENI has to attach) — that undercuts the point of an
HPA/load-test demo, which should show pods scaling up snappily.

A self-managed ASG gives full control (custom AMI, custom kubelet flags) but
you own AMI patch pipelines, node draining during upgrades, and wiring node
identity into the cluster — all things a managed node group already
automates (rolling replacement by launch-template version, cordon/drain on
update, integration with cluster-autoscaler). For a project meant to
demonstrate platform judgment, not AMI-pipeline maintenance, that overhead
buys nothing.

**At scale:** replace the static node group with Karpenter (or run both) —
Karpenter reacts to unschedulable pods in seconds and diversifies
instance types/AZs automatically, where a managed node group is a fixed
instance-type list per group. Self-managed nodes still rarely win even at
scale; the AMI/patch automation a managed node group gives you for free
keeps paying off.

---

## 2. IRSA over node IAM roles

**Decision:** `irsa.tf` creates an IAM role trusted only by the OIDC
federated identity of one specific ServiceAccount
(`system:serviceaccount:kube-system:aws-load-balancer-controller`), with
`StringEquals` conditions on both the `sub` and `aud` claims — rather than
attaching an `elasticloadbalancing:*`-style policy to the shared node
instance role. *(The IAM role/policy/trust-policy plumbing is implemented;
the ALB controller pod that would assume it is not deployed yet.)*

**Alternatives considered:**
- **Node IAM role** — simplest, zero extra Terraform.
- **EKS Pod Identity** — the newer `aws_eks_pod_identity_association`
  mechanism. Notably, `eks.tf` already enables the `eks-pod-identity-agent`
  cluster addon, but nothing in this repo creates a pod identity
  association — the actual ALB controller role is still wired through
  classic OIDC/IRSA in `irsa.tf`. That's a deliberate, slightly
  inconsistent-looking choice: IRSA is what nearly every existing Helm
  chart's IAM documentation assumes, is portable to older EKS versions, and
  is the pattern worth understanding first. The addon is enabled mostly for
  forward compatibility; migrating this role to a pod identity association
  later is a small, contained change.
- **kube2iam / kiam** — self-hosted IMDS interception to hand out per-pod
  credentials. Predates IRSA, adds a whole system to run and secure, and is
  effectively obsolete now that IRSA and Pod Identity are native.

**Why IRSA:** least privilege at the pod, not the node. With a node IAM
role, *every* pod scheduled on that node — including an unrelated app pod —
can reach the instance metadata service and use whatever the node's
instance profile allows. Stack that on top of nodes already sitting in
public subnets (see §5) and a compromised pod's blast radius gets
uncomfortable fast. IRSA's trust-policy conditions mean this specific role
is assumable by exactly one ServiceAccount in one namespace: not "any pod
on this node," not even "any pod in `kube-system`."

**At scale:** every controller or app that needs AWS access (external-dns,
cluster-autoscaler, cert-manager's Route53 solver, an app pod reading from
S3) gets its own narrowly-scoped role the same way, migrating to Pod
Identity associations as tooling catches up, and node roles carry nothing
beyond what kubelet itself needs (ECR pull, CNI, CloudWatch logs).

---

## 3. ArgoCD / GitOps (pull) over push-based CD from CI

**Decision (fully written, not yet running):** run ArgoCD in-cluster,
pulling manifests/Helm releases from a Git repo, instead of having CI
(e.g. GitHub Actions) `kubectl apply` / `helm upgrade` directly against the
cluster at the end of a pipeline. `argocd/root-app.yaml` is the app-of-apps
root — the *one* manifest ever applied by hand
(`kubectl apply -n argocd -f argocd/root-app.yaml`, after ArgoCD itself is
installed, which nothing here automates yet). From there it watches
`argocd/apps/` recursively and self-manages: every file ArgoCD finds
becomes an Application it creates, syncs, prunes, and heals.

Sync-wave annotations enforce dependency order, and they're concrete, not
theoretical: `argocd/apps/platform/namespaces.yaml` lands at wave `-10`
(the `apps` namespace needs its `istio-injection: enabled` label attached
*at creation*, which a bare `CreateNamespace=true` sync option can't do).
`cert-manager`, `istio-base`, `kube-prometheus-stack`, `metrics-server`, and
the `aws-load-balancer-controller` all land at wave `0`. Two Applications
that depend on CRDs those installs create — `cert-manager-issuer` (the
self-signed `ClusterIssuer`) and `istiod` — land at wave `1`, and
`istio-mesh-policy` (the mesh-wide `PeerAuthentication: STRICT`) waits for
wave `2` since it needs istiod actually running to enforce anything. All 10
microservice Applications sit at wave `10`, after every platform dependency
is healthy.

**Alternatives considered:**
- **Push-based CD** — CI holds a kubeconfig or an IAM role that can reach
  the cluster's API and applies changes itself.
- **Hybrid** — CI builds and pushes an image, then hits a webhook to
  trigger deployment.

**Why pull (GitOps):**
- *Credential exposure.* Push-based CD means a third-party SaaS runner
  holds live cluster-reaching credentials. This cluster's API endpoint is
  public (`cluster_endpoint_public_access = true`, chosen for laptop
  access without a bastion — see §5), so a leaked CI credential is a direct
  path in. ArgoCD instead runs inside the cluster and only needs *read*
  access to Git — a far lower-value credential to leak. Nothing external
  ever pushes into the cluster.
- *Drift detection.* ArgoCD continuously diffs live state against Git and
  can surface or auto-heal drift — someone `kubectl edit`-ing a Deployment
  by hand during an incident gets caught. A push pipeline only reconciles
  the moment it runs; manual changes persist silently until the next
  deploy happens to touch the same resource.
- *Git as the audit log.* Every change is a reviewed commit; rollback is
  `git revert`, not "hope someone remembers the last good CI run."

**What it costs:** ArgoCD is itself another stateful system to run,
monitor, and upgrade, and the feedback loop is asynchronous — a merge
doesn't deploy immediately, it deploys on ArgoCD's next sync (or a
webhook-triggered one), which surprises engineers used to a pipeline that
finishes with "deployed."

**At scale:** the app-of-apps pattern already used here scales to one
Application per service/team as-is; the next additions would be ArgoCD
Projects to scope which repos/namespaces each team can touch (everything
currently uses the `default` project), and sync-failure notifications wired
to Slack instead of relying on someone watching the UI.

---

## 4. SPOT instances and what breaks when a node is reclaimed

**Decision:** `variables.tf` defaults `node_capacity_type = "SPOT"` on
`t3.small`, `min=2 / desired=2 / max=4`. *(Implemented.)*

**Alternatives considered:** `ON_DEMAND` (the variable is validated to only
accept `ON_DEMAND` or `SPOT`), or a mixed policy — an on-demand baseline
plus SPOT burst capacity.

**Why SPOT:** for a sandbox that isn't serving real traffic, SPOT typically
runs 60–90% cheaper than on-demand for the same instance size. `t3.small`
is a low-demand, widely available instance type, so interruption risk is
comparatively low — a reasonable bet for a cluster that isn't running
24/7 anyway.

**What actually breaks when a node is reclaimed (stated plainly, not
hand-waved):**
- AWS gives a 2-minute interruption notice via instance metadata and an
  EventBridge event. Kubernetes doesn't act on that automatically — the
  managed node group replaces the *capacity* (the ASG side), but nothing in
  this repo watches the interruption notice and proactively drains pods
  (that's the job of the AWS Node Termination Handler, or Karpenter's
  built-in interruption handling — neither is deployed here). Without it,
  the node just disappears; pods on it are only rescheduled once the node
  is marked `NotReady` and the default pod-eviction-timeout elapses. That's
  a real multi-minute gap, not a rounding error.
- Anything with local state on that node's disk — `emptyDir` data, a bare
  pod not backed by a ReplicaSet, a single-replica StatefulSet without a
  properly attached EBS volume — is just gone. Nothing in this repo runs
  stateful workloads yet, so today the blast radius is "stateless pods take
  ~30–90s to reschedule," but it's the first thing that breaks the day
  someone adds a single-replica database pod without thinking about it.
- In-flight requests to pods on the reclaimed node get connection resets
  until Service endpoints update (and, once one exists, until the load
  balancer stops routing to the dead target). Readiness probes and
  PodDisruptionBudgets matter here and aren't configured in this repo yet.
- SPOT capacity can simply run dry for a given instance type in a given AZ.
  `max_size=4` gives headroom, but if `t3.small` SPOT capacity is
  unavailable in the AZ the ASG lands in, the node group won't scale no
  matter what HPA wants — a reason production wouldn't pin a single
  instance type.

**At scale:** run node termination handling (NTH or Karpenter), diversify
SPOT across multiple instance types and AZs rather than one type, set
PodDisruptionBudgets and real readiness/liveness probes everywhere, and
keep a small `ON_DEMAND` baseline node group for anything that genuinely
can't tolerate a 2-minute-notice eviction.

---

## 5. Why NAT Gateway is disabled, and what production does differently

**Decision:** `enable_nat_gateway = false` by default (`variables.tf`), so
worker nodes sit in **public** subnets with public IPs
(`local.node_subnets` in `vpc.tf`) instead of private subnets egressing
through a NAT Gateway. *(Implemented — and the code supports flipping this
with a single variable; `vpc.tf` and `eks.tf` both branch on it.)*

**Why:** a NAT Gateway bills hourly (roughly $0.045–0.06/hr depending on
region, ~$32–45/month) plus per-GB data processing, *whether or not a
single byte crosses it*. For a cluster meant to run for a few hours around
an interview conversation, that's the single largest "always-on" line item
after the control plane itself, for essentially zero actual usage most of
the time.

**The trade-off, stated honestly, not minimized:** nodes in public subnets
get public IPs — which, since AWS's February 2024 pricing change, aren't
even free anymore ($0.005/hr per address, so this isn't a pure win, just a
cheaper one) — and are directly *reachable* from the internet on any port a
security group allows. The security group the managed node group ships
with is reasonably tight (cluster-to-node and node-to-node rules, not "open
to the world"), but "worker node has a routable public IP" is a materially
larger attack surface than "worker node is unreachable except outbound via
NAT," and it is not a pattern to copy into a real production environment
without deliberately re-deciding it.

**What production would do differently:**
- Set `enable_nat_gateway = true` — nodes move to private subnets, pod
  egress goes out through NAT. `vpc.tf` currently pins
  `single_nat_gateway = true` even when NAT is enabled (one NAT for all
  three AZs, not one per AZ) — cheaper, but a single point of failure for
  every AZ's egress; a production build would weigh that trade-off
  explicitly rather than inherit the sandbox default.
- Restrict `cluster_endpoint_public_access` (currently `true`, for laptop
  convenience without a bastion) to `false` or a specific CIDR allowlist.
- Reach nodes for debugging via SSM Session Manager rather than relying on
  public reachability.
- Add VPC endpoints (S3, ECR, STS) to cut NAT data-processing costs further
  even with NAT enabled.

---

## 6. Remote state in S3 + DynamoDB locking

**Decision:** `bootstrap/` stands up a versioned, SSE-AES256-encrypted,
fully-public-access-blocked S3 bucket, plus a `PAY_PER_REQUEST` DynamoDB
table, purely to hold and lock `terraform/`'s state. It's run once, with
*local* state, before the main stack exists — `bootstrap/` has no backend
block of its own, because you can't store the state for the thing that
creates your state storage inside that same storage. *(Implemented.)*

**Alternatives considered:** local state only (Terraform's default, and
what `bootstrap/` itself intentionally uses); a managed backend like
Terraform Cloud/HCP (no AWS resources to run yourself).

**Why S3 + DynamoDB:** local state has two failure modes that matter even
for a solo project worked from more than one machine. First, nothing
enforces exclusivity — two `terraform apply` runs against the same state
can both read "current," both write back, and the loser's write silently
clobbers the winner's. That's corruption, not a lint warning. Second, local
state isn't shared or durable — lose the laptop, lose the record of every
resource Terraform believes it owns, and the next `apply` either fails to
find existing resources or tries to recreate them. The DynamoDB table
exists for exactly one reason: its `LockID` hash-key conditional write
gives Terraform a mutex, so a second `apply` blocks with "state is locked"
instead of racing the first. S3 versioning is the rollback path if a bad
apply corrupts state anyway.

**Why not Terraform Cloud:** a reasonable alternative, arguably less to run
yourself — but the point of this repo is demonstrating AWS-native infra
skills, and hand-rolling the backend with S3 + DynamoDB is the more common
pattern in AWS-only shops, and shows understanding of *why* the lock table
exists rather than just that a SaaS handles it invisibly.

**At scale:** same mechanism, harder guardrails — a bucket policy
restricting writes to CI's role only (nobody applies from a laptop), a
separate state key/workspace per environment, and splitting into smaller
state files per layer (network, cluster, platform add-ons) so a bad apply's
blast radius doesn't span the whole account.

---

## 7. One generic Helm chart + 10 values files, instead of 10 charts

**Decision (implemented):** `charts/microservice/` is one parameterized
chart (Deployment, Service, HPA, Ingress, ServiceAccount, ServiceMonitor,
Istio VirtualService/DestinationRule — all templated and mostly opt-in) and
`charts/values/svc-01.yaml` through `svc-10.yaml` are 10 thin values files,
one per demo service, rather than 10 independent charts.

**Alternatives considered:** an independent chart per service (its own
`templates/` directory each); or a single chart with no per-service
customization at all.

**Why one chart + many values files:** the 10 demo services (`api-gateway`,
`auth-service`, `catalog-service`, `cart-service`, `order-service`,
`payment-service`, `notification-service`, `search-service`,
`user-service`, `inventory-service`) share the same Kubernetes shape — one
Deployment, one Service, optionally an HPA, Ingress, and Istio sidecar. 10
separate charts would mean 10 copies of the same template logic, so a fix
like "every service needs `readOnlyRootFilesystem`" becomes 10 PRs (or a
scripted find-and-replace, its own bug source) instead of one. The values
files stay genuinely thin because the chart's defaults
(`charts/microservice/values.yaml`) are deliberately conservative —
Ingress, HPA, and the Istio sidecar are all `enabled: false` by default —
so most of the 10 values files are a handful of comment lines plus a
`nameOverride`, and the interesting ones are interesting *because* they
override something: `svc-01.yaml` (`api-gateway`) is the only one with
Ingress on (the one public entry point) and pairs it with an HPA;
`svc-08.yaml` (`search-service`) gets the second and only other HPA (its
query load is the most naturally bursty of the 10, making it the clearest
autoscaling demo); `svc-01.yaml` and `svc-06.yaml` (`payment-service`) are
the only two with the Istio sidecar on. A reviewer scanning a values file
sees exactly what makes that service different, not a wall of boilerplate.

**What it costs:** a generic chart's templates inevitably grow
`{{- if }}` branches for the services that don't fit the common shape. This
chart already has four independent toggles (`ingress.enabled`,
`hpa.enabled`, `istio.enabled`, `serviceMonitor.enabled`) plus a
`readOnlyRootFilesystem`-driven volume mount — still readable at that size,
but it's a real, present-tense example of the trade-off, not a hypothetical
one. Past a certain amount of divergence (one service needing a second
container, a non-HTTP probe, an extra volume), the "generic" chart becomes
an unreadable maze of conditionals — worse than just giving that one
service its own chart. The judgment call: while services stay structurally
similar, one chart wins; the moment a service's needs genuinely diverge (a
CronJob instead of a Deployment, say), split it out rather than bolt on
more conditionals.

**At scale:** this is exactly what Helm library charts are for — promote
the common templates into a library chart each service's thin chart
depends on, getting per-service charts back (their own `Chart.yaml`, their
own release lifecycle) without duplicating template YAML.

---

## 8. Istio on t3.small: sidecar memory overhead — the honest version

**Decision (implemented as code — Istio's control plane + 2 of 10 sidecars
are fully defined, not yet running against a live cluster):**
`argocd/apps/platform/istio-base.yaml` and `istiod.yaml` install Istio's
CRDs and control plane; `argocd/manifests/istio/peer-authentication.yaml`
turns on mesh-wide `STRICT` mTLS for the `apps` namespace. Only 2 of the 10
services — `api-gateway` (`svc-01.yaml`) and `payment-service`
(`svc-06.yaml`) — actually opt into the sidecar (`istio.enabled: true`);
the other 8 explicitly opt back *out* of the namespace-wide injection with
`sidecar.istio.io/inject: "false"` (see `deployment.yaml`'s template — the
`apps` namespace itself carries `istio-injection: enabled`, so opting out
has to be explicit per pod, not just "don't turn it on"). All of this runs
on the same `t3.small` (2 vCPU, 2 GiB RAM) SPOT node group provisioned for
everything else — there's no dedicated, larger node pool for mesh
workloads, and deliberately no `istio-ingressgateway` either (north-south
traffic stays on the ALB; a second LoadBalancer Service for an ingress
gateway would just be another ELB AWS bills for hourly with no traffic
reason to exist — see `istiod.yaml`'s own comment on this).

**This is genuinely tight, and it's worth saying plainly instead of
glossing over it.** Istio's Envoy sidecar defaults to roughly 100m CPU /
128Mi memory requested per injected pod — on a `t3.small`, that default
alone is close to the entire per-pod CPU budget once kubelet, kube-proxy,
and the CNI have taken their share. That's exactly why
`istiod.yaml`'s `global.proxy.resources` overrides the sidecar default down
to 10m CPU / 64Mi requested (100m / 128Mi limit) — a real, deliberate
mitigation already baked into this repo's config, not a hypothetical one.
Even scaled down, every meshed pod still carries a second full container:
Envoy's own process overhead, plus istiod itself budgeted at 50m/128Mi
requested. That's exactly why only 2 of 10 services carry a sidecar instead
of the whole `apps` namespace inheriting one by default — `api-gateway`
because it's the edge (worth demonstrating retries/timeouts on the one path
every request crosses) and `payment-service` because it's the most
failure-sensitive internal hop (a stuck upstream shouldn't hang a payment
call indefinitely). Meshing all 10 services on this node group, even with
the trimmed sidecar footprint, would leave little headroom once
kube-prometheus-stack, cert-manager, the ALB controller, and istiod itself
are also running on the same 2 nodes.

**Why accept it anyway for this project:** the goal is to demonstrate mTLS
and resilience *mechanics* for an interview conversation, not to run
production traffic. Two mesh-injected services with real
`PeerAuthentication: STRICT` mTLS, retries, timeouts, and outlier-detection
circuit breaking (see `charts/microservice/templates/virtualservice.yaml`
and `destinationrule.yaml`) is enough to show `istioctl proxy-status` and a
working policy, without sizing nodes to comfortably fit a cluster-wide mesh
and blowing the cost budget this whole design is built around.

**What production (or a more serious demo) would do differently:**
- Move to **Istio's ambient mesh mode** — no per-pod sidecar, a shared
  per-node `ztunnel` instead. This is the specific feature Istio built to
  solve exactly this sidecar-tax problem.
- Or size nodes for the mesh (`t3.medium`/`large`, an `ON_DEMAND` baseline)
  and only inject sidecars into the services actually being demoed, not
  mesh-wide.
- Or, in a genuinely cost-constrained sandbox, skip the sidecar model
  entirely and demonstrate mTLS/traffic-splitting with a lighter proxy
  (Linkerd) or an Ingress-level canary via ALB weighted target groups —
  and say plainly in the interview why that trade-off was made.
