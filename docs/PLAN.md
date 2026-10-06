# Fetcher — Build Plan

Status: **signed off 2026-10-03**. Milestone 0 is written and passes fmt, validate,
tflint and checkov locally; it has not been applied yet.

Source of truth for requirements: [FETCHER-BRIEF.md](../FETCHER-BRIEF.md).
This document records how the brief gets implemented, every decision the brief
left open, and every place this plan deliberately departs from the brief.

---

## 1. Decisions

### 1.1 Answered by you

| # | Decision | Value |
|---|---|---|
| 1 | Human identity | The Google account that applies bootstrap — state bucket IAM, Cloud SQL IAM user, IAP admin, alert and budget email |
| 2 | Projects | New projects created by Terraform: seed + dev (+ prod at M5), in a `fetcher` folder under the organization, on the open billing account. Both ids live in the gitignored `terraform.tfvars` |
| 3 | Org policy | `automaticIamGrantsForDefaultServiceAccounts` enforced on the **fetcher folder**, not org-wide and not per project — see [ADR 0002](decisions/0002-org-policy-at-folder-level.md), a project-scoped policy cannot win the race against project creation |
| 4 | Region | `us-east4` (Vertex AI is the documented exception) |
| 5 | GitHub repo | **Public** — gives the real environment-reviewer gate |
| 6 | GitHub config | Managed by the `integrations/github` Terraform provider in bootstrap |
| 7 | IaC tool | Terraform (not OpenTofu) |
| 8 | CIDRs | dev `10.10.0.0/16`, prod reserved `10.20.0.0/16` |
| 9 | DB access | Migrations via Cloud Run job; IAP bastion behind a flag, off by default |
| 10 | Environments | `dev` through M4; `prod` (own project) added at M5, before real users |
| 11 | Database | PostgreSQL 17, `edition = "ENTERPRISE"` |
| 12 | Budget | $50, alerts at 50/90/100%, created in bootstrap |
| 13 | Domain | `run.app` for now |
| 14 | Twilio | **No account yet** — see §6, this gates M7 |
| 15 | Admin auth | Separate `admin` Cloud Run service behind IAP |
| 16 | Health inputs | Weight, sex, height, age, activity collected; blood sugar is a scoring preference, never a medical mode |
| 17 | Places | Cheaper option — hours from venue sites, rating dropped from scoring |
| 18 | Seed venues | No list exists; selection rules below |
| 19 | Trips | Declared, not detected; second trip ≥ 14 days after the previous one ends |
| 20 | Goal intake | Web only; SMS links to it |
| 21 | Empty state | Never widen silently; say what was found and how far |
| 22 | Stack | Next.js + TypeScript + pnpm, Kysely, `@google-cloud/cloud-sql-connector`, Claude Haiku 4.5 for inference, with configuration documented |
| 23 | Housekeeping | `README.md` → `FETCHER-BRIEF.md`; new short README |

### 1.2 Deviations from the brief — each needs your sign-off

**D1. Google provider `~> 8.5`, not `~> 7.0`.**
The brief was written when 7.0 was new. Today the latest is 8.5.0 and the 7.x line
is a major version behind. Starting a new repo on a superseded major means doing
the 7→8 upgrade later for no reason. I'll read the v8 upgrade guide and pin
`~> 8.5` (allows 8.x patches and minors, never 9.0).

**D2. Terraform pinned to 1.16.4.**
`required_version = ">= 1.9, < 2.0"` in config (per the brief), plus
`.terraform-version` and the CI setup step pinned to exactly 1.16.4 so local and CI
can never silently differ. (1.16.5 shipped the day before and is not in the
HashiCorp tap yet; matching across machines beats being one patch newer.) Your local Terraform is 1.5.7 from Homebrew core, which
is the last MPL-licensed build — it must be replaced with the `hashicorp/tap`
formula.

**D3. Two projects, not one.**
The brief says one project. I recommend a seed project (state bucket, WIF pool, CI
service accounts, budget) and a dev project (workloads), because:
- Destroying or rebuilding dev can never take out the state or the CI identity.
- Prod at M5 becomes a new project, not a new bootstrap.
- It mirrors how real GCP estates are laid out, which §6 already gestures at.

