resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}

# One dedicated service account per workload, each with only the roles that
# workload needs (§8.12). Never the default compute account — which, on these
# projects, no longer carries roles/editor either (see ADR 0002).
resource "google_project_iam_member" "roles" {
  for_each = var.project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.this.member
}

# google_project_iam_member is additive and leaves bindings it does not know
# about alone. google_project_iam_policy would be authoritative and would delete
# every binding absent from config — including yours. The difference is a
# production outage.

resource "google_service_account_iam_member" "impersonators" {
  for_each = var.impersonators

  service_account_id = google_service_account.this.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}
