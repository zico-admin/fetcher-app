# service-account

A workload identity plus the roles it holds on its project.

One per workload (§8.12): `run-web`, `run-job`, and later `scheduler-invoker`.
Never the default compute account — which on these projects no longer carries
`roles/editor` either (ADR 0002).

**Inputs:** `project_id`, `account_id`, `display_name`, `description`,
`project_roles`, `impersonators`.

**Outputs:** `email`, `member`, `name`, `sql_user_name`.

`sql_user_name` exists because Cloud SQL for PostgreSQL strips
`.gserviceaccount.com` from a service account email. Computing it once here
beats getting it wrong somewhere else.

`project_roles` rejects `roles/owner`, `roles/editor` and `roles/viewer` with a
validation error. A workload that appears to need a basic role needs a narrower
role nobody has looked up yet.

Bindings use `google_project_iam_member`, which is additive.
`google_project_iam_policy` is authoritative and would delete every binding not
in config — including yours.
