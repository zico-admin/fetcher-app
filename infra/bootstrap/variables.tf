variable "org_id" {
  description = "Numeric GCP organization id that owns the fetcher folder."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be the numeric organization id, not the domain name."
  }
}

variable "billing_account" {
  description = "Billing account id in XXXXXX-XXXXXX-XXXXXX form."
  type        = string

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account must look like XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "folder_display_name" {
  description = "Display name of the folder holding every Fetcher project."
  type        = string
  default     = "fetcher"
}

variable "seed_project_id" {
  description = "Project id for the seed project: state bucket, WIF, CI identities. Globally unique and permanent."
  type        = string
  default     = "ogbn-fetcher-seed"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.seed_project_id))
    error_message = "Project ids are 6-30 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "dev_project_id" {
  description = "Project id for the dev workload project. Globally unique and permanent."
  type        = string
  default     = "ogbn-fetcher-dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.dev_project_id))
    error_message = "Project ids are 6-30 chars, lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Default region for regional resources."
  type        = string
  default     = "us-east4"
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. Globally unique across all of GCS."
  type        = string
  default     = "ogbn-fetcher-tfstate"
}

variable "state_bucket_noncurrent_versions" {
  description = "How many noncurrent (superseded) state versions to keep before deletion."
  type        = number
  default     = 30

  validation {
    condition     = var.state_bucket_noncurrent_versions >= 5 && var.state_bucket_noncurrent_versions <= 365
    error_message = "Keep between 5 and 365 noncurrent versions; fewer than 5 makes recovery from a bad apply unlikely."
  }
}

variable "github_owner" {
  description = "GitHub account that owns the repository."
  type        = string
  default     = "zico-admin"
}

variable "github_repo" {
  description = "Repository name, without the owner."
  type        = string
  default     = "fetcher-app"
}

variable "github_token" {
  description = "Fine-grained GitHub PAT used only by this bootstrap apply. Never stored, never sent to CI."
  type        = string
  sensitive   = true
}

variable "tf_apply_environment" {
  description = "Name of the GitHub environment that gates terraform apply. Appears verbatim in the WIF subject, so changing it changes who can apply."
  type        = string
  default     = "tf-apply"
}

variable "admin_email" {
  description = "Human owner. Gets state bucket access, alert emails and budget notifications."
  type        = string
  default     = "you@example.com"

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be an email address."
  }
}

variable "budget_amount_usd" {
  description = "Monthly budget in whole USD across every Fetcher project."
  type        = number
  default     = 50

  validation {
    condition     = var.budget_amount_usd > 0 && var.budget_amount_usd <= 1000
    error_message = "Budget must be between 1 and 1000 USD; above that you have almost certainly made a mistake."
  }
}

variable "budget_threshold_percents" {
  description = "Fractions of the budget at which to alert."
  type        = list(number)
  default     = [0.5, 0.9, 1.0]

  validation {
    condition     = alltrue([for t in var.budget_threshold_percents : t > 0 && t <= 1])
    error_message = "Thresholds are fractions between 0 and 1, so 0.9 means 90 percent."
  }
}
