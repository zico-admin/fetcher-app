# No `project` on the default provider, deliberately.
#
# Bootstrap *creates* the projects, so at plan time there is no "current project"
# to point at. Every resource in this directory therefore sets `project`
# explicitly. If you ever see a resource here without one, it is a bug, not a
# shortcut.
provider "google" {
  region = var.region
}

# A second, aliased provider for the two APIs that are NOT billed to the project
# holding the resource:
#
#   - Org Policy    (resource lives on a project, call is billed to a quota project)
#   - Billing Budget (resource lives on a *billing account*, which has no project)
#
# Those calls need `user_project_override` plus a `billing_project` that has the
# relevant API enabled. This is the generalised version of the problem that
# blocked reading org policies before bootstrap existed: an org-level or
# billing-level API call still has to bill quota somewhere.
#
# `billing_project` is a plain variable, not a resource attribute, on purpose. A
# provider configuration that depends on a resource created by that same provider
# is unknown at plan time and Terraform will refuse it. Because we *choose* the
# project id rather than letting GCP generate one, the value is known statically
# and the cycle disappears.
provider "google" {
  alias                 = "seed_quota"
  region                = var.region
  billing_project       = var.seed_project_id
  user_project_override = true
}

# The GitHub provider manages repo settings, the apply environment, branch
# protection and Actions variables — the same "if it isn't in code, it doesn't
# exist" rule applied to the other half of the system.
#
# The token is read from TF_VAR_github_token and is never committed and never
# reaches CI. Bootstrap is applied by a human, by design (§6).
provider "github" {
  owner = var.github_owner
  token = var.github_token
}
