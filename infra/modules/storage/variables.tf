variable "project_id" {
  description = "Project that owns the bucket."
  type        = string
}

variable "bucket_name" {
  description = "Bucket name. Globally unique across all of Google Cloud Storage and permanent."
  type        = string
}

variable "location" {
  description = "Bucket location. A region costs less than a multi-region and is the right default for data you can regenerate."
  type        = string
}

variable "lifecycle_age_days" {
  description = "Delete objects older than this many days. Zero disables the rule."
  type        = number
  default     = 90

  validation {
    condition     = var.lifecycle_age_days >= 0
    error_message = "lifecycle_age_days must be zero (disabled) or positive."
  }
}

variable "versioning" {
  description = "Object versioning. Worth it for state and configuration; usually not for regenerable snapshots."
  type        = bool
  default     = false
}

variable "keep_noncurrent_versions" {
  description = "How many superseded versions to keep when versioning is on."
  type        = number
  default     = 5
}

variable "force_destroy" {
  description = "Allow Terraform to delete a bucket that still contains objects. Leave false unless you mean it."
  type        = bool
  default     = false
}

variable "writers" {
  description = "IAM members granted object read, write and delete — not bucket administration."
  type        = set(string)
  default     = []
}

variable "readers" {
  description = "IAM members granted read-only object access."
  type        = set(string)
  default     = []
}

variable "labels" {
  description = "Labels applied to the bucket."
  type        = map(string)
  default     = {}
}