Projects are free; this costs nothing.

**D4. Two CI service accounts, not one `terraform-deployer`.**
A single SA that can both plan on PRs and apply on main cannot be least-privilege:
plans run on untrusted-ish PR code, applies are privileged. Split:
- `tf-plan@seed` — read-only, any ref in the repo.
- `tf-apply@seed` — write, only the `tf-apply` GitHub environment subject.

**D5. Budget and org policy move into bootstrap (M0).**
The brief contradicts itself (§17 says M1, the milestone table says M8), and the
default-SA org policy only affects service accounts created *after* enforcement —
so it must land before `compute.googleapis.com` is ever enabled, or it is
decorative.

**D6. Three modules the brief's layout omits.**
- `modules/storage` — §8.9 requires a GCS bucket but the module list has none.
- `modules/service-account` — a workload SA plus its role bindings, used 5+ times.
- `modules/billing-budget` — budget lives at billing-account scope and is applied by
  you in bootstrap, not by the CI SA, which must never hold billing admin.

**D7. `prevent_destroy` is hardcoded inside the Cloud SQL and state-bucket modules.**
`lifecycle` blocks cannot take variables — this is a Terraform language limit, not a
style choice. A `var.prevent_destroy` input is therefore impossible. Noted here
because it will look like an inconsistency with "nothing hardcoded in modules."

**D8. PR plans run with `-lock=false`.**
A read-only plan SA cannot write the GCS lock object. The alternatives are granting
the plan SA write access to state (defeats the point) or a conditional IAM binding
scoped to the lock object name (fragile). A plan mutates nothing; the worst case is
a plan computed against state that an apply is concurrently rewriting, which the CI
concurrency group already makes unlikely. Documented in the workflow.

**D9. Scheduler uses `oauth_token`, not `oidc_token`.**
Starting a Cloud Run job calls `run.googleapis.com/…/jobs/X:run`, a Google API,
which takes an OAuth access token. OIDC tokens are for calling your own services.
The brief's §8.7 wording is wrong.

**D10. The Cloud Tasks target endpoint is verified in the application.**
The web service must allow `allUsers` (browsers and Twilio reach it), so Cloud Run
IAM cannot protect `/internal/*`. The app verifies the OIDC token's signature,
audience, and caller SA email. A separate internal-ingress service is the
alternative if you'd rather have infrastructure enforce it; I've chosen app-level
verification plus a deny-by-default middleware test.

### 1.3 Decisions the brief left open, resolved here

| Area | Decision |
|---|---|
| Project IDs | `ogbn-fetcher-seed`, `ogbn-fetcher-dev`, `ogbn-fetcher-prod` (globally unique, permanent — override at sign-off if you dislike the prefix) |
| Folder | `fetcher` folder under the org, so project-level policy has one parent |
| State layout | One bucket in seed, prefixes `bootstrap/`, `envs/dev/`, `envs/prod/` |
| BigQuery location | `us-east4`, matching everything else |
| Image tags | Commit SHA only; Terraform ignores image changes, CD owns the tag |
| Initial Cloud Run image | Google's public `hello` image, so Terraform can create the service before CD exists |
| Action pinning | All third-party GitHub Actions pinned to full commit SHAs |
| Default workflow permissions | `contents: read`; `id-token: write` only on jobs needing it |
| Fork PRs | Plan job skipped — forks get no OIDC token by design |
| Labels | `provider default_labels`: `app=fetcher`, `env`, `managed-by=terraform` |
| Resource naming | `fetcher-<env>-<resource>` |
| Secret values | Terraform creates the secret container; versions are added out of band so no secret ever enters state |
| Migrations | Cloud Run job, run on deploy, using the same image |
| Scoring config | One commented, named weights object, unit-tested, versioned in the `rec_served` event |

---

## 2. Milestones

Renumbered because of D5 and the new prod milestone. Brief numbers in brackets.

