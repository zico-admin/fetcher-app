output "project_id" {
  description = "Dev project id."
  value       = var.project_id
}

output "enabled_services" {
  description = "APIs this environment manages."
  value       = keys(module.project_services.enabled_services)
}
