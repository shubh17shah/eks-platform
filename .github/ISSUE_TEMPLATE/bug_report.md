---
name: Bug report
about: Something in the Terraform, Helm chart, or ArgoCD config is wrong or broken
title: "[bug] "
labels: bug
assignees: shubh17shah
---

## What's wrong

<!-- What you expected vs. what actually happened. -->

## Where

<!-- Be specific — this repo has three layers that behave differently:
     - terraform/ or bootstrap/ (a .tf file, a plan/apply error)
     - charts/ (the microservice chart or a specific values file)
     - argocd/ (a specific Application or plain manifest) -->

- File(s):
- Terraform version (`terraform version`), if relevant:
- Helm version (`helm version`), if relevant:

## Steps to reproduce

1.
2.
3.

## Relevant output

<!-- `terraform plan`/`validate` output, `helm lint`/`helm template` output,
     `kubectl describe`/`kubectl logs`, or an ArgoCD sync error — whatever's
     closest to the actual failure. Paste as text in a fenced code block,
     not a screenshot, so it's searchable. Redact account IDs / ARNs you'd
     rather not publish, but say that you did. -->

```
paste here
```

## Was this against a live cluster or just static validation?

<!-- "make validate only, no AWS" vs. "applied with make up, saw this on
     the live cluster" changes how to debug this a lot. -->
