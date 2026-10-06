# Committed on purpose: nothing here is a secret, and CI needs it.
# Secrets never appear in tfvars — see infra/bootstrap for how the one human-held
# token is handled.

project_id  = "ogbn-fetcher-dev"
region      = "us-east4"
environment = "dev"
