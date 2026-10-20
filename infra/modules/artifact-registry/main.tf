resource "google_artifact_registry_repository" "this" {
  # checkov:skip=CKV_GCP_84:Customer-managed keys would add a Cloud KMS key to create, rotate, hold IAM on, and never lose — because losing it makes every image unreadable. Images here are built from a public repository and carry no secrets; Google-managed encryption at rest is the right trade. Revisit if images ever embed proprietary data.
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_id
  description   = var.description
  format        = "DOCKER"
  labels        = var.labels

  # Container images accumulate silently — every commit to main pushes one, and
  # nothing ever deletes them. Three lines of config against a slow leak (§8.4).
  #
  # dry_run first if you are nervous: it logs what would be deleted without
  # deleting anything, so you can read a week of decisions before trusting it.
  cleanup_policy_dry_run = var.cleanup_dry_run

  # Untagged images are the ones no deployment refers to: superseded layers and
  # failed builds.
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = var.untagged_older_than
    }
  }

  # Keeps the most recent images whatever the rule above says, so a rollback
  # target cannot be deleted out from under you. Order does not matter: KEEP
  # policies win over DELETE policies.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.keep_recent_count
    }
  }
}

resource "google_artifact_registry_repository_iam_member" "writers" {
  for_each = var.writers

  project    = var.project_id
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.writer"
  member     = each.value
}

resource "google_artifact_registry_repository_iam_member" "readers" {
  for_each = var.readers

  project    = var.project_id
  location   = google_artifact_registry_repository.this.location
  repository = google_artifact_registry_repository.this.name
  role       = "roles/artifactregistry.reader"
  member     = each.value
}
