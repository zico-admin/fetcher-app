terraform {
  required_version = ">= 1.9, < 2.0"

  # Modules declare which providers they REQUIRE, never how those providers are
  # CONFIGURED. A provider block inside a module makes the module impossible to
  # reuse across projects, regions or credentials, and impossible to remove
  # cleanly later (§5).
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 8.0, < 9.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
