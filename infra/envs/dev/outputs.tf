output "project_id" {
  description = "Dev project id."
  value       = var.project_id
}

output "enabled_services" {
  description = "APIs this environment manages."
  value       = keys(module.project_services.enabled_services)
}

output "network_name" {
  description = "Custom-mode VPC."
  value       = module.network.network_name
}

output "sql_connection_name" {
  description = "project:region:instance, which the Cloud SQL connector takes instead of a host and port."
  value       = module.cloud_sql.connection_name
}

output "sql_private_ip" {
  description = "Private IP of the database. Reachable only from inside the VPC — there is no public address."
  value       = module.cloud_sql.private_ip_address
}

output "sql_iam_user_names" {
  description = "Database user names as Cloud SQL stores them, with the .gserviceaccount.com suffix removed. These are the names to use in GRANT statements."
  value       = module.cloud_sql.iam_user_names
}

output "artifact_registry_url" {
  description = "Prefix for image names. Tag with the commit SHA, never latest."
  value       = module.artifact_registry.repository_url
}

output "menu_snapshots_bucket" {
  description = "Bucket holding raw menu HTML and PDFs."
  value       = module.menu_snapshots.bucket_name
}

output "secret_value_commands" {
  description = "How to add each secret's value, since values deliberately never pass through Terraform."
  value       = module.secrets.add_version_commands
}

output "run_service_accounts" {
  description = "Workload identities, for reference when granting further access."
  value = {
    web = module.sa_run_web.email
    job = module.sa_run_job.email
  }
}
