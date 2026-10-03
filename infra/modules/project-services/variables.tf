variable "project_id" {
  description = "Project whose APIs are managed. Nothing in this module is hardcoded to one project or region (§5)."
  type        = string
}

variable "services" {
  description = "Fully qualified API names, e.g. run.googleapis.com. A set, so ordering never shows up as a diff."
  type        = set(string)

  validation {
    condition     = alltrue([for s in var.services : can(regex("\\.googleapis\\.com$", s))])
    error_message = "Each service must be a fully qualified API name ending in .googleapis.com."
  }
}

variable "disable_on_destroy" {
  description = "Whether removing a service from the set disables the API. Keep false unless you know what else uses it."
  type        = bool
  default     = false
}

variable "settle_duration" {
  description = "How long to wait after enabling APIs before dependents are created, to absorb eventual consistency."
  type        = string
  default     = "60s"

  validation {
    condition     = can(regex("^[0-9]+(s|m)$", var.settle_duration))
    error_message = "Duration must look like 30s or 2m."
  }
}
