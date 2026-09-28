# apps/

There is no application source in this repo. This is the **infrastructure
and GitOps repo** — Terraform, the Helm chart, and ArgoCD Applications. It
does not build or hold any container image's code.

## Where the application lives

The `telemetry-service` Node.js/Express source — the one image every
microservice in this platform runs (see `charts/microservice/values.yaml`)
— lives in a separate repo:

**[github.com/shubh17shah/devsecops-pipeline](https://github.com/shubh17shah/devsecops-pipeline)**

That repo's CI tests, SAST-scans, builds, Trivy-scans, and SBOM-signs the
image, publishes it to `ghcr.io/shubh17shah/telemetry-service`, and then
opens/pushes a commit here that bumps `image.tag` in
`charts/microservice/values.yaml`. This repo deploys whatever tag is
committed here — ArgoCD reads this repo, not the app repo, and never talks
to CI directly. That handoff — CI publishes an image and proposes a tag,
this repo's git history decides what actually runs — is the GitOps
boundary between the two repos.

## Why the split exists

- **Different rate of change.** Application code changes on every feature
  and bugfix; infrastructure (VPC, EKS, IRSA, the Helm chart's shape)
  changes far less often. Mixing them means every app commit touches an
  infra repo and vice versa.
- **Different reviewers.** App changes want reviewers who know the Node.js
  service; infra changes want reviewers who know Terraform/Kubernetes/cost.
  One repo per concern keeps CODEOWNERS and review focus honest.
- **Different blast radius.** A bad app commit should, at worst, break one
  image build. It should never be able to touch Terraform state, IRSA
  roles, or ArgoCD's own sync behavior — which is possible by construction
  only if the app's CI has no path to those files.
- **The cluster never trusts CI, it only trusts git.** ArgoCD pulls from
  this repo; nothing ever pushes into the cluster from a pipeline. Keeping
  application CI in its own repo, with write access to exactly one field
  here (an image tag bump, ideally via PR), keeps that boundary real
  instead of theoretical.
