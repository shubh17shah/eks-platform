# Contributing

This repo is Terraform + a Helm chart + ArgoCD Applications — there's no
application code to build or test here (that's
[`devsecops-pipeline`](https://github.com/shubh17shah/devsecops-pipeline),
see [apps/README.md](apps/README.md)). "Contributing" mostly means: change
some `.tf`/`.yaml`, prove it's still valid, open a PR.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
  (the version this repo is developed and CI-linted against; the code
  itself only requires >= 1.5 per `terraform/providers.tf` and
  `bootstrap/main.tf`, but 1.9+ avoids some fmt/validate output quirks in
  older releases)
- `kubectl` (for `make kubeconfig` / `make status`, and for rendering
  Kubernetes manifests mentally while reading the Helm chart)
- [Helm](https://helm.sh/docs/intro/install/) 3.x (for `helm lint` /
  `helm template` against `charts/microservice`)
- AWS CLI v2 — only needed once you're touching real infrastructure
  (`make plan`/`make up`/`make down`/`make destroy-check`); not needed for
  the local validation loop below
- [tflint](https://github.com/terraform-linters/tflint) and
  [yamllint](https://yamllint.readthedocs.io/) — both optional locally
  (`make lint` degrades gracefully if `tflint` is missing), but both run
  in CI, so install them if you want to catch what CI will catch before
  you push

## Local validation loop

Everything below works **without AWS credentials**. Run it before opening
a PR — it's the same set of checks `.github/workflows/terraform-ci.yml`
runs, just faster to iterate on locally:

```bash
# Format Terraform in place (both roots: bootstrap/ and terraform/)
make fmt

# Syntax/config validation — no AWS credentials, no state, no network
# access to AWS (it does need to download providers once)
make validate

# Static analysis, if tflint is installed
make lint

# Lint the Helm chart against every per-service values file
for f in charts/values/*.yaml; do
  helm lint charts/microservice --values "$f" || exit 1
done

# Lint plain YAML (argocd/ and charts/values/ — NOT
# charts/microservice/templates/, which is Go templates, not YAML)
yamllint -c .yamllint.yml argocd/ charts/values/
```

If you only have five minutes: `make validate` is the single command that
catches the most common mistake (a Terraform syntax error) without
touching AWS at all.

## The cost warning, repeated here on purpose

`make up` runs `terraform apply` against a real AWS account and **starts
a billing clock the instant it finishes** — $0.10/hour for the EKS control
plane alone, no free tier, ~$0.13/hour all-in for this config (see
[docs/COST.md](docs/COST.md)). It bills whether or not anything is
running on the cluster, and it does not stop itself.

If you run `make up` to test a change against a live cluster:

- **`make down` is not optional.** Run it the moment you're done, every
  time, even if the apply "didn't fully work" or you're just stepping
  away for a few minutes.
- Follow it with `make destroy-check` — it queries AWS directly for any
  EKS cluster, tagged EC2 instance, load balancer, or NAT gateway left in
  the region, independent of what Terraform *thinks* it destroyed.
- If you manually `kubectl apply`'d or `helm install`'d anything outside
  Terraform (an Ingress, a LoadBalancer Service), delete that *before*
  `make down` — Terraform doesn't know about it and won't clean it up,
  and a leftover ALB keeps billing indefinitely.

PRs that only touch `charts/` or `argocd/` content don't need a live
cluster at all — `helm lint`/`helm template` and `yamllint` cover them
without spending a cent.

## Branch naming

`<type>/<short-description>`, matching the commit-type prefixes below —
e.g. `fix/alb-controller-irsa-trust`, `feat/add-audit-service-hpa`,
`docs/cost-breakdown-update`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <summary>

[optional body — the "why", not a restatement of the diff]
```

`type` is one of `feat`, `fix`, `docs`, `refactor`, `chore`, `ci`, `test`.
`scope` is usually a top-level directory (`terraform`, `charts`, `argocd`,
`bootstrap`) or a service name (`api-gateway`). Example:

```
fix(terraform): scope ALB controller IRSA trust to kube-system SA only

Previously trusted the whole OIDC provider with no subject condition,
which meant any ServiceAccount in any namespace could assume the role.
```

## What CI checks on a PR

`.github/workflows/terraform-ci.yml` runs on every PR (and on pushes to
`main`) that touches `terraform/**`, `charts/**`, or `argocd/**`. None of
it needs AWS credentials, so it runs the same for every contributor:

- **`terraform` job** — `terraform fmt -check -recursive`,
  `terraform init -backend=false`, `terraform validate`, `tflint`
  (against both `terraform/` and `bootstrap/`)
- **`helm` job** — `helm lint charts/microservice` against every file in
  `charts/values/`, one matrix entry per service, so a values file that
  breaks the chart for just one service fails loudly instead of getting
  masked by the other 11 passing
- **`yaml` job** — `yamllint` over `argocd/` and `charts/values/`
  (`charts/microservice/templates/` is deliberately excluded — it's Go
  template syntax wrapped in YAML-like indentation, not valid YAML on its
  own, and no linter should try to parse it as such)

A PR that only changes `docs/`, `README.md`, or this file won't trigger
the workflow at all (see the `paths:` filter) — there's nothing in those
for `terraform`/`helm`/`yamllint` to check.
