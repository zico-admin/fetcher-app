locals {
  common_labels = {
    app        = "fetcher"
    managed-by = "terraform"
  }

  # APIs the seed project needs to be a seed project: hold state, mint tokens,
  # manage policy and budgets. Nothing here creates a default service account.
  seed_services = toset([
    "cloudresourcemanager.googleapis.com", # projects and folders
    "serviceusage.googleapis.com",         # enabling other APIs
    "iam.googleapis.com",                  # service accounts
    "iamcredentials.googleapis.com",       # short-lived credentials
    "sts.googleapis.com",                  # the WIF token exchange itself
    "storage.googleapis.com",              # state bucket
    "orgpolicy.googleapis.com",            # the policy in org-policy.tf
    "billingbudgets.googleapis.com",       # the budget in budget.tf
    "monitoring.googleapis.com",           # budget notification channel
    # audit-logs.tf turns on DATA_READ/DATA_WRITE audit logging for storage here.
    # Those entries are written regardless, but reading them needs this API — and
    # an audit log you cannot read is not an audit log.
    "logging.googleapis.com",
  ])

  # Only what bootstrap itself needs on dev. Everything else dev needs is owned by
  # infra/envs/dev, which is applied by CI. Two configurations must never manage
  # the same google_project_service — split the list, don't overlap it.
  dev_bootstrap_services = toset([
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "iam.googleapis.com",
    "orgpolicy.googleapis.com",
  ])

  managed_projects = {
    seed = google_project.seed.project_id
    dev  = google_project.dev.project_id
  }
}

resource "google_folder" "fetcher" {
  display_name = var.folder_display_name
  parent       = "organizations/${var.org_id}"

  # A folder is cheap to create and catastrophic to delete — everything beneath it
  # goes too. Terraform-side protection as well as GCP-side.
  deletion_protection = true
}

# Why two projects rather than the brief's one (deviation D3):
# the seed project holds the things that must outlive any environment — state,
# the CI identity, the WIF pool. If dev is ever destroyed or rebuilt, none of that
# is at risk, and prod at M5 is a third project rather than a second bootstrap.
resource "google_project" "seed" {
  name            = "Fetcher Seed"
  project_id      = var.seed_project_id
  folder_id       = google_folder.fetcher.folder_id
  billing_account = var.billing_account
  labels          = merge(local.common_labels, { env = "seed" })

  # An auto-created default VPC gives you a subnet in every region with ranges you
  # did not choose and permissive default firewall rules. §8.2 wants a custom-mode
  # VPC; this is where you refuse the default one.
  auto_create_network = false

  # Terraform will not delete this project even if it is removed from config.
  deletion_policy = "PREVENT"
}

resource "google_project" "dev" {
  name            = "Fetcher Dev"
  project_id      = var.dev_project_id
  folder_id       = google_folder.fetcher.folder_id
  billing_account = var.billing_account
  labels          = merge(local.common_labels, { env = "dev" })

  auto_create_network = false
  deletion_policy     = "PREVENT"
}

module "seed_services" {
  source = "../modules/project-services"

  project_id = google_project.seed.project_id
  services   = local.seed_services
}

module "dev_services" {
  source = "../modules/project-services"

  project_id = google_project.dev.project_id
  services   = local.dev_bootstrap_services
}
