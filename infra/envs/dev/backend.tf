terraform {
  # Backend configuration cannot use variables, locals, or any expression — it is
  # read before Terraform evaluates anything else. So the bucket name is a literal
  # here and in every other environment, and `prefix` is what keeps the state
  # files apart.
  #
  # This is also the concrete argument against workspaces (§5): each environment
  # is a separate directory with its own backend block and its own state file, so
  # there is no `terraform workspace select` that could point dev's configuration
  # at prod's state.
  backend "gcs" {
    bucket = "ogbn-fetcher-tfstate"
    prefix = "envs/dev"
  }
}
