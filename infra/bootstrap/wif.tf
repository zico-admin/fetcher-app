# Workload Identity Federation — the highest-stakes twenty lines in the repo (§6).
#
# GitHub Actions presents a short-lived OIDC token; GCP exchanges it for a
# short-lived access token. There is no service account key to leak, rotate, or
# commit. Long-lived SA keys are the most common cause of real GCP compromise.

data "github_repository" "fetcher" {
  full_name = "${var.github_owner}/${var.github_repo}"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = google_project.seed.project_id
  workload_identity_pool_id = "fetcher-github"
  display_name              = "Fetcher GitHub"
  description               = "Keyless OIDC federation for GitHub Actions in ${var.github_owner}/${var.github_repo}."

  depends_on = [module.seed_services]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = google_project.seed.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub Actions OIDC"

  # checkov:skip=CKV_GCP_125:The check requires the literal pattern `assertion.sub == "repo:owner/name:..."`. Pinning the immutable numeric repository_id is strictly stronger (names are re-registerable, ids are never reissued), and a single sub equality cannot work here because plan and apply are deliberately different subjects — each is pinned on its own service account binding in ci-service-accounts.tf.

  # THE line that matters.
  #
  # Without a condition — or with attribute.repository/* in a binding — any
  # GitHub repository on earth can mint a token for these service accounts. That
  # is a live vulnerability, not a style note.
  #
  # Pinned to the numeric repository id rather than "owner/name" because names are
  # reusable: delete or rename a repo and someone else can register the name, and
  # a name-based condition would then trust the impostor. Numeric ids are never
  # reissued. The id comes from the API via the data source above, so it is never
  # a hand-copied number that silently goes stale.
  attribute_condition = "assertion.repository_id == \"${data.github_repository.fetcher.repo_id}\""

  attribute_mapping = {
    # sub is the tightest identifier GitHub issues. For a job running in an
    # environment it reads: repo:OWNER/REPO:environment:NAME — which is exactly
    # what the apply binding below keys on.
    "google.subject" = "assertion.sub"

    "attribute.repository"    = "assertion.repository"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
    "attribute.event_name"    = "assertion.event_name"

    # Deliberately NOT mapping assertion.environment. The claim is absent on jobs
    # that declare no environment, and a mapping that references a missing claim
    # fails the whole token exchange — which would break every PR plan. The apply
    # identity gets its environment guarantee from google.subject instead.
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
