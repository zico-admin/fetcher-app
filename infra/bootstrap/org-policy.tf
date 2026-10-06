# The single most important GCP security setting in this repo (§8.12).
#
# When you enable compute.googleapis.com, GCP creates a default compute service
# account AND grants it roles/editor on the project. Anything running as it can do
# almost anything. This policy switches that automatic grant off.
#
# Ordering is the whole point, and it is easy to get wrong: the policy only affects
# service accounts created AFTER it is enforced. The default compute SA is created
# the moment compute.googleapis.com is enabled — which happens in infra/envs/dev at
# M1, long after this applies. Enforce it here, in bootstrap, or it is decorative.
#
# Scoped to the Fetcher projects, not the whole organization: ogbonna.net contains
# other projects that did not ask for this and might break.
resource "google_org_policy_policy" "no_automatic_iam_grants" {
  provider = google.seed_quota
  for_each = local.managed_projects

  name   = "projects/${each.value}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = "projects/${each.value}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  # The Org Policy API has to be enabled before it can be called, on both the
  # project being managed and the project paying for the call.
  depends_on = [
    module.seed_services,
    module.dev_services,
  ]
}
