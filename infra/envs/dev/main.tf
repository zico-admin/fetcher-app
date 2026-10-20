locals {
  prefix = "fetcher-${var.environment}"

  # APIs owned by this environment.
  #
  # Four are deliberately absent because infra/bootstrap manages them on this
  # project: cloudresourcemanager, serviceusage, iam and orgpolicy. Two
  # configurations must never manage the same resource.
  #
  # Enabling compute is what creates the default compute service account. That is
  # safe here only because the folder-level org policy strips its automatic
  # editor grant, and was enforced before these projects existed (ADR 0002).
  services = toset([
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "iamcredentials.googleapis.com",

    # M1
    "compute.googleapis.com",           # VPC, subnet, Private Service Access
    "servicenetworking.googleapis.com", # the peering itself
    "sqladmin.googleapis.com",          # Cloud SQL
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
  ])
}

module "project_services" {
  source = "../../modules/project-services"

  project_id = var.project_id
  services   = local.services
}

# ---------------------------------------------------------------------------
# Workload identities
# ---------------------------------------------------------------------------
# One service account per workload, created before the things they need access
# to so the grants can reference them. Neither runs as the default compute
# account, which is the rule §8.12 cares most about.

module "sa_run_web" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "run-web"
  display_name = "Cloud Run web service"
  description  = "Next.js app and the Twilio webhook. Reads the database as itself via IAM authentication."

  project_roles = [
    "roles/cloudsql.client",       # connect through the Cloud SQL connector
    "roles/cloudsql.instanceUser", # log in as an IAM database user
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [module.project_services]
}

module "sa_run_job" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "run-job"
  display_name = "Cloud Run job"
  description  = "Menu ingestion and database migrations. Holds cloudsqlsuperuser, so it is the account that grants privileges to the others."

  project_roles = [
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [module.project_services]
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "network" {
  source = "../../modules/network"

  project_id   = var.project_id
  network_name = local.prefix
  region       = var.region
  subnet_cidr  = var.subnet_cidr
  psa_cidr     = var.psa_cidr

  # Cloud NAT stays off until menu fetching needs one stable egress IP — the M4
  # exercise in §8.2. It bills hourly whether or not traffic flows.
  enable_cloud_nat = false

  depends_on = [module.project_services]
}

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id    = var.project_id
  region        = var.region
  instance_name = "${local.prefix}-pg"

  tier              = var.sql_tier
  disk_size_gb      = var.sql_disk_size_gb
  activation_policy = var.sql_activation_policy

  network_self_link = module.network.network_self_link
  psa_connection_id = module.network.psa_connection_id

  databases = ["fetcher"]

  # No password exists for either user. `password` is not required for IAM user
  # types, so nothing lands in state, in Secret Manager, or in a rotation
  # schedule — revoking access is an IAM change (§8.3).
  #
  # run-job carries cloudsqlsuperuser because an IAM user is created with no
  # privileges at all, unlike a built-in user. Something must issue the first
  # GRANT, and this is how that happens without a built-in user existing.
  iam_users = {
    run_job = {
      email          = module.sa_run_job.email
      type           = "CLOUD_IAM_SERVICE_ACCOUNT"
      database_roles = ["cloudsqlsuperuser"]
    }
    run_web = {
      email = module.sa_run_web.email
      type  = "CLOUD_IAM_SERVICE_ACCOUNT"
      # Nothing. The migration job grants exactly the table privileges the app
      # needs, so the web service cannot create or drop anything.
      database_roles = []
    }
  }

  labels = { component = "database" }

  depends_on = [module.project_services]
}

# ---------------------------------------------------------------------------
# Images, storage, secrets
# ---------------------------------------------------------------------------

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  region        = var.region
  repository_id = "fetcher"
  description   = "Container images for the Cloud Run service and job, tagged with the commit SHA."

  # The CI deploy identity is added at M2, when there is something to push.
  readers = [
    module.sa_run_web.member,
    module.sa_run_job.member,
  ]

  labels = { component = "images" }

  depends_on = [module.project_services]
}

module "menu_snapshots" {
  source = "../../modules/storage"

  project_id  = var.project_id
  bucket_name = "${var.project_id}-menu-snapshots"
  location    = var.region

  # Raw menu HTML and PDFs, kept 90 days so a bad inference can be traced back to
  # the input that produced it (§8.9). No versioning: these are append-only
  # snapshots that are never edited in place.
  lifecycle_age_days = 90
  versioning         = false

  writers = [module.sa_run_job.member]
  readers = [module.sa_run_web.member]

  labels = { component = "menu-snapshots" }

  depends_on = [module.project_services]
}

module "secrets" {
  source = "../../modules/secrets"

  project_id = var.project_id

  # Twilio is the only real secret in the system. Vertex AI needs no API key and
  # Cloud SQL needs no password, which is the lesson §8.10 is making: the best
  # secret management is having fewer secrets.
  #
  # The containers exist now so Cloud Run can reference them at M2; the values go
  # in by hand once the Twilio account exists, and never pass through Terraform.
  secrets = {
    twilio_account_sid = {
      secret_id             = "twilio-account-sid"
      accessors             = [module.sa_run_web.member]
      replication_locations = [var.region]
    }
    twilio_auth_token = {
      secret_id             = "twilio-auth-token"
      accessors             = [module.sa_run_web.member]
      replication_locations = [var.region]
    }
  }

  labels = { component = "secrets" }

  depends_on = [module.project_services]
}
