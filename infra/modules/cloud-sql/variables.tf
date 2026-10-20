variable "project_id" {
  description = "Project that owns the instance."
  type        = string
}

variable "region" {
  description = "Region for the instance. Co-locate with Cloud Run: cross-region database traffic costs latency and egress."
  type        = string
}

variable "instance_name" {
  description = "Instance name. Cannot be reused for up to a week after deletion, so avoid burning good names during experiments."
  type        = string
}

variable "database_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "POSTGRES_17"

  validation {
    condition     = contains(["POSTGRES_16", "POSTGRES_17"], var.database_version)
    error_message = "Use POSTGRES_16 or POSTGRES_17; older majors reach end of support sooner than this project will finish."
  }
}

variable "edition" {
  description = "ENTERPRISE or ENTERPRISE_PLUS. Shared-core tiers exist only on ENTERPRISE."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "tier" {
  description = "Machine type. db-f1-micro is the cheapest shared-core option, around 11 USD a month, and caps out near 25 connections — size the application pool against that."
  type        = string
  default     = "db-f1-micro"
}

variable "availability_type" {
  description = "ZONAL (single zone) or REGIONAL (synchronous standby, roughly double the cost)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.availability_type)
    error_message = "availability_type must be ZONAL or REGIONAL."
  }
}

variable "disk_size_gb" {
  description = "Initial SSD size in GB. Storage bills even while the instance is stopped."
  type        = number
  default     = 10

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 500
    error_message = "disk_size_gb must be between 10 (the minimum) and 500 (past which you should be reconsidering the design)."
  }
}

variable "disk_autoresize_limit" {
  description = "Ceiling for automatic growth, in GB. A runaway table cannot bankrupt you past this."
  type        = number
  default     = 50
}

variable "activation_policy" {
  description = "ALWAYS runs the instance; NEVER stops it, which stops compute billing but not storage."
  type        = string
  default     = "ALWAYS"

  validation {
    condition     = contains(["ALWAYS", "NEVER"], var.activation_policy)
    error_message = "activation_policy must be ALWAYS or NEVER."
  }
}

variable "network_self_link" {
  description = "Self link of the VPC the private IP is allocated in."
  type        = string
}

variable "psa_connection_id" {
  description = "Private Service Access connection id. Passed as a value so the dependency is part of the interface: the instance cannot be created before the peering exists."
  type        = string
}

variable "databases" {
  description = "Databases to create on the instance."
  type        = set(string)
  default     = []
}

variable "iam_users" {
  description = "IAM database users, keyed by a stable name. Exactly one should hold cloudsqlsuperuser so it can grant privileges to the others; IAM users receive none by default."
  type = map(object({
    email          = string
    type           = string
    database_roles = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for u in values(var.iam_users) : contains(["CLOUD_IAM_SERVICE_ACCOUNT", "CLOUD_IAM_USER", "CLOUD_IAM_GROUP"], u.type)
    ])
    error_message = "Each iam_users type must be CLOUD_IAM_SERVICE_ACCOUNT, CLOUD_IAM_USER or CLOUD_IAM_GROUP. A built-in user would need a password, which this module deliberately cannot create."
  }
}

variable "backup" {
  description = "Backup configuration. Daily backups are the cheapest insurance here; point-in-time recovery adds write-ahead log storage cost."
  type = object({
    enabled                = optional(bool, true)
    start_time             = optional(string, "08:00") # UTC, so early morning in us-east4
    retained_count         = optional(number, 7)
    point_in_time_recovery = optional(bool, false)
  })
  default = {}
}

variable "maintenance_window" {
  description = "When Google may restart the instance for updates. Pick a window you would rather lose than have chosen for you."
  type = object({
    day          = optional(number, 2) # Tuesday
    hour         = optional(number, 9) # UTC
    update_track = optional(string, "stable")
  })
  default = {}

  validation {
    condition     = var.maintenance_window.day >= 1 && var.maintenance_window.day <= 7
    error_message = "maintenance_window.day is 1 (Monday) through 7 (Sunday)."
  }

  validation {
    condition     = var.maintenance_window.hour >= 0 && var.maintenance_window.hour <= 23
    error_message = "maintenance_window.hour is 0 through 23, in UTC."
  }
}

variable "query_insights" {
  description = "Query Insights. Free at this scale and the difference between guessing at a slow query and seeing it."
  type        = bool
  default     = true
}

variable "extra_database_flags" {
  description = "Additional PostgreSQL flags. cloudsql.iam_authentication is always set by the module and does not belong here."
  type        = map(string)
  default     = {}

  validation {
    condition     = !contains(keys(var.extra_database_flags), "cloudsql.iam_authentication")
    error_message = "cloudsql.iam_authentication is managed by this module and is always on; remove it from extra_database_flags."
  }
}

variable "labels" {
  description = "Labels applied to the instance."
  type        = map(string)
  default     = {}
}

variable "enable_standard_log_flags" {
  description = "Connection, checkpoint, lock-wait and hostname logging. On by default; these make real operational problems visible and record no statement text."
  type        = bool
  default     = true
}
