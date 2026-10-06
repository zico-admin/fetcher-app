# Fetcher

Where to eat and what to order in a city you don't know, for travellers eating to
a health goal. Seed city: Washington, DC.

The full specification is [FETCHER-BRIEF.md](FETCHER-BRIEF.md). The build plan,
including every decision the brief left open, is [docs/PLAN.md](docs/PLAN.md).

**Status: Milestone 0.** Infrastructure only — there is no application yet.

## Ground rules

1. Every Google Cloud resource is created by Terraform. Nothing is clicked in the
   console or created with `gcloud`. The sole exception is `infra/bootstrap`,
   which resolves the chicken-and-egg of creating the bucket that holds state.
2. No service account keys. CI authenticates with Workload Identity Federation.
3. Infrastructure is reviewed as a plan on a pull request, and applied by CI
   behind a human approval.

## Layout

```
infra/bootstrap/    applied once, by hand, then its state moves into GCS
infra/modules/      reusable, no provider blocks, nothing hardcoded
infra/envs/dev/     one directory per environment, one state file per directory
.github/workflows/  infra.yml (plan on PR, apply on main)
docs/               plan, runbooks, decision records
```

## Getting started

Read [docs/runbooks/bootstrap.md](docs/runbooks/bootstrap.md). It covers tooling,
credentials, the one local apply, the state migration, and how to verify no key
exists anywhere.

For how CI authenticates and how to add a permission when an apply is denied, see
[docs/runbooks/ci.md](docs/runbooks/ci.md).

## Projects

| Project | Purpose |
|---|---|
| `ogbn-fetcher-seed` | Terraform state, Workload Identity Federation, CI service accounts, budget |
| `ogbn-fetcher-dev` | Workloads |

Region is `us-east4`. The monthly budget is $50, alerting at 50 / 90 / 100 percent
— which emails you, and does not stop spending.

---

Fetcher gives food suggestions, not medical advice.
