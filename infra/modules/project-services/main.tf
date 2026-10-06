resource "google_project_service" "this" {
  for_each = var.services

  project = var.project_id
  service = each.value

  # Leaving an API enabled when the resource is removed from config is the safe
  # default: disabling an API can break resources in the project that Terraform
  # does not manage, and re-enabling is free. §8.1 is explicit about this.
  disable_on_destroy = var.disable_on_destroy

  # Never cascade. Disabling dependent services is how one small change takes down
  # things nobody connected to it.
  disable_dependent_services = false
}

# API enablement is eventually consistent.
#
# A resource created in the same apply, seconds after its API was enabled, can
# fail with a permission error that looks like an IAM problem and is not. The
# usual symptom is a confusing 403 on the first apply that disappears on the
# second — which is exactly the kind of thing people "fix" by rerunning instead of
# understanding.
#
# Consumers depend on the `ready` output rather than on the services directly, so
# the wait is part of the dependency graph instead of a rerun.
resource "time_sleep" "settle" {
  create_duration = var.settle_duration

  # Re-wait whenever the set of enabled APIs changes, not only on first create.
  triggers = {
    services = join(",", sort(tolist(var.services)))
  }

  depends_on = [google_project_service.this]
}
