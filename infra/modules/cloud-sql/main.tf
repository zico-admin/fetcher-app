locals {
  # IAM database authentication is the reason this module needs no passwords, so
  # the flag is always set here rather than left to the caller to remember.
  # Logging flags worth having on every instance: they make connection churn,
  # checkpoint pressure and lock contention visible, and cost almost nothing.
  #
  # Deliberately absent: log_statement and pgAudit. Both record statement text,
  # which for this application would put self-reported weight and goal data into
  # Cloud Logging — §15 says that data does not leave the database, and a log
  # sink is leaving. They are also the two settings that actually cost money at
  # volume.
  standard_log_flags = {
    "log_checkpoints"    = "on"
    "log_connections"    = "on"
    "log_disconnections" = "on"
    "log_lock_waits"     = "on"
    "log_hostname"       = "on"
    "log_min_messages"   = "warning"
  }

  database_flags = merge(
    { "cloudsql.iam_authentication" = "on" },
    var.enable_standard_log_flags ? local.standard_log_flags : {},
    var.extra_database_flags,
  )

  # Cloud SQL for PostgreSQL truncates the .gserviceaccount.com suffix from a
  # service account's email when it becomes a database user. Get this wrong and
  # the user is created with a name that can never log in — a silent failure that
  # only shows up as an authentication error much later.
  iam_user_names = {
    for key, user in var.iam_users :
    key => user.type == "CLOUD_IAM_SERVICE_ACCOUNT" ? trimsuffix(user.email, ".gserviceaccount.com") : user.email
  }
}

resource "google_sql_database_instance" "this" {
  # The six below are set — in local.standard_log_flags, rendered through the
  # dynamic database_flags block. Checkov evaluates configuration statically and
  # cannot see through merge() plus a dynamic block, so it reports them missing.
  # Verified in the plan: the instance renders 7 database_flags blocks, the six
  # here plus cloudsql.iam_authentication.
  # checkov:skip=CKV_GCP_51:Set via local.standard_log_flags (log_checkpoints = on); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_52:Set via local.standard_log_flags (log_connections = on); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_53:Set via local.standard_log_flags (log_disconnections = on); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_54:Set via local.standard_log_flags (log_lock_waits = on); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_108:Set via local.standard_log_flags (log_hostname = on); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_109:Set via local.standard_log_flags (log_min_messages = warning, which is below ERROR); invisible to static analysis through a dynamic block.
  # checkov:skip=CKV_GCP_111:Logging every SQL statement would write self-reported weight and goal data into Cloud Logging. §15 keeps health-adjacent data in the database; a log sink is a copy of it somewhere with different access controls. Slow-query visibility comes from Query Insights instead, which reports shapes rather than values.
  # checkov:skip=CKV_GCP_110:pgAudit records statement text, so it carries the same privacy problem as CKV_GCP_111, plus real log-ingestion cost at volume. Revisit if this ever needs a compliance audit trail, and scope it to specific tables rather than everything.
  # checkov:skip=CKV_GCP_6:The check looks for the deprecated require_ssl field. ssl_mode = "ENCRYPTED_ONLY" is its replacement and is set below; setting both is not possible in provider 8.
  # checkov:skip=CKV_GCP_79:POSTGRES_17 is deliberate. The variable validation permits 16 or 17 per the brief, and 17 is the newer of the two; chasing the newest major the moment it appears is how you end up on a version Cloud SQL supports but the connector libraries do not.
  # checkov:skip=CKV_GCP_14:Backups ARE enabled — var.backup.enabled defaults to true and the block below reads it. Checkov cannot see through an optional object attribute's default, so this is a false positive. Verify in the plan output, where the setting is concrete.
  project          = var.project_id
  name             = var.instance_name
  region           = var.region
  database_version = var.database_version

  # Terraform-side guard. This is separate from the API-side flag below: this one
  # makes Terraform refuse to destroy the instance, the other makes Google refuse.
  # Both, because they fail at different moments.
  deletion_protection = true

  settings {
    tier    = var.tier
    edition = var.edition

    # ZONAL is single-zone and half the price of REGIONAL. For a phase that is
    # measuring whether anyone returns for a second trip, an hour of downtime
    # during a zonal incident costs less than the standby costs every month.
    availability_type = var.availability_type

    disk_type             = "PD_SSD"
    disk_size             = var.disk_size_gb
    disk_autoresize       = true
    disk_autoresize_limit = var.disk_autoresize_limit

    # NEVER stops the instance: compute stops billing, storage does not (§17).
    # Driving it from here rather than `gcloud sql instances patch` keeps the
    # stopped state in config instead of making it drift the next apply undoes.
    activation_policy = var.activation_policy

    # API-side guard, the counterpart to deletion_protection above.
    deletion_protection_enabled = true

    user_labels = var.labels

    ip_configuration {
      # The whole point (§8.3). No public address exists, so there is no
      # authorized-networks list to get wrong, and no surface to scan.
      ipv4_enabled = false

      private_network = var.network_self_link

      # Reject unencrypted connections outright.
      ssl_mode = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled    = var.backup.enabled
      start_time = var.backup.start_time

      # Point-in-time recovery is off for now: it bills for write-ahead log
      # storage, and at this stage the data is reconstructible from GCS snapshots
      # and the menu pipeline. Turn it on before real user data matters.
      point_in_time_recovery_enabled = var.backup.point_in_time_recovery

      backup_retention_settings {
        retained_backups = var.backup.retained_count
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day          = var.maintenance_window.day
      hour         = var.maintenance_window.hour
      update_track = var.maintenance_window.update_track
    }

    insights_config {
      query_insights_enabled  = var.query_insights
      record_application_tags = false
      record_client_address   = false # a client address here is a user's IP
    }

    dynamic "database_flags" {
      for_each = local.database_flags

      content {
        name  = database_flags.key
        value = database_flags.value
      }
    }
  }

  lifecycle {
    # Last line of defence. A plan that wants to destroy the database fails here,
    # loudly, before anything irreversible happens. It cannot be a variable —
    # lifecycle arguments are evaluated too early for that — which is why this
    # module hardcodes it rather than exposing a toggle.
    prevent_destroy = true

    # This does two jobs. It fails with a readable message instead of an opaque
    # Google error if Private Service Access is missing, and — because a
    # precondition's references are real dependencies — it orders the instance
    # after the peering. A comment saying "depends on the connection" would not
    # have created the edge; referencing the value does.
    precondition {
      condition     = var.psa_connection_id != ""
      error_message = "psa_connection_id is empty: Private Service Access is not configured, and an instance with ipv4_enabled = false cannot be created without it."
    }
  }
}

resource "google_sql_database" "this" {
  for_each = var.databases

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = each.value

  # Deleting a database drops every table in it. Removing one from the set should
  # be a deliberate two-step: remove this guard, then remove the database.
  deletion_policy = "ABANDON"
}

# IAM database users (§8.3).
#
# No password exists anywhere in this module: no random_password, nothing in
# state, nothing in Secret Manager, nothing to rotate. Revoking database access
# becomes an IAM change. `password` is not required for these user types, which
# is exactly what makes the passwordless design possible.
#
# An IAM user arrives with NO database privileges — unlike a built-in user, which
# is granted cloudsqlsuperuser automatically. Something has to issue the first
# GRANT, so one account here is given cloudsqlsuperuser via database_roles and
# does it for the others from the migration job.
resource "google_sql_user" "iam" {
  for_each = var.iam_users

  project  = var.project_id
  instance = google_sql_database_instance.this.name
  name     = local.iam_user_names[each.key]
  type     = each.value.type

  database_roles = each.value.database_roles
}
