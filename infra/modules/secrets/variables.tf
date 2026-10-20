variable "project_id" {
  description = "Project that owns the secrets."
  type        = string
}

variable "secrets" {
  description = "Secrets to create, keyed by a stable name. Values are never managed here — only the container and who may read it."
  type = map(object({
    secret_id             = string
    accessors             = optional(list(string), [])
    replication_locations = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.secrets) : length(s.replication_locations) > 0])
    error_message = "Give each secret at least one replication location; an empty list would leave the secret unreplicated and unreadable."
  }
}

variable "labels" {
  description = "Labels applied to every secret."
  type        = map(string)
  default     = {}
}
