variable "project_id" {
  description = "Project that owns the VPC."
  type        = string
}

variable "network_name" {
  description = "Name of the custom-mode VPC."
  type        = string
}

variable "region" {
  description = "Region for the subnet and, if enabled, Cloud NAT."
  type        = string
}

variable "subnet_cidr" {
  description = "Primary range for the subnet. Must not overlap psa_cidr, and must leave room for ~2 addresses per Cloud Run instance using Direct VPC egress."
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be valid CIDR notation, for example 10.10.0.0/24."
  }
}

variable "psa_cidr" {
  description = "Range reserved for Private Service Access, from which Cloud SQL takes its private IP. Must not overlap subnet_cidr."
  type        = string

  validation {
    condition     = can(cidrhost(var.psa_cidr, 0))
    error_message = "psa_cidr must be valid CIDR notation, for example 10.10.16.0/20."
  }

  validation {
    condition     = tonumber(split("/", var.psa_cidr)[1]) <= 24
    error_message = "Google requires at least a /24 for Private Service Access; /20 or larger is recommended so future managed services fit."
  }
}

variable "routing_mode" {
  description = "REGIONAL keeps route advertisement within the region; GLOBAL advertises across all regions."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

variable "enable_flow_logs" {
  description = "VPC flow logs on the subnet. Useful for debugging connectivity, and billed per volume ingested."
  type        = bool
  default     = true
}

variable "flow_log_sampling" {
  description = "Fraction of flows sampled, 0 to 1. Lower costs less and still shows patterns."
  type        = number
  default     = 0.5

  validation {
    condition     = var.flow_log_sampling > 0 && var.flow_log_sampling <= 1
    error_message = "flow_log_sampling must be greater than 0 and at most 1."
  }
}

variable "enable_cloud_nat" {
  description = "Cloud Router plus Cloud NAT, so egress leaves from one stable IP. Off by default; it bills hourly whether used or not."
  type        = bool
  default     = false
}

variable "enable_firewall_logs" {
  description = "Log connections the default-deny rule blocks. Cheap at this scale and the difference between a silent drop and a diagnosable one."
  type        = bool
  default     = true
}
