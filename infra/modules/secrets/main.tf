locals {
  # Flatten {secret => [accessors]} into one binding per pair, so each secret is
  # granted only to the workloads that need it. Project-wide
  # roles/secretmanager.secretAccessor would hand every secret to everything —
  # the grant people make once and never revisit (§8.10).
  accessor_bindings = merge([
    for key, secret in var.secrets : {
      for accessor in secret.accessors :
      "${key}:${accessor}" => { secret_key = key, member = accessor }
    }
  ]...)
}

# Containers only — never versions.
#
# A google_secret_manager_secret_version would put the secret value into
# Terraform state in plaintext, which is the thing state being sensitive is
# about. Terraform declares that the secret exists and who may read it; the value
# is added out of band:
#
#   gcloud secrets versions add twilio-auth-token --data-file=- --project=...
#
# That is not a console-click exception to the repo's rule. The resource is in
# Terraform; only the value is not, and it is the one thing that must not be.
resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.value.secret_id
  labels    = var.labels

  replication {
    # Pinned to chosen regions rather than automatic, so secret material has a
    # known location. Automatic replication is simpler and tells you less.
    user_managed {
      dynamic "replicas" {
        for_each = toset(each.value.replication_locations)

        content {
          location = replicas.value
        }
      }
    }
  }
}

resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each = local.accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret_key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
