# The GitHub side of the system is infrastructure too, so it is code as well.
#
# The repository already exists, so it is ADOPTED with an import block rather than
# `terraform import` at the CLI (§5). The difference matters: this block is
# reviewable in a pull request and reproducible by anyone who clones the repo,
# where a CLI import is an invisible act of the one person who ran it.
#
# Once the import has applied, the block can be deleted — the resource stays in
# state. Leaving it is harmless and documents how the resource got there.
import {
  to = github_repository.fetcher
  id = var.github_repo
}

resource "github_repository" "fetcher" {
  # checkov:skip=CKV_GIT_1:Public is a deliberate choice. GitHub only offers required-reviewer environment protection on private repositories under Enterprise plans, and that reviewer gate is what guards terraform apply. Nothing confidential lives in the repo: no state, no keys, no secret values — only project ids and service account emails, which are identifiers rather than credentials.
  name        = var.github_repo
  description = "Fetcher — where to eat and what to order, for travellers eating to a goal."

  # Public, decided at sign-off. The practical consequence for CI: pull requests
  # from forks never receive an OIDC token, so the plan job cannot be used by a
  # stranger to read your infrastructure. The plan workflow skips fork PRs anyway.
  visibility = "public"

  has_issues   = true
  has_wiki     = false
  has_projects = false

  # Keep history linear and the branch list clean.
  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = false
  delete_branch_on_merge = true

  lifecycle {
    prevent_destroy = true
  }
}

# Its own resource rather than the repository's deprecated `vulnerability_alerts`
# argument, which the provider warns about and will remove.
resource "github_repository_vulnerability_alerts" "fetcher" {
  repository = github_repository.fetcher.name
  enabled    = true
}

data "github_user" "admin" {
  username = var.github_owner
}

# The gate in front of terraform apply.
#
# Pairs with the WIF binding in ci-service-accounts.tf: the apply service account
# can only be impersonated by a job running in THIS environment, so the reviewer
# requirement is enforced by GCP's token exchange and not merely by GitHub's UI.
resource "github_repository_environment" "tf_apply" {
  repository  = github_repository.fetcher.name
  environment = var.tf_apply_environment

  reviewers {
    users = [data.github_user.admin.id]
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

# Branch protection, with one deliberate omission: no required approving reviews.
#
# GitHub does not let you approve your own pull request, so on a solo repository
# "require 1 approval" means nothing can ever merge. The real gate is the apply
# environment above, which you approve as a deployment rather than as a review.
# What IS required here is that the plan succeeded.
resource "github_branch_protection" "main" {
  # checkov:skip=CKV_GIT_5:Two approving reviews is impossible on a single-maintainer repository — GitHub forbids approving your own pull request, so any non-zero requirement would mean nothing can ever merge. The equivalent control here is the tf-apply environment, which requires a human deployment approval that GCP's token exchange also enforces.
  # checkov:skip=CKV_GIT_6:Signed commits are worth enabling, but turning them on before commit signing is configured on the machine would block every merge. Tracked as a follow-up for M1, once an SSH or GPG signing key is set up.
  repository_id = github_repository.fetcher.node_id
  pattern       = "main"

  required_status_checks {
    strict   = true
    contexts = ["plan"]
  }

  # Direct pushes to main are blocked; changes arrive through pull requests.
  required_pull_request_reviews {
    required_approving_review_count = 0
    dismiss_stale_reviews           = true
  }

  # Left false so you can rescue a broken main without surgery on this file.
  # Revisit once anything real depends on this repository.
  enforce_admins = false
}

# Values CI needs to authenticate. Variables, not secrets — none of these are
# confidential, and writing them from Terraform means the workflow never contains
# a hand-copied project number that goes stale after a rebuild.
resource "github_actions_variable" "gcp_workload_identity_provider" {
  repository    = github_repository.fetcher.name
  variable_name = "GCP_WORKLOAD_IDENTITY_PROVIDER"
  value         = google_iam_workload_identity_pool_provider.github.name
}

resource "github_actions_variable" "gcp_tf_plan_sa" {
  repository    = github_repository.fetcher.name
  variable_name = "GCP_TF_PLAN_SA"
  value         = google_service_account.tf_plan.email
}

resource "github_actions_variable" "gcp_tf_apply_sa" {
  repository    = github_repository.fetcher.name
  variable_name = "GCP_TF_APPLY_SA"
  value         = google_service_account.tf_apply.email
}

resource "github_actions_variable" "gcp_dev_project_id" {
  repository    = github_repository.fetcher.name
  variable_name = "GCP_DEV_PROJECT_ID"
  value         = google_project.dev.project_id
}
