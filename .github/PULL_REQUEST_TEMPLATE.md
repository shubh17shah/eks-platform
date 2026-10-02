## What changed and why

<!-- One or two sentences. Link an issue if there is one. -->

## Scope

<!-- Check whatever applies. -->

- [ ] `terraform/` or `bootstrap/`
- [ ] `charts/` (chart templates and/or per-service values)
- [ ] `argocd/` (Applications or plain-manifest sources)
- [ ] Docs only (`README.md`, `docs/`, this template, etc.)

## Checklist

- [ ] `terraform fmt -check -recursive` passes (run `make fmt` if not, then
      re-check the diff)
- [ ] `terraform validate` passes — `make validate` (works without AWS
      credentials)
- [ ] `tflint` passes, or any findings are explained below
- [ ] `terraform plan` was run against a real backend for this change, and
      the relevant plan output is pasted below (skip only for docs-only or
      comment-only changes — say so if you skip it)
- [ ] `helm lint charts/microservice` passes against every values file this
      change affects (all of `charts/values/*.yaml` if the chart templates
      changed)
- [ ] Cost impact considered — does this add/remove a billable AWS
      resource (ALB, NAT, node, EBS volume, public IP)? If yes,
      `docs/COST.md` is updated to match
- [ ] If this change was tested against a live cluster, teardown was
      verified (`make down` + `make destroy-check` both clean)
- [ ] Docs updated — `README.md`, `docs/DESIGN-DECISIONS.md`, and/or
      `docs/COST.md`, whichever this change actually affects

## `terraform plan` output

<!--
Paste the relevant part of `terraform plan` here (trim anything irrelevant,
but don't cherry-pick away a destroy/replace you'd rather not call attention
to — that's exactly what a reviewer needs to see). If no plan was run,
say why (e.g. "docs only", "chart-only change, no Terraform touched").
-->

```
paste plan output here
```

## Anything a reviewer should look at closely

<!-- IAM policy changes, anything that widens a trust relationship or
     opens a port, anything that changes default replica counts/resource
     requests across all 12 services at once, etc. "None" is a fine answer. -->
