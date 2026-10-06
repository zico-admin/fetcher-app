provider "google" {
  project = var.project_id
  region  = var.region

  # Service Usage calls on the dev project must be billed to a project the CI
  # identities may "use". Without this the call carries no quota project and the
  # API answers 403 "caller does not have permission".
  billing_project       = var.quota_project_id
  user_project_override = true

  # Applied to every resource that supports labels, so cost reports and audits can
  # group by environment without anyone remembering to tag. Set once, here, rather
  # than threaded through every module.
  default_labels = {
    app        = "fetcher"
    env        = var.environment
    managed-by = "terraform"
  }
}
