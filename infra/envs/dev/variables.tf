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

variable "quota_project_id" {
  description = "Seed project that API calls are billed to. CI identities hold serviceusage.services.use on it (bootstrap)."
  type        = string
  default     = "ogbn-fetcher-seed"
}
