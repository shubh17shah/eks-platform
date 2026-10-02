---
name: Feature request
about: Propose a new capability or a change to an existing design decision
title: "[feature] "
labels: enhancement
assignees: shubh17shah
---

## What are you proposing

<!-- The capability, not the implementation yet — e.g. "support a
     production-like profile with NAT enabled" rather than "add an
     if-statement to vpc.tf". -->

## Which layer does this touch

- [ ] `terraform/` / `bootstrap/` (infrastructure)
- [ ] `charts/` (the generic chart or per-service values)
- [ ] `argocd/` (Applications, platform add-ons, sync ordering)
- [ ] Something outside this repo (application code/CI belongs in
      [devsecops-pipeline](https://github.com/shubh17shah/devsecops-pipeline)
      — open the issue there instead)

## Why

<!-- What's the gap today? If this conflicts with an existing trade-off
     documented in docs/DESIGN-DECISIONS.md, name the section and explain
     why it should change. -->

## Cost impact

<!-- Does this add a billable AWS resource, change instance types/counts,
     or otherwise move the needle on docs/COST.md? Rough order of
     magnitude is fine (e.g. "+$32/month for a NAT Gateway"). -->

## Alternatives considered

<!-- Optional, but useful — especially if you already ruled something out. -->
