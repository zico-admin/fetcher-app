provider "google" {
  project = var.project_id
  region  = var.region

  # Applied to every resource that supports labels, so cost reports and audits can
  # group by environment without anyone remembering to tag. Set once, here, rather
  # than threaded through every module.
  default_labels = {
    app        = "fetcher"
    env        = var.environment
    managed-by = "terraform"
  }
}