| # | Milestone | Done when |
|---|---|---|
| **M0** | [0] Bootstrap: projects, folder, org policy, state bucket, WIF, CI SAs, budget, GitHub config; state migrated to GCS; `envs/dev` with project-services only | A PR posts a real plan; merging to main applies it after your environment approval; no key exists anywhere |
| **M1** | [1] Network, Cloud SQL (private IP, IAM auth), Artifact Registry, Secret Manager, GCS snapshots bucket | CI applies it; a Cloud Run job inside the VPC reaches the DB; nothing public can |
| **M2** | [2] Cloud Run service (hello-world), both workflows complete | Merge to main deploys a SHA-tagged revision |
| **M3** | [3] Schema, migrations, scoring function with tests — no UI | `pnpm test` passes; a script ranks a hand-seeded venue set. **Also: open the Twilio account and start A2P registration** |
| **M4** | [4] Menu pipeline job: GCS snapshots, Vertex inference, tiering, admin verify form behind IAP | 50 DC venues ingested; one verified in under 60s |
| **M5** | *new* Prod environment: `ogbn-fetcher-prod`, `envs/prod`, separate CI gate | Prod applies from CI; dev is free to be broken again |
| **M6** | [5] Web onboarding, goal intake, pace guardrail, recommendation card | You sign up and get a real recommendation on your phone |
| **M7** | [6] SMS loop with the Cloud Tasks follow-up | You text "dinner" from a DC street. **Blocked on A2P approval** |
| **M8** | [7] Event mode, all three moments | Morning-after flow fires and passes the copy lint |
| **M9** | [8] Pub/Sub → BigQuery, observability, alert policies, 300 venues | The second-trip cohort curve renders from real data |

---

## 3. Repository tree

```
fetcher-app/
├── FETCHER-BRIEF.md              # the brief (renamed from README.md)
├── README.md                     # short: what this is, how to run it
├── .gitignore                    # *.tfstate*, .terraform/, .env* — committed BEFORE first apply
├── .terraform-version            # 1.16.5
├── .tflint.hcl                   # google ruleset
├── .checkov.yml                  # skips, each with a written reason
├── .pre-commit-config.yaml       # fmt, validate, tflint
├── docs/
│   ├── PLAN.md                   # this file
│   ├── COSTS.md                  # running estimate vs actual
│   ├── decisions/                # ADRs, one per non-obvious choice
│   │   └── 0001-seed-and-env-projects.md
│   └── runbooks/
│       ├── bootstrap.md          # the one-time human apply, step by step
│       ├── ci.md                 # how WIF, the two SAs and the gates fit together
│       ├── database.md           # IAM auth, grants, migrations, stop/start
│       └── disaster-recovery.md  # rebuild from an empty org
├── .github/
│   ├── CODEOWNERS
│   ├── dependabot.yml            # actions + npm + terraform
│   └── workflows/
│       ├── infra.yml             # fmt→init→validate→tflint→checkov→plan→apply
│       └── app.yml               # lint→typecheck→test→build→push→deploy  (M2)
├── infra/
│   ├── bootstrap/                # local state → migrated to GCS
│   │   ├── versions.tf
│   │   ├── providers.tf          # google + github
│   │   ├── projects.tf           # folder, seed + dev projects, billing link
│   │   ├── org-policy.tf         # BEFORE any compute API is enabled
│   │   ├── state-bucket.tf
│   │   ├── wif.tf                # pool, provider, attribute condition
│   │   ├── ci-service-accounts.tf
│   │   ├── budget.tf
│   │   ├── github.tf             # repo settings, environment, branch protection
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   └── backend.tf            # added at the end, then init -migrate-state
│   ├── modules/
│   │   ├── project-services/
│   │   ├── service-account/      # D6
│   │   ├── network/
│   │   ├── cloud-sql/
│   │   ├── artifact-registry/
│   │   ├── storage/              # D6
│   │   ├── cloud-run-service/
│   │   ├── cloud-run-job/
│   │   ├── scheduling/
│   │   ├── analytics/
│   │   ├── secrets/
│   │   ├── observability/
│   │   └── billing-budget/       # D6
│   └── envs/
│       ├── dev/
│       │   ├── backend.tf
│       │   ├── versions.tf
│       │   ├── providers.tf
│       │   ├── main.tf
│       │   ├── iam.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── terraform.tfvars
│       └── prod/                 # M5
└── app/                          # M3 onward
    ├── package.json
    ├── src/
    └── tests/
```

