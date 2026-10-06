# The single most important GCP security setting in this repo (§8.12).
#
# Enabling compute.googleapis.com creates a default compute service account AND
# grants it roles/editor. Anything running as it can do almost anything. This
# policy switches that automatic grant off.
#
# ---------------------------------------------------------------------------
# Why this is on the FOLDER and not on each project
# ---------------------------------------------------------------------------
# It was project-scoped first, to keep the blast radius off the rest of
# ogbonna.net. That does not work, and the reason is worth keeping:
#
# The policy only affects service accounts created AFTER it is enforced. A
# project-level policy cannot exist until its project exists — and compute is
# enabled *during* project creation, because `auto_create_network = false` makes
# the provider create the default network and then delete it. The provider
# schema says so outright: "the network will exist momentarily". A network means
# compute, compute means a default service account, and that account is granted
# editor before any project-level policy could possibly be written.
#
# Both projects were created with the privileged default account for exactly
# this reason. Measured, not assumed:
#
#   roles/editor  serviceAccount:582048530189-compute@developer.gserviceaccount.com
#
# A folder-level policy is inherited by projects at the moment they are created,
# so it wins the race. The blast radius is still just the fetcher folder.
#
# The seed project is the one exception: it must exist before this policy can be
# written, because setting a folder policy is an API call that has to bill quota
# to some project. Its default account is deprivileged below instead.
resource "google_org_policy_policy" "no_automatic_iam_grants" {
  provider = google.seed_quota

  name   = "folders/${google_folder.fetcher.folder_id}/policies/iam.automaticIamGrantsForDefaultServiceAccounts"
  parent = "folders/${google_folder.fetcher.folder_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }

  # The Org Policy API must be enabled on the project paying for the call.
  depends_on = [module.seed_services]
}

# Remediation for default accounts that already exist, and a safety net for any
# the policy misses — the seed project's, above all.
#
# DEPRIVILEGE strips roles/editor and leaves the account in place. DISABLE would
# be stronger, but these projects are young and a disabled default account
# produces confusing failures in services that quietly rely on it; the editor
# grant is the actual danger, and this removes it.
#
# restore_policy = "NONE": if this resource is ever removed, do not hand editor
# back. An undo that re-grants the most dangerous role in the project is not an
# undo anyone wants.
resource "google_project_default_service_accounts" "deprivilege" {
  for_each = local.managed_projects

  project        = each.value
  action         = "DEPRIVILEGE"
  restore_policy = "NONE"

  depends_on = [google_org_policy_policy.no_automatic_iam_grants]
}
