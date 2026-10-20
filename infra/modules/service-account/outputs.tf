output "email" {
  description = "Service account email address."
  value       = google_service_account.this.email
}

output "member" {
  description = "IAM member string, serviceAccount:<email>, for use in bindings."
  value       = google_service_account.this.member
}

output "name" {
  description = "Fully qualified resource name, for service-account-level IAM bindings."
  value       = google_service_account.this.name
}

output "sql_user_name" {
  description = "The email with .gserviceaccount.com removed — the form Cloud SQL for PostgreSQL requires for an IAM service account database user."
  value       = trimsuffix(google_service_account.this.email, ".gserviceaccount.com")
}
