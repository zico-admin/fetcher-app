# 0002 — The default-service-account org policy belongs on the folder

- Status: accepted
- Date: 2026-10-06
- Supersedes: decision 3 in `docs/PLAN.md` ("enforced per project, not org-wide")

## Context

§8.12 calls the automatic `roles/editor` grant to the default compute service
account the single most important GCP security fact. The plan enforced
`constraints/iam.automaticIamGrantsForDefaultServiceAccounts` at the project
level, to keep other projects in `ogbonna.net` unaffected.

It did not work. After the first bootstrap apply, both projects had this:

```
roles/editor  serviceAccount:582048530189-compute@developer.gserviceaccount.com
roles/editor  serviceAccount:781463442713-compute@developer.gserviceaccount.com
```

The policy was enforced, and `gcloud org-policies describe` confirmed
`enforce: true` on the dev project. It simply arrived too late — by about five
minutes, from the dev project's own audit log:

| Time (2026-10-06) | Event |
|---|---|
| 01:00:22 | Project creation enables services. No `serviceIds` recorded: the single `EnableService` calls, compute among them, for the network that exists momentarily |
| 01:03:54 | `cloudresourcemanager`, `orgpolicy`, `iam` enabled — `dev_bootstrap_services` |
| **01:05:13** | **Policy enforced.** The default account has held editor for five minutes |

## Why a project-level policy cannot work

Two facts combine:

1. The policy only affects service accounts created **after** it is enforced.
2. `auto_create_network = false` — deliberate, so no default VPC exists — makes
   the provider create the default network and then delete it. From the provider
   schema: *"the network will exist momentarily."*

A network requires `compute.googleapis.com`. Enabling compute mints the default
compute service account and grants it editor. All of that happens **during
project creation**, before a project-scoped policy can exist, because the policy
needs the project as its parent.

So the good practice (no default VPC) is what guarantees the bad outcome, and
the policy can never win that race at project scope.

## Decision

Enforce the constraint on the `fetcher` folder, created before any project, and
make the dev project's creation depend on it. Inheritance applies the policy at
the instant a project is created.

The seed project remains the one exception: setting a folder policy is an API
call that must bill quota to a project, so seed has to exist first. Its default
account is remediated rather than prevented.

For both existing projects, `google_project_default_service_accounts` with
`action = "DEPRIVILEGE"` strips editor. `restore_policy = "NONE"`, because an
undo that re-grants editor is not an undo worth having.

## Consequences

- Rebuilt from an empty org, dev and prod never hold a privileged default
  account at any instant.
- Blast radius is unchanged from the original intent: the fetcher folder only,
  not the organization.
- Seed keeps a default account, now without editor. It runs no workloads.
- One more ordering dependency in bootstrap, documented in `projects.tf`.

## What this cost, and the lesson

Two projects were created with an over-privileged account, found by reading the
live IAM policy rather than trusting the apply output. "The policy is enforced"
and "the policy protected anything" are different claims, and only the second
one matters.

Verify with:

```bash
gcloud projects get-iam-policy ogbn-fetcher-dev \
  --flatten="bindings[].members" --filter="bindings.role:roles/editor" \
  --format="value(bindings.members)"
```

Empty output is the goal.
