output "enabled_services" {
  description = "Map of API name to the google_project_service resource id."
  value       = { for k, v in google_project_service.this : k => v.id }
}

output "ready" {
  description = "Depend on this, not on the services themselves: it resolves only after the settle wait has elapsed."
  value       = time_sleep.settle.id
}

output "project_id" {
  description = "Echoed back so callers can chain without repeating themselves."
  value       = var.project_id
}
