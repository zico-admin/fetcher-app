resource "google_storage_bucket" "this" {
  # checkov:skip=CKV_GCP_78:Versioning is an input (var.versioning), not an omission. Callers storing anything editable turn it on; the menu snapshots bucket does not, because snapshots are append-only and versioning would duplicate storage for objects that are never overwritten.
  # checkov:skip=CKV_GCP_62:Bucket access logs write hourly CSV files into a second bucket that then needs its own protection and lifecycle. Where access to a bucket genuinely matters — the Terraform state bucket — data-access audit logging is enabled instead and lands in Cloud Logging (infra/bootstrap/audit-logs.tf). This bucket holds published restaurant menus.
  project  = var.project_id
  name     = var.bucket_name
  location = var.location
  labels   = var.labels

  # Permissions live in exactly one place: IAM. Per-object ACLs are how buckets
  # quietly become world-readable.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  force_destroy = var.force_destroy

  versioning {
    enabled = var.versioning
  }

  # Raw menu HTML and PDFs are kept so that when an inference looks wrong you can
  # read the input that produced it — the difference between debugging and
  # guessing (§8.9). They stop being useful long before they stop costing money.
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_age_days > 0 ? [1] : []

    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  # Noncurrent versions need their own rule: without it, versioning turns a
  # 90-day deletion policy into permanent storage of every overwrite.
  dynamic "lifecycle_rule" {
    for_each = var.versioning ? [1] : []

    content {
      condition {
        num_newer_versions = var.keep_noncurrent_versions
        with_state         = "ARCHIVED"
      }
      action {
        type = "Delete"
      }
    }
  }
}

resource "google_storage_bucket_iam_member" "writers" {
  for_each = var.writers

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectUser" # read, write and delete objects; no bucket administration
  member = each.value
}

resource "google_storage_bucket_iam_member" "readers" {
  for_each = var.readers

  bucket = google_storage_bucket.this.name
  role   = "roles/storage.objectViewer"
  member = each.value
}
