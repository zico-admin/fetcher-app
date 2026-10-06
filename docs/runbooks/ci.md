# Runbook — how CI authenticates, and how to extend it

## The chain, end to end

1. A workflow job asks GitHub for an OIDC token. This requires `permissions:
   id-token: write` on the job. Forget it and nothing works.
2. GitHub mints a short-lived JWT. Its `sub` claim identifies the job precisely —
   `repo:zico-admin/fetcher-app:pull_request` for a PR, or
   `repo:zico-admin/fetcher-app:environment:tf-apply` for a job declaring that
   environment.
3. `google-github-actions/auth` presents the JWT to GCP's Security Token Service,
   naming the workload identity provider.
4. The provider's `attribute_condition` rejects the token unless
   `assertion.repository_id` equals this repository's numeric id.
5. STS returns a federated token. It is exchanged for a short-lived access token
   for whichever service account the job named — but only if that account has an
   `iam.workloadIdentityUser` binding matching this principal.
6. Terraform runs as that service account. The token expires in an hour.

No key exists at any step. Nothing to rotate, leak, or commit.

## Why two service accounts

| | `tf-plan` | `tf-apply` |
|---|---|---|
| Used on | pull requests | pushes to main |
| Bound to | `principalSet://…/attribute.repository_id/<id>` — any job in this repo | `principal://…/subject/repo:zico-admin/fetcher-app:environment:tf-apply` — one exact subject |
| GCP roles | `viewer`, `iam.securityReviewer` | only what the current milestone needs |
| State bucket | `objectViewer`, `envs/` prefix only | `objectAdmin`, `envs/` prefix only |

Neither can touch the `bootstrap/` state prefix. The CI identity must not be able
to rewrite the state that defines the CI identity.

The apply binding is worth understanding properly: because it keys on the
environment in the token's subject, a workflow that drops `environment: tf-apply`
cannot authenticate **at all**. The human approval is enforced by GCP, not only by
GitHub's UI.

## The first apply of a new environment

A plan cannot be the first thing that runs against a brand-new environment, and
this surprises people. Expect it again when `envs/prod` is created at M5.

On a PR touching a never-applied environment, `terraform init` fails with:

```
Error loading state: writing "gs://.../envs/dev/default.tflock" failed:
403 ... does not have storage.objects.create access
```

The GCS backend, finding no state object, tries to create one — and takes a lock
to do it. That is a write, during `init`, before `plan` ever runs, so the
`-lock=false` on the plan step is irrelevant. `tf-plan` is read-only and refuses.

**Do not fix this by granting the plan identity write access.** In GCS,
`storage.objects.create` also overwrites existing objects, so that one permission
would let any pull request rewrite your state.

**Do not pre-create a placeholder state object from bootstrap either.**
`google_storage_bucket_object` tracks its content, so after the environment
applied for real, bootstrap's next plan would propose replacing live state with
the empty placeholder.

The sequence that works:

1. Merge the pull request. The `plan` check cannot pass yet; `enforce_admins` is
   false precisely so you can merge this once without disabling protection.
2. The apply job runs on main as `tf-apply`, which holds `objectAdmin` on the
   `envs/` prefix. It creates the state object.
3. Every plan after that is a pure read, and the check behaves normally.

In other words, the first write to an environment's state is always an apply, by
the only identity allowed to write. That is the property you want.

## Adding a permission (the least-privilege loop)

This is the intended workflow, not a workaround. Do not pre-grant roles.

1. Write the Terraform for the new resource and open a PR.
2. The apply fails with something like
   `Error 403: Permission 'compute.networks.create' denied on resource`.
3. Read the **permission**, not the resource. Find the narrowest predefined role
   containing it, or write a custom role if the predefined one is far too wide.
4. Add it to `local.tf_apply_roles` in `infra/bootstrap/ci-service-accounts.tf`,
   with the milestone in a comment.
5. Apply bootstrap locally, re-run the failed job.

The git history of that list becomes the evidence that permissions were derived
from denials rather than from `roles/editor`.

Known sharp edge, written down rather than hidden: anything holding
`roles/resourcemanager.projectIamAdmin` can grant itself any role, so a Terraform
identity that manages IAM is close to owner by construction. When M1 needs it,
constrain it with an IAM condition limiting which roles it may grant, and keep
using `google_project_iam_member` rather than `google_project_iam_policy` — the
latter overwrites bindings it does not know about, including yours.

## Reading a plan before approving an apply

Read the plan comment on the PR, in this order:

1. **Destroy.** Anything that says `will be destroyed` or `must be replaced`. A
   replace on the Cloud SQL instance or the state bucket should be impossible —
   `prevent_destroy` will fail the plan first — but a replace on a network or a
   service account is survivable and still probably wrong.
2. **Forced replacement reasons.** Terraform prints `# forces replacement` next to
   the offending attribute. If it is an attribute you did not intend to change,
   stop.
3. **IAM members.** Anything granting a role to a principal that is not one of
   ours.
4. **Counts.** The summary line should match what the diff looked like.

If a resource is being destroyed and recreated only because it moved or was
renamed, that is what `moved` blocks are for — add one instead of approving the
churn (§5).

## When a plan and an apply disagree

The plan ran with `-lock=false` (see deviation D8 in `docs/PLAN.md`), so a plan
computed while an apply was in flight can be stale. The apply job re-plans before
applying, so the result is correct either way — but if the apply does something
the comment did not predict, that is the reason, and the fix is to re-run the plan
rather than to distrust the apply.
