provider "google" {
  project = var.project_id
  region  = var.region

  # Bill API calls to THIS project, not to the one that owns the credentials.
  #
  # Without user_project_override, a Google API call is billed to the project
  # owning the service account making it — ogbn-fetcher-seed, where tf-apply
  # lives. Service Networking is enabled on dev and not on seed, so creating the
  # Private Service Access peering failed with:
  #
  #   Error 403: Service Networking API has not been used in project
  #   781463442713 before or it is disabled
  #
  # 781463442713 is seed. The API was enabled all along — on the wrong project
  # for where the call was being counted.
  #
  # This corrects two earlier mistakes rather than reverting one. PR #4 added the
  # override but pointed billing_project at seed, which would have failed here
  # for the same reason. PR #15 then removed it entirely, on the strength of an
  # experiment that only exercised google_project_service — which succeeded
  # because roles/browser fixed that path. The experiment's conclusion was too
  # broad: it proved what fixed one 403, not that the override did nothing.
  #
  # Pointing it at dev means calls are billed where the APIs are, and no
  # environment shares another's quota.
  billing_project       = var.project_id
  user_project_override = true

  # Applied to every resource that supports labels, so cost reports and audits can
  # group by environment without anyone remembering to tag. Set once, here, rather
  # than threaded through every module.
  default_labels = {
    app        = "fetcher"
    env        = var.environment
    managed-by = "terraform"
  }
}
