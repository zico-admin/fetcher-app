output "repository_id" {
  description = "Repository id as configured."
  value       = google_artifact_registry_repository.this.repository_id
}

output "repository_name" {
  description = "Fully qualified repository resource name."
  value       = google_artifact_registry_repository.this.name
}

output "repository_url" {
  description = "Host and path to prefix image names with, e.g. us-east4-docker.pkg.dev/project/repo. Tag images with the commit SHA, never latest (§7)."
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}"
}
