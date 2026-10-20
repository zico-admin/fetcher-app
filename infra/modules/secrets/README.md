# secrets

Secret Manager containers and per-secret access, never values.

A `google_secret_manager_secret_version` would put the secret value into
Terraform state in plaintext — the exact thing "state is a secret" is about. So
this module declares that a secret exists and who may read it; the value is
added out of band:

    gcloud secrets versions add twilio-auth-token --project=PROJECT --data-file=-

The `add_version_commands` output prints the exact command per secret. That is
not a console-click exception to the repo's rule: the resource is in Terraform,
and only the value is not, which is the one thing that must not be.

Access is granted per secret to named members, never project-wide
`roles/secretmanager.secretAccessor` — the grant people make once and never
revisit (§8.10).

**Inputs:** `project_id`, `secrets` (map of `secret_id`, `accessors`,
`replication_locations`), `labels`.

**Outputs:** `secret_ids`, `secret_names`, `add_version_commands`.

Replication is user-managed so secret material has a known location.
