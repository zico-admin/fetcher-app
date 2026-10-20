variable "project_id" {
  description = "Project that owns the repository."
  type        = string
}

variable "region" {
  description = "Region for the repository. Keep it with the Cloud Run service that pulls from it: cross-region pulls add cold-start latency and egress cost."
  type        = string
}

variable "repository_id" {
  description = "Repository name, the last path segment of an image reference."
  type        = string
}

variable "description" {
  description = "What this repository holds."
  type        = string
  default     = ""
}

variable "keep_recent_count" {
  description = "How many recent image versions to keep regardless of the deletion rule, so a rollback target always exists."
  type        = number
  default     = 20

  validation {
    condition     = var.keep_recent_count >= 5
    error_message = "Keep at least 5 versions; fewer leaves no room to roll back past a bad deploy."
  }
}

variable "untagged_older_than" {
  description = "Age after which untagged images are deleted, as a duration string such as 604800s (7 days)."
  type        = string
  default     = "604800s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.untagged_older_than))
    error_message = "Express the age in seconds with a trailing s, for example 604800s."
  }
}

variable "cleanup_dry_run" {
  description = "Log what the cleanup policies would delete without deleting it. Useful for one cycle before trusting them."
  type        = bool
  default     = false
}

variable "writers" {
  description = "IAM members allowed to push images — the CI deploy identity, and nothing else."
  type        = set(string)
  default     = []
}

variable "readers" {
  description = "IAM members allowed to pull images — the Cloud Run runtime service accounts."
  type        = set(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the repository."
  type        = map(string)
  default     = {}
}
