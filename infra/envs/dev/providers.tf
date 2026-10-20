provider "google" {
  project = var.project_id
  region  = var.region

  # Deliberately NO billing_project / user_project_override.
  #
  # Both were added (PR #4) in the same bootstrap apply as roles/browser, to fix
  # the same 403 on google_project_service, so neither could be credited. This
  # removes the override to find out which one was load-bearing.
  #
  # If the apply on main succeeds, roles/browser was the real fix and the quota
  # coupling goes with this commit: billing every environment's API calls to the
  # seed project would make dev and prod share one project's quota.
  #
  # If it fails with "caller does not have permission", the override is required
  # and comes back with this failure recorded next to it.

  # Applied to every resource that supports labels, so cost reports and audits can
  # group by environment without anyone remembering to tag. Set once, here, rather
  # than threaded through every module.
  default_labels = {
    app        = "fetcher"
    env        = var.environment
    managed-by = "terraform"
  }
}
