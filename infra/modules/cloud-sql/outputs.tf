output "instance_name" {
  description = "Instance name."
  value       = google_sql_database_instance.this.name
}

output "connection_name" {
  description = "project:region:instance — what the Cloud SQL connectors take, rather than a host and port."
  value       = google_sql_database_instance.this.connection_name
}

output "private_ip_address" {
  description = "Private IP allocated from the Private Service Access range. Reachable only from inside the VPC."
  value       = google_sql_database_instance.this.private_ip_address
}

output "self_link" {
  description = "Instance self link."
  value       = google_sql_database_instance.this.self_link
}

output "database_names" {
  description = "Databases created on the instance."
  value       = [for db in google_sql_database.this : db.name]
}

output "iam_user_names" {
  description = "Database user names as Cloud SQL stores them, with the .gserviceaccount.com suffix already removed. Use these in GRANT statements."
  value       = local.iam_user_names
}
