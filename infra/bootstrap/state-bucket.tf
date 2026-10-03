# State is a secret (§5). It stores generated passwords and secret values in
# plaintext, so this bucket is treated as a credential store, not as storage.
resource "google_storage_bucket" "tfstate" {
  # checkov:skip=CKV_GCP_62:Access to this bucket IS logged, by a better mechanism than the bucket access logs this check looks for. See audit-logs.tf — DATA_READ and DATA_WRITE audit logging is enabled for storage on this project, which lands in Cloud Logging rather than in hourly CSV files in a second bucket that would itself need protecting.
  name     = var.state_bucket_name
  project  = google_project.seed.project_id
  location = var.region

  # Uniform access means ACLs cannot be used at all, so permissions live in exactly
  # one place: IAM. Per-object ACLs are how buckets quietly become world-readable.
  uniform_bucket_level_access = true

  # Belt and braces: even an IAM binding to allUsers would be rejected.
  public_access_prevention = "enforced"

  # Refuse to delete a bucket that still contains objects.
  force_destroy = false

  # Versioning is the undo button for a corrupted or truncated state file.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.state_bucket_noncurrent_versions
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Note on soft delete: GCS applies a default soft-delete retention to new buckets,
  # so deleted objects are recoverable (and billed) for that window. For a state
  # bucket that is a feature, so it is left at the default rather than disabled.

  # The last line of defence. A plan that wants to destroy this must fail loudly,
  # even if someone removed the resource from config.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [module.seed_services]
}

# You. Full control of the bucket, because you are the one who repairs state when
# it breaks.
resource "google_storage_bucket_iam_member" "admin" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.admin"
  member = "user:${var.admin_email}"
}

locals {
  # IAM conditions on GCS objects match on the full object path.
  #
  # The `resource.type == Bucket` disjunct is not padding. storage.objects.list is
  # authorised against the BUCKET, not against any object, so a condition that only
  # matches object names silently denies listing and Terraform's backend fails in a
  # confusing way. Allowing list across the bucket exposes state file *names*, not
  # their contents.
  envs_prefix_condition = <<-EOT
    resource.type == "storage.googleapis.com/Bucket" ||
    resource.name.startsWith("projects/_/buckets/${var.state_bucket_name}/objects/envs/")
  EOT
}

# CI writes state for environments only. The bootstrap/ prefix stays human-only:
# the CI identity must not be able to rewrite the state that defines the CI
# identity.
resource "google_storage_bucket_iam_member" "tf_apply_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.tf_apply.member

  condition {
    title       = "envs-prefix-only"
    description = "Environment state only; bootstrap state is off limits to CI."
    expression  = local.envs_prefix_condition
  }
}

resource "google_storage_bucket_iam_member" "tf_plan_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.tf_plan.member

  condition {
    title       = "envs-prefix-only"
    description = "Read-only access to environment state for plan."
    expression  = local.envs_prefix_condition
  }
}
