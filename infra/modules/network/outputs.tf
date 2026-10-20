output "network_id" {
  description = "Fully qualified network id."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Network name."
  value       = google_compute_network.this.name
}

output "network_self_link" {
  description = "Network self link, which Cloud SQL's private_network field expects."
  value       = google_compute_network.this.self_link
}

output "subnet_id" {
  description = "Subnet id, for Cloud Run Direct VPC egress."
  value       = google_compute_subnetwork.this.id
}

output "subnet_name" {
  description = "Subnet name."
  value       = google_compute_subnetwork.this.name
}

output "subnet_cidr" {
  description = "Subnet primary range, echoed for firewall rules and documentation."
  value       = google_compute_subnetwork.this.ip_cidr_range
}

output "psa_range_name" {
  description = "Name of the reserved Private Service Access range."
  value       = google_compute_global_address.psa.name
}

output "psa_connection_id" {
  description = "Depend on this before creating any private-IP managed service: the instance cannot be created until the peering exists."
  value       = google_service_networking_connection.psa.id
}
