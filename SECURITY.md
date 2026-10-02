# Security Policy

## Reporting a vulnerability

Please **do not open a public GitHub issue** for a suspected security
vulnerability — that discloses it to everyone before it's fixed.

Instead, use GitHub's private vulnerability reporting for this repo:

1. Go to the **Security** tab → **Advisories** → **Report a vulnerability**
   (or go directly to
   `https://github.com/shubh17shah/eks-platform/security/advisories/new`).
2. Describe the issue: which file/resource it's in, what the impact is
   (e.g. "overly broad IAM trust policy", "secret committed in plaintext",
   "state bucket publicly readable"), and, if you have one, how to
   reproduce or verify it.

This is a single-maintainer portfolio project, not a company with an SLA —
expect an initial response within a few days, not hours. There's no bug
bounty.

## Supported versions

This repo doesn't cut releases or maintain version branches — there is one
line of development, `main`. Security fixes land there. If you're running
a fork or an old clone, the only "supported version" is whatever `main`
currently looks like; please rebase/pull before reporting something that
might already be fixed.

## Security posture of this repo

This section exists because the repo *is* infrastructure config, so its
own handling of secrets and access is part of what "secure" means here —
not just whether the code has bugs.

- **No secrets in git.** `.gitignore` excludes `*.tfvars`, `*.tfstate`,
  anything matching `*credential*`/`*secret*`, kubeconfig, and common key
  file extensions. `terraform/backend.tf` (the file with a real S3 bucket
  name) is generated locally from `terraform/backend.tf.example` and never
  committed — only the `.example` template is tracked. The one value that
  does look sensitive but isn't — the AWS account ID pasted into
  `argocd/apps/platform/aws-load-balancer-controller.yaml` — is a 12-digit
  identifier, not a credential; it's required in an IAM role ARN and
  disclosing it grants no access on its own.
- **State is encrypted at rest.** The S3 backend bucket created by
  `bootstrap/main.tf` has SSE (AES256) enabled
  (`aws_s3_bucket_server_side_encryption_configuration`), versioning
  enabled, and all four public-access-block settings on
  (`aws_s3_bucket_public_access_block`). Terraform state routinely
  contains plaintext secrets (DB passwords, generated keys) pulled from
  provider APIs — treat a copy of it with the same care as a credentials
  file if you ever download one locally.
- **IRSA for pod-level least privilege.** `terraform/irsa.tf` creates an
  IAM role trusted only by one specific Kubernetes ServiceAccount
  (`system:serviceaccount:kube-system:aws-load-balancer-controller`) via
  the cluster's OIDC provider — not by the node's instance role. Without
  this, every pod on a node inherits whatever IAM permissions the node
  role has, so a single compromised pod (or a container-escape bug in any
  of the 12 microservices) would get the blast radius of the *entire node
  role*, not just what that one pod needs. Only the ALB controller has an
  IRSA role today, because it's the only workload that calls the AWS API;
  the 12 telemetry services don't, and get no IAM role at all.
- **Pod/container hardening is chart-wide, not opt-in.**
  `charts/microservice/values.yaml` defaults every release to
  `runAsNonRoot: true`, a dropped `ALL` capability set,
  `allowPrivilegeEscalation: false`, and `readOnlyRootFilesystem: true` —
  so a new service added to `charts/values/` starts hardened by default
  instead of needing someone to remember to lock it down later.
- **mTLS between services that have the sidecar.** `api-gateway` and
  `auth-service` run the Istio sidecar with mesh-wide `STRICT` mTLS
  (`argocd/manifests/istio/peer-authentication.yaml`); the other 10
  services talk over plain ClusterIP without it — a deliberate
  cost/complexity trade-off on `t3.small` nodes, documented in
  [docs/DESIGN-DECISIONS.md](docs/DESIGN-DECISIONS.md), not an oversight.

## If credentials leak

This applies to anyone operating a real deployment of this repo (the
sandbox AWS account, not the public GitHub repo itself):

1. **Rotate immediately** — deactivate the leaked AWS access key
   (`aws iam update-access-key --status Inactive`) or delete it outright,
   and rotate any downstream secret it could have touched (DB passwords,
   API tokens stored as Kubernetes Secrets).
2. **Check CloudTrail** for any API activity on the key between when it
   was issued and when it was deactivated — look specifically for IAM
   changes, new access keys, or EC2/EKS resources you didn't create.
3. **Assume state may be exposed too.** If the leaked credential could
   read the S3 state bucket, treat every value in `terraform.tfstate` as
   compromised — anything Terraform wrote there (e.g. generated
   passwords) needs rotating, not just the credential itself.
4. **Re-run `make destroy-check`** (or the equivalent manual AWS CLI
   checks in the Makefile) against the account to confirm nothing
   unexpected was created while the credential was live.
5. **Never commit the leaked value anywhere**, including in the incident
   writeup — reference it by name/ARN, not by pasting the key material,
   even into a private issue or commit message.
