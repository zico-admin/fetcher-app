locals {
  # APIs owned by this environment.
  #
  # Four APIs are deliberately absent because infra/bootstrap already manages them
  # on this project: cloudresourcemanager, serviceusage, iam and orgpolicy. Two
  # Terraform configurations must never manage the same resource — the second one
  # to run would keep "fixing" the first one's work.
  #
  # M1 will add: compute, sqladmin, servicenetworking, artifactregistry,
  # secretmanager. Note that enabling compute is what creates the default compute
  # service account — which is why bootstrap enforces the org policy that strips
  # its automatic editor grant BEFORE that ever happens (§8.12).
  services = toset([
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "iamcredentials.googleapis.com",
  ])
}

module "project_services" {
  source = "../../modules/project-services"

  project_id = var.project_id
  services   = local.services
}
