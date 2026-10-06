output "seed_project_id" {
  description = "Seed project: state, CI identities, WIF pool."
  value       = google_project.seed.project_id
}

output "seed_project_number" {
  description = "Seed project number, which is what IAM principals and budgets use."
  value       = google_project.seed.number
}

output "dev_project_id" {
  description = "Dev workload project, managed by infra/envs/dev."
  value       = google_project.dev.project_id
}

output "folder_id" {
  description = "Folder holding every Fetcher project."
  value       = google_folder.fetcher.folder_id
}

output "state_bucket" {
  description = "Terraform state bucket. Hardcoded in each environment's backend.tf, since backends cannot take variables."
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Full provider resource name, passed to google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "tf_plan_service_account" {
  description = "Read-only CI identity used on pull requests."
  value       = google_service_account.tf_plan.email
}

output "tf_apply_service_account" {
  description = "CI identity used on main, reachable only from the apply environment."
  value       = google_service_account.tf_apply.email
}

output "github_repository_id" {
  description = "Numeric repository id pinned in the WIF attribute condition."
  value       = data.github_repository.fetcher.repo_id
}
