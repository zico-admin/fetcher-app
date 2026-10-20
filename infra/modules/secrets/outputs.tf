output "secret_ids" {
  description = "Map of key to secret id, for referencing from Cloud Run secret environment variables."
  value       = { for k, s in google_secret_manager_secret.this : k => s.secret_id }
}

output "secret_names" {
  description = "Map of key to fully qualified secret resource name."
  value       = { for k, s in google_secret_manager_secret.this : k => s.name }
}

output "add_version_commands" {
  description = "The command to run for each secret to add its value, since the value deliberately never passes through Terraform."
  value = {
    for k, s in google_secret_manager_secret.this :
    k => "gcloud secrets versions add ${s.secret_id} --project=${var.project_id} --data-file=-"
  }
}
