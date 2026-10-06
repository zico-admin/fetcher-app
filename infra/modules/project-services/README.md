# project-services

Enables a set of Google Cloud APIs on one project, and gives callers something
safe to depend on while enablement settles.

## Why this is a module at all

API enablement is infrastructure. If APIs are switched on by console click, a
fresh project cannot be rebuilt from this repository, and nobody can answer "what
does this project actually use?" without clicking through a UI (§8.1).

## Why `ready` exists

Enabling an API is eventually consistent. A resource created seconds after its
API is enabled can fail with a permission error that looks like an IAM problem
and is not — the usual tell is a 403 on the first apply that vanishes on the
second. Depending on `module.x.ready` instead of on the services puts the wait
inside the dependency graph, so a clean apply does not depend on rerunning it.

## Usage

```hcl
module "project_services" {
  source = "../../modules/project-services"

  project_id = var.project_id
  services = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
  ])
}

resource "google_cloud_run_v2_service" "web" {
  # ...
  depends_on = [module.project_services] # resolves only after `ready`
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | Project whose APIs are managed. |
| `services` | `set(string)` | — | Fully qualified API names, validated to end in `.googleapis.com`. |
| `disable_on_destroy` | `bool` | `false` | Whether removing a service disables the API. |
| `settle_duration` | `string` | `"60s"` | Wait after enabling, to absorb eventual consistency. |

## Outputs

| Name | Description |
|---|---|
| `enabled_services` | Map of API name to resource id. |
| `ready` | Depend on this rather than on the services themselves. |
| `project_id` | Echoed back for chaining. |

## Notes

- `for_each`, not `count`: APIs are addressed by name, so removing one from the
  middle of the set does not churn the others (§5).
- No `provider` block. Configuration belongs to the caller.
