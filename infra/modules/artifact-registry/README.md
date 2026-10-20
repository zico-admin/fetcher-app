# artifact-registry

One Docker repository, with cleanup policies.

Images accumulate silently: every merge to main pushes one and nothing deletes
them. Two policies — delete untagged images older than a week, always keep the
most recent 20 — are a few lines against a slow leak (§8.4).

Set `cleanup_dry_run = true` for a cycle if you want to read the decisions
before trusting them; it logs what would be deleted without deleting it.

**Inputs:** `project_id`, `region`, `repository_id`, `description`,
`keep_recent_count`, `untagged_older_than`, `cleanup_dry_run`, `writers`,
`readers`, `labels`.

**Outputs:** `repository_id`, `repository_name`, `repository_url`.

Tag images with the commit SHA, never `latest`: otherwise you cannot say which
commit is in production and a rollback is guesswork (§7).
