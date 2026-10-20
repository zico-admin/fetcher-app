variable "project_id" {
  description = "Dev workload project, created by infra/bootstrap."
  type        = string
}

variable "region" {
  description = "Region for regional resources. us-east4 keeps Cloud Run and Cloud SQL co-located (§4)."
  type        = string
  default     = "us-east4"
}

variable "environment" {
  description = "Environment name. Appears in default labels and in resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod; each lives in its own directory and its own project."
  }
}

variable "subnet_cidr" {
  description = "Primary range for the dev subnet. Direct VPC egress uses roughly two addresses per Cloud Run instance, so a /24 is ample for max_instances = 3."
  type        = string
  default     = "10.10.0.0/24"
}

variable "psa_cidr" {
  description = "Range reserved for Private Service Access, which Cloud SQL's private IP comes from. 10.20.0.0/16 is reserved for a future prod environment and must not be used here."
  type        = string
  default     = "10.10.16.0/20"
}

variable "sql_tier" {
  description = "Cloud SQL machine type. db-f1-micro is the cheapest shared-core option and the largest single line in the monthly bill."
  type        = string
  default     = "db-f1-micro"
}

variable "sql_disk_size_gb" {
  description = "Cloud SQL disk size in GB. Billed even while the instance is stopped."
  type        = number
  default     = 10
}

variable "sql_activation_policy" {
  description = "Set to NEVER to stop the instance between work sessions: compute stops billing, storage does not. Changing it here keeps the stopped state in config rather than as drift."
  type        = string
  default     = "ALWAYS"
}