Every module directory contains `main.tf`, `variables.tf`, `outputs.tf`,
`versions.tf`, `README.md`. No module contains a `provider` block.

---

## 4. Terraform module interfaces

Conventions: every variable is typed, described, and validated where it has a
legal range. Every module takes `project_id`. Collections use `for_each` over maps
keyed by a stable string. `count` appears only for true on/off toggles.

### `project-services`
**In:** `project_id`, `services` (set(string)), `disable_on_destroy` (bool, default `false`), `settle_duration` (string, default `"60s"`)
**Out:** `enabled_services` (map), `ready` (the `time_sleep` id — other modules `depends_on` this; §8.1's eventual-consistency trap)

### `service-account`
**In:** `project_id`, `account_id`, `display_name`, `description`, `project_roles` (set(string)), `impersonators` (set(string), default `[]`)
**Out:** `email`, `member` (`serviceAccount:…`), `name`, `unique_id`

### `network`
**In:** `project_id`, `network_name`, `region`, `subnet_cidr`, `psa_cidr`, `enable_flow_logs` (bool, default `true`), `flow_log_sampling` (number, 0–1, default `0.5`), `enable_cloud_nat` (bool, default `false` — the M4 exercise in §8.2)
**Out:** `network_id`, `network_self_link`, `subnet_id`, `subnet_self_link`, `subnet_cidr`, `psa_range_name`, `service_networking_connection_id`

### `cloud-sql`
**In:** `project_id`, `region`, `instance_name`, `database_version` (default `POSTGRES_17`, validated against an allowlist), `tier`, `edition` (default `ENTERPRISE`, validated), `disk_size_gb`, `disk_autoresize_limit`, `network_id`, `psa_connection` (dependency handle), `databases` (set), `iam_users` (map of SA email → type), `backup` (object: enabled, start_time, retained_count, pitr), `maintenance_window` (object: day, hour, update_track), `activation_policy` (`ALWAYS`|`NEVER`, validated), `database_flags` (map), `query_insights` (bool)
**Out:** `instance_name`, `connection_name`, `private_ip_address`, `self_link`, `database_names`, `iam_user_emails`
**Notes:** `deletion_protection = true` and `prevent_destroy` hardcoded (D7). `cloudsql.iam_authentication` always on. No `random_password` anywhere — nothing to leak into state.

### `artifact-registry`
**In:** `project_id`, `region`, `repository_id`, `description`, `keep_untagged_count` (number, default 20), `cleanup_dry_run` (bool, default `false`), `writers` (set), `readers` (set)
**Out:** `repository_id`, `repository_name`, `repository_url`

### `storage`
**In:** `project_id`, `region`, `bucket_name`, `lifecycle_age_days` (default 90), `versioning` (bool), `readers`, `writers`, `force_destroy` (bool, default `false`)
**Out:** `bucket_name`, `bucket_url`, `bucket_self_link`

### `cloud-run-service`
**In:** `project_id`, `region`, `service_name`, `image`, `service_account_email`, `network_id`, `subnet_id`, `vpc_egress` (default `PRIVATE_RANGES_ONLY`, validated), `min_instances` (default 0), `max_instances` (default 3), `concurrency` (default 80, validated 1–1000), `cpu`, `memory`, `cpu_idle` (bool, default `true`), `request_timeout`, `env` (map), `secret_env` (map → {secret_id, version}), `ingress`, `allow_unauthenticated` (bool), `enable_iap` (bool, default `false` — the admin service), `startup_probe` (object)
**Out:** `service_name`, `uri`, `latest_ready_revision`, `id`
**Notes:** `lifecycle { ignore_changes = [template[0].containers[0].image, client, client_version] }` — Terraform owns the shape, CD owns the tag (§8.5).

### `cloud-run-job`
**In:** `project_id`, `region`, `job_name`, `image`, `service_account_email`, `network_id`, `subnet_id`, `vpc_egress`, `task_timeout` (default `"3600s"`), `max_retries` (default 2), `task_count`, `parallelism`, `cpu`, `memory`, `env`, `secret_env`
**Out:** `job_name`, `job_id`, `job_location`

### `scheduling`
**In:** `project_id`, `region`, `scheduler_jobs` (map → {schedule, time_zone, target_type `run_job`|`http`, target_name_or_uri, service_account_email, paused, attempt_deadline, retry_config}), `task_queues` (map → {max_dispatches_per_second, max_concurrent_dispatches, max_attempts, min_backoff, max_backoff})
**Out:** `scheduler_job_ids`, `queue_ids`, `queue_names`

### `analytics`
**In:** `project_id`, `location`, `topic_name`, `dataset_id`, `table_id`, `schema` (structured, not a blob — §8.8), `partition_field`, `partition_expiration_days`, `clustering_fields`, `message_retention_duration`, `enable_dead_letter` (bool), `publishers` (set), `table_deletion_protection` (bool, default `true`)
**Out:** `topic_id`, `topic_name`, `subscription_id`, `dataset_id`, `table_id`, `table_full_id`

### `secrets`
**In:** `project_id`, `secrets` (map → {secret_id, accessors (set), replication_locations (list)}), `labels`
**Out:** `secret_ids` (map), `secret_names` (map)
**Notes:** containers only, never versions — values are added out of band so no secret enters state.

### `observability`
**In:** `project_id`, `notification_emails` (set), `uptime_check` (object: enabled, host, path, period), `log_based_metrics` (map), `alerts` (object: run_5xx_rate_threshold, sql_disk_util_threshold, job_failure_enabled), `notification_rate_limit`
**Out:** `notification_channel_ids`, `uptime_check_id`, `alert_policy_ids`, `log_metric_ids`

### `billing-budget`
**In:** `billing_account`, `display_name`, `amount_usd`, `projects` (set of project ids), `threshold_percents` (list, default `[0.5, 0.9, 1.0]`), `notification_channel_ids` (set), `credit_treatment`
**Out:** `budget_id`, `budget_name`
**Notes:** billing-account scope. Applied by you from bootstrap; the CI SA never holds billing admin.

---

## 5. CI/CD and identity design

### Workload Identity Federation

```
pool     fetcher-github
provider github-oidc        issuer https://token.actions.githubusercontent.com

attribute_condition =
  assertion.repository_owner_id == "<numeric>" &&
  assertion.repository_id       == "<numeric>"
```

Numeric ids, not names: a deleted or renamed repo frees its name for anyone to
claim, and a name-based condition would then trust the impostor. The ids come from
the `github_repository` data source, so they are never hand-copied.

| Identity | Principal | Can |
|---|---|---|
| `tf-plan` | `principalSet://…/attribute.repository_id/<id>` — any ref, any event | Read everything; read state |
| `tf-apply` | `principal://…/subject/repo:zico-admin/fetcher-app:environment:tf-apply` | Apply; write state |
| `app-deploy` (M2) | `principal://…/subject/repo:zico-admin/fetcher-app:environment:app-deploy` | Push images; deploy revisions |

The apply identity is reachable only through a GitHub environment, so the required
reviewer is enforced by the token exchange itself, not just by GitHub's UI.

### Roles, granted per milestone from denials

M0 grants `tf-apply` only `roles/serviceusage.serviceUsageAdmin` on dev plus object
admin on its state prefix. Every later milestone adds exactly the roles its
resources demand, read from the actual denial. This loop is the IAM lesson in §8.12
and it stays in the git history as evidence.

One honest caveat to write into the runbook: any identity holding
`roles/resourcemanager.projectIamAdmin` can grant itself anything, so a Terraform SA
that manages IAM is near-owner by construction. Mitigated with an IAM condition
restricting which roles it may grant, and with `google_project_iam_member` rather
than `_policy` (which would otherwise clobber bindings it doesn't know about).

### Workflows

`infra.yml` — paths `infra/**`
- PR: fmt -check → init → validate → tflint → checkov → plan (`-lock=false`, D8) → post plan as a PR comment. Skipped for forks.
- main: apply, in the `tf-apply` environment with you as required reviewer. Concurrency group `infra-${{ env }}` so two applies can't race.

`app.yml` — paths `app/**` (M2)
- PR: lint, typecheck, vitest.
- main: build → push `…/fetcher:${GITHUB_SHA}` → deploy revision → run the migration job. Never `:latest`; rollback is a revision pointer.

---

## 6. Risks and things to verify at build time

| Risk | Handling |
|---|---|
| **Twilio A2P 10DLC** — no account yet; US carriers filter unregistered traffic and approval takes weeks | Register at M3, four milestones before M7 needs it. A public privacy policy page is part of the application |
| **Claude on Vertex region** — likely not us-east4 | Verify the region list at M4; use the global endpoint or us-east5, and write the exception into the ADR |
| **Vertex Model Garden terms** — cannot be accepted by Terraform | Documented exception #2 alongside bootstrap |
| **Vertex quota** — new projects can start at zero | Check before M4; a quota increase has lead time |
| **Cloud SQL GRANTs** — IAM users land with no table privileges, and granting needs a superuser | Resolve at M1: either `google_sql_user.database_roles` if the provider supports it, or a one-time migration job. Decides whether a built-in `postgres` user must exist at all |
| **`db-f1-micro` connection ceiling** (~25) | Pool sized against `max_instances × pool`, asserted in the app config |
| **Provider lock file** | `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64` so CI and your Mac share one lock file |
| **ADC quota project** is a project outside the org | Repointed at the seed project after bootstrap (a local gcloud config change, not a resource) |
| **Public repo** | Plan comments expose project ids and SA emails — not secrets, but review them once. Actions pinned to SHAs; no `pull_request_target` |
| **Org policies unread** — the Org Policy API is off on the current quota project | Read them during bootstrap, when the seed project can be the quota project |

---

## 7. Milestone 0 — exact scope

Built once you sign off, then I stop.

1. `.gitignore` committed **first**, before any state can exist.
2. Rename the brief; write the short README.
3. `infra/bootstrap/` with local state:
   - `fetcher` folder; `ogbn-fetcher-seed` and `ogbn-fetcher-dev` projects, billing linked
   - org policy on both projects **before** any compute API
   - minimum APIs to function
   - state bucket: versioning, uniform bucket-level access, public access prevention, 30 noncurrent versions, `prevent_destroy`
   - WIF pool and provider with the numeric-id condition
   - `tf-plan` and `tf-apply` service accounts, bucket IAM scoped by prefix
   - $50 budget with the notification channel
   - GitHub: repo public, `tf-apply` environment with you as reviewer, branch protection on main
4. Add `backend.tf` to bootstrap, `terraform init -migrate-state`.
5. `infra/envs/dev/` with the `project-services` module only.
6. `.github/workflows/infra.yml`.
7. Open a PR, watch the plan post, approve, watch it apply.

**Done when:** a GitHub Actions job authenticates to GCP with no key and plans
successfully; `gcloud iam service-accounts keys list` shows only Google-managed keys.

---

## 8. Application decisions recorded now, built later

- **Venue selection (M4):** traveler neighborhoods only — Downtown, Penn Quarter, Dupont, Logan, Navy Yard, Georgetown, Union Station. Must publish its own menu. Cuisine share capped. Chains ≤ 20%.
- **Places usage:** `place_id` at ingestion only; hours parsed from venue sites; rating not in the scoring function. Keeps us inside Maps terms and off the per-call meter.
- **Tier enforcement (§10):** `inferred` and `unknown` rows are a different TypeScript type from `verified` and `menu_stated`. The function that renders a precise figure, and the one that satisfies a hard filter, accept only the latter — so a leak is a compile error, not a failing test. Tests cover it anyway.
- **Trips:** declared; a trip ends after N days idle; `second_trip` is a new trip ≥ 14 days later. DC residents are excluded from the 30% gate — the persona is travelers.
- **Goal intake:** web only. Stores `stated_target`, `stated_deadline`, `coached_rate_lb_per_week`, `coached_deadline`, `guardrail_applied`.
- **Copy lint:** fails the build on "cure", "detox", "flush", "prevents a hangover", plus the §9 moral-vocabulary list.
- **Deletion:** one tap deletes Postgres rows, BigQuery rows, and GCS objects. Events are keyed by a pseudonymous user id, never the phone number, so deletion is one predicate.
