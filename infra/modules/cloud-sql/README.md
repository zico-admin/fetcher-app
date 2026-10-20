# cloud-sql

PostgreSQL on a private IP, authenticated with IAM, with no password anywhere.

## Why there is no password

`google_sql_user` does not require `password` when `type` is `CLOUD_IAM_USER` or
`CLOUD_IAM_SERVICE_ACCOUNT` — confirmed in the provider schema, not assumed. So:

- nothing in Terraform state, which stores values in plaintext
- nothing in Secret Manager, and nothing to rotate
- revoking database access is an IAM change

A `random_password` would have landed in state forever. Survivable with a
locked-down bucket, but avoiding it is better (§8.3).

## The GRANT problem, and how it is solved

An IAM database user is created with **no privileges at all**. A built-in user is
different: it gets `cloudsqlsuperuser` automatically. So something has to issue
the first `GRANT`, and the obvious answer — use the built-in `postgres` user —
means giving it a password and losing the property above.

Instead one account is created with `database_roles = ["cloudsqlsuperuser"]`
(the migration job's), and it grants the others exactly what they need. No
built-in user is ever created.

**Break-glass:** deliberately not provisioned. Setting a password on `postgres`
is a control-plane call through the Cloud SQL Admin API, so it still works when
IAM login is broken. Break-glass can be created at the moment it is needed; a
standing password is a standing liability.

**Username truncation:** Cloud SQL strips `.gserviceaccount.com` from a service
account email. The module does this; `iam_user_names` gives the exact strings to
use in `GRANT` statements. Getting it wrong creates a user that can never log in.

## Guards

`deletion_protection` (Terraform refuses) and `deletion_protection_enabled`
(Google refuses) are both on, because they fail at different moments.
`prevent_destroy` is hardcoded — `lifecycle` arguments cannot take variables, so
a toggle is impossible, not merely undesirable (§5).

## Logging

Connection, disconnection, checkpoint, lock-wait and hostname logging are on by
default. `log_statement` and pgAudit are deliberately **off**: both record
statement text, which here would mean self-reported weight and goal data in
Cloud Logging, and §15 keeps that data in the database.

## Inputs

Required: `project_id`, `region`, `instance_name`, `network_self_link`,
`psa_connection_id`.

Notable optional: `database_version` (`POSTGRES_17`), `edition` (`ENTERPRISE`),
`tier` (`db-f1-micro`), `availability_type` (`ZONAL`), `disk_size_gb` (`10`),
`activation_policy` (`ALWAYS` — set `NEVER` to stop the instance between work
sessions), `databases`, `iam_users`, `backup`, `maintenance_window`,
`query_insights`, `enable_standard_log_flags`, `extra_database_flags`, `labels`.

## Outputs

`instance_name`, `connection_name`, `private_ip_address`, `self_link`,
`database_names`, `iam_user_names`.

## Cost

`db-f1-micro` with 10 GB SSD is roughly $13/month and the largest fixed line in
the project. `activation_policy = "NEVER"` stops compute billing; storage bills
regardless. Driving it from Terraform keeps the stopped state in config instead
of as drift the next apply would undo.
