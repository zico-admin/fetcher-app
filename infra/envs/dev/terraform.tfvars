# Committed on purpose: nothing here is a secret, and CI needs it.
# Secrets never appear in tfvars — see infra/bootstrap for how the one human-held
# token is handled.

project_id  = "ogbn-fetcher-dev"
region      = "us-east4"
environment = "dev"

# Network addressing. Dev takes 10.10.0.0/16; 10.20.0.0/16 is reserved for prod
# so the two could be peered later without renumbering either.
subnet_cidr = "10.10.0.0/24"
psa_cidr    = "10.10.16.0/20"

# Database. Flip sql_activation_policy to NEVER between work sessions to stop
# paying for compute — storage still bills, and the data survives.
sql_tier              = "db-f1-micro"
sql_disk_size_gb      = 10
sql_activation_policy = "ALWAYS"
