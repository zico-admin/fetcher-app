# storage

A GCS bucket with uniform access, public access prevention, and a lifecycle rule.

Used for raw menu HTML and PDF snapshots. Keeping the inputs means that when an
inference looks wrong you can read what produced it — the difference between
debugging and guessing (§8.9) — and the lifecycle rule stops them accumulating
forever.

**Inputs:** `project_id`, `bucket_name`, `location`, `lifecycle_age_days`,
`versioning`, `keep_noncurrent_versions`, `force_destroy`, `writers`, `readers`,
`labels`.

**Outputs:** `bucket_name`, `bucket_url`, `bucket_self_link`.

Writers get `roles/storage.objectUser` (read, write, delete objects) rather than
`storage.admin`, which would also allow changing the bucket's own configuration.

Turning `versioning` on also enables a noncurrent-version lifecycle rule;
without one, versioning quietly turns a 90-day deletion policy into permanent
storage of every overwrite.
