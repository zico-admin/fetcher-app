# Two CI identities, not one (deviation D4).
#
# Plans run against pull request code and need to read everything. Applies change
# the world and are gated by a human. One service account cannot be least
# privilege for both jobs, so there are two, and only one of them can write.

resource "google_service_account" "tf_plan" {
  project      = google_project.seed.project_id
  account_id   = "tf-plan"
  display_name = "Terraform plan (read-only, CI)"
  description  = "Assumed by GitHub Actions on pull requests. Must never be able to change anything."

  depends_on = [module.seed_services]
}

resource "google_service_account" "tf_apply" {
  project      = google_project.seed.project_id
  account_id   = "tf-apply"
  display_name = "Terraform apply (CI)"
  description  = "Assumed by GitHub Actions on main, only from the ${var.tf_apply_environment} environment."

  depends_on = [module.seed_services]
}

# --- Who may impersonate them -------------------------------------------------

# Any job in this repository may plan. The provider-level attribute_condition has
# already established that the token came from this exact repository id.
resource "google_service_account_iam_member" "tf_plan_wif" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_id/${data.github_repository.fetcher.repo_id}"
}

# Apply is bound to ONE exact subject: a job running in the tf-apply environment.
# `principal://` with a full subject, not `principalSet://` with an attribute —
# this is a single identity, not a set.
#
# The useful consequence: the required reviewer on that environment is enforced by
# the token exchange itself. A workflow that forgets `environment: tf-apply`
# cannot authenticate at all, rather than quietly applying without review.
resource "google_service_account_iam_member" "tf_apply_wif" {
  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/repo:${var.github_owner}/${var.github_repo}:environment:${var.tf_apply_environment}"
}

# --- What they may do ---------------------------------------------------------

locals {
  # Read-only. roles/viewer covers most resources; securityReviewer adds the
  # ability to read IAM policies, which plain viewer cannot, and which a plan of
  # any IAM resource needs.
  tf_plan_roles = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",
  ])

  # M0 ONLY.
  #
  # infra/envs/dev currently manages exactly one thing: enabled APIs. So the apply
  # identity gets exactly one role. Every later milestone adds the roles its own
  # resources demand, read from the actual permission denial rather than guessed
  # (§8.12). The commit history of this list is the least-privilege exercise.
  #
  # When M1 lands expect to add, roughly: compute.networkAdmin, cloudsql.admin,
  # artifactregistry.admin, secretmanager.admin, storage.admin,
  # iam.serviceAccountAdmin, resourcemanager.projectIamAdmin. Do not add them now.
  tf_apply_roles = toset([
    "roles/serviceusage.serviceUsageAdmin",
  ])
}

resource "google_project_iam_member" "tf_plan_dev" {
  # checkov:skip=CKV_GCP_117:Basic roles are flagged because editor and owner grant write access. roles/viewer is read-only, and a plan must be able to read every resource type the configuration manages. The alternative — a custom role enumerating every *.get and *.list permission — would drift silently every time a new resource type is added. roles/editor and roles/owner appear nowhere in this repo.
  for_each = local.tf_plan_roles

  project = google_project.dev.project_id
  role    = each.value
  member  = google_service_account.tf_plan.member
}

resource "google_project_iam_member" "tf_apply_dev" {
  for_each = local.tf_apply_roles

  project = google_project.dev.project_id
  role    = each.value
  member  = google_service_account.tf_apply.member
}
