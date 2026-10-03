# Who read the state bucket, and when.
#
# Admin Activity audit logs are on by default and cannot be switched off, but they
# only record configuration changes. Reading an object is a DATA_READ event, and
# data access logging is OFF by default for every service — so without this block,
# nothing anywhere records that someone downloaded terraform.tfstate.
#
# Given that state contains secrets in plaintext (§5), that is the one access log
# actually worth having.
#
# Preferred over GCS bucket access logs (which is what Checkov asks for on the
# bucket itself) because those write hourly CSV files into a second bucket that
# then needs its own protection and lifecycle. These land in Cloud Logging, are
# queryable immediately, and can feed an alert policy at M9.
resource "google_project_iam_audit_config" "seed_storage" {
  project = google_project.seed.project_id
  service = "storage.googleapis.com"

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}
