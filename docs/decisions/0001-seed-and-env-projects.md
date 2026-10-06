# 0001 — A seed project separate from environment projects

- Status: accepted
- Date: 2026-10-03
- Supersedes: the brief's "one GCP project" (§4)

## Context

The brief specifies one GCP project holding everything. Bootstrap (§6) then
describes the seed-project pattern approvingly without actually separating one.

Bootstrap creates things with a different lifetime from the workloads: the state
bucket, the Workload Identity pool, and the CI service accounts. Those must
survive any environment, because they are what rebuilds an environment.

## Decision

Two projects now, a third at M5:

| Project | Holds | Applied by |
|---|---|---|
| `ogbn-fetcher-seed` | state bucket, WIF pool, `tf-plan` / `tf-apply`, budget | you, locally, once |
| `ogbn-fetcher-dev` | every workload | CI |
| `ogbn-fetcher-prod` | every workload (M5) | CI |

Both sit in a `fetcher` folder under `ogbonna.net`, so project-scoped org policy
has a single parent to inherit from.

## Consequences

- Destroying or rebuilding dev cannot take out state or the CI identity. With one
  project, `terraform destroy` aimed at dev could delete the bucket holding the
  state that described it.
- Prod is a new project and a new directory, not a second bootstrap.
- Blast radius of a mistaken IAM grant in dev stops at dev.
- Cost: none. Projects are free; the budget filter covers both.
- Price paid: two project ids to keep straight, and bootstrap must be explicit
  about which project each resource belongs to — no provider-level default
  `project`, which is why every resource in `infra/bootstrap` names one.

## Alternatives considered

- **One project, as the brief says.** Simpler, and genuinely fine for a solo
  build. Rejected because the craft goal wins on infrastructure decisions (§2),
  and the seed split is the thing a DevOps interview actually asks about.
- **A separate org or a second billing account.** Real isolation, real overhead,
  no benefit at this size.
