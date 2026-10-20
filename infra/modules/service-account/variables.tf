variable "project_id" {
  description = "Project that owns the service account and grants its roles."
  type        = string
}

variable "account_id" {
  description = "Short id, the part before the @ in the email. Six to thirty lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.account_id))
    error_message = "account_id must be 6-30 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "display_name" {
  description = "Human-readable name shown in the console."
  type        = string
}

variable "description" {
  description = "What this workload is and why it needs an identity. Future you will want this."
  type        = string
  default     = ""
}

variable "project_roles" {
  description = "Roles granted to this account on project_id. Keep this list earned from denials, not guessed."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for r in var.project_roles : !contains(["roles/owner", "roles/editor", "roles/viewer"], r)
    ])
    error_message = "Basic roles are not allowed on a workload identity. Grant a predefined or custom role that names the permissions it needs."
  }
}

variable "impersonators" {
  description = "Members granted roles/iam.serviceAccountTokenCreator on this account, as fully qualified IAM members."
  type        = set(string)
  default     = []
}
