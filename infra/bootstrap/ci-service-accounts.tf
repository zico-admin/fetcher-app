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

# Apply is bound to an exact subject: a job running in the tf-apply environment.
# `principal://` with a full subject, not `principalSet://` with an attribute —
# this is a single identity, not a set.
#
# The useful consequence: the required reviewer on that environment is enforced by
# the token exchange itself. A workflow that forgets `environment: tf-apply`
# cannot authenticate at all, rather than quietly applying without review.
#
# Two subjects, because GitHub does not issue the subject its own documentation
# describes. Observed in the token on 2026-10-06:
#
#   repo:zico-admin@199652266/fetcher-app@1370482956:environment:tf-apply
#
# rather than the documented:
#
#   repo:zico-admin/fetcher-app:environment:tf-apply
#
# GitHub has started embedding the numeric owner and repository ids in the
# subject — the same defence against name reuse that this repo applies in the
# provider's attribute_condition. Binding both forms means a rollout in either
# direction cannot lock the apply identity out. Neither is weaker: both name one
# exact job in one exact repository in one exact environment.
#
# The ids come from the API via data sources, so no numeric id is hand-copied.
locals {
  tf_apply_subjects = toset([
    # Current: ids embedded.
    "repo:${var.github_owner}@${data.github_user.admin.id}/${var.github_repo}@${data.github_repository.fetcher.repo_id}:environment:${var.tf_apply_environment}",
    # Documented, and what GitHub issued historically.
    "repo:${var.github_owner}/${var.github_repo}:environment:${var.tf_apply_environment}",
  ])
}

resource "google_service_account_iam_member" "tf_apply_wif" {
  for_each = local.tf_apply_subjects

  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${each.value}"
}

# The binding above went from one resource to a keyed set. Without this, Terraform
# would destroy the existing binding and create a new one; the moved block tells it
# the resource simply has a new address (§5). The key must be a literal, so the
# historical subject is spelled out here rather than interpolated.
moved {
  from = google_service_account_iam_member.tf_apply_wif
  to   = google_service_account_iam_member.tf_apply_wif["repo:zico-admin/fetcher-app:environment:tf-apply"]
}

# --- What they may do ---------------------------------------------------------

locals {
  # Read-only. roles/viewer covers most resources; securityReviewer adds the
  # ability to read IAM policies, which plain viewer cannot, and which a plan of
  # any IAM resource needs.
  tf_plan_roles = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",

    # With user_project_override, every API call a plan makes is billed to the
    # dev project, and billing a call requires serviceusage.services.use there.
    # roles/viewer does not carry it. This is the read-only twin of the
    # serviceUsageAdmin that tf-apply already holds.
    "roles/serviceusage.serviceUsageConsumer",
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

    # Added M0, from a denial rather than a guess.
    #
    # The apply failed with "Error when reading or editing Project Service
    # ogbn-fetcher-dev/logging.googleapis.com: 403". Reading the role showed why:
    # serviceUsageAdmin grants serviceusage.services.enable/get/list but NOT
    # resourcemanager.projects.get, and the provider reads the project while
    # reconciling every google_project_service.
    #
    # Proven, not assumed: PR #15 removed the competing fix (user_project_override
    # billing dev's API calls to the seed project) and the apply on main still
    # succeeded. This role is what carries it.
    #
    # roles/browser is the narrowest predefined role containing it: read-only
    # metadata about projects, folders and the org, and nothing else. Narrower
    # than roles/viewer, which would grant read on every resource in the project.
    # A custom role with the single permission would be narrower still; it is not
    # worth the maintenance here, because every later milestone needs this same
    # project read.
    "roles/browser",

    # ---- M1 -----------------------------------------------------------------
    # Predicted from what the M1 resources touch, not from denials, because
    # discovering eight roles one failed apply at a time would cost eight local
    # bootstrap applies. The loop still happens for whatever is missing here, and
    # anything that turns out to be unnecessary should be deleted rather than
    # left behind "just in case" — an unused grant is still a grant.
    "roles/compute.networkAdmin",            # VPC, subnet, PSA global address, router/NAT
    "roles/servicenetworking.networksAdmin", # the service networking peering
    "roles/cloudsql.admin",                  # instance, databases, IAM database users
    "roles/artifactregistry.admin",          # repository and its IAM
    "roles/secretmanager.admin",             # secret containers and their IAM, never values
    "roles/storage.admin",                   # the menu snapshots bucket and its IAM
    "roles/iam.serviceAccountAdmin",         # create run-web and run-job

    # Added from a denial: "Required 'compute.firewalls.create' permission".
    # compute.networkAdmin manages networks, subnets and routes but has
    # read-only access to firewall rules — confirmed by reading the role, which
    # contains compute.firewalls.get and .list and not .create. Firewall changes
    # are a security boundary, so Google puts them in a separate role.
    "roles/compute.securityAdmin",
  ])

  # Roles the apply identity is allowed to grant to workload service accounts.
  # Anything not on this list is refused by the IAM condition below.
  tf_apply_grantable_roles = [
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor",
    "roles/run.invoker",
    "roles/aiplatform.user",
  ]
}

resource "google_project_iam_member" "tf_plan_dev" {
  # checkov:skip=CKV_GCP_117:Basic roles are flagged because editor and owner grant write access. roles/viewer is read-only, and a plan must be able to read every resource type the configuration manages. The alternative — a custom role enumerating every *.get and *.list permission — would drift silently every time a new resource type is added. roles/editor and roles/owner appear nowhere in this repo.
  for_each = local.tf_plan_roles

  project = google_project.dev.project_id
  role    = each.value
  member  = google_service_account.tf_plan.member
}

resource "google_project_iam_member" "tf_apply_dev" {
  # checkov:skip=CKV_GCP_49:roles/iam.serviceAccountAdmin is how CI creates the run-web and run-job identities — that work has to belong to Terraform, or workload identities become console artifacts nobody can rebuild. The real risk the check points at, privilege escalation by granting itself a role, is addressed separately: the projectIamAdmin grant below is conditional on an explicit allowlist, so this account cannot grant roles/owner to anything, including itself.
  for_each = local.tf_apply_roles

  project = google_project.dev.project_id
  role    = each.value
  member  = google_service_account.tf_apply.member
}

# The most dangerous grant in the repo, and the reason it is conditional.
#
# Managing IAM requires resourcemanager.projectIamAdmin, and an identity holding
# it unconditionally can grant itself roles/owner — so "least privilege CI" would
# be a fiction. The condition limits WHICH roles it may grant: modifiedGrantsByRole
# is evaluated against the roles touched by the call, and hasOnly() refuses the
# request outright if it touches anything else.
#
# Concretely: tf-apply can grant roles/cloudsql.client to run-web, and cannot
# grant roles/owner to anyone, including itself.
#
# Expect to extend tf_apply_grantable_roles as later milestones add workloads.
# Each addition is a deliberate decision recorded in a diff, which is the point.
resource "google_project_iam_member" "tf_apply_iam_admin" {
  project = google_project.dev.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = google_service_account.tf_apply.member

  condition {
    title       = "only-workload-roles"
    description = "May grant only the specific roles Fetcher workloads need."
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", formatlist("'%s'", local.tf_apply_grantable_roles))}])"
  }
}
