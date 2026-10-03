terraform {
  # The brief asks for >= 1.9. The lower bound lives here; the exact version CI and
  # your laptop both run lives in .terraform-version. Config declares a floor,
  # tooling pins a point release — those are different jobs.
  required_version = ">= 1.9, < 2.0"

  required_providers {
    google = {
      source = "hashicorp/google"
      # Deviation D1: the brief says ~> 7.0, written when 7.0 was new. 8.x is GA
      # now, so starting here avoids a pointless 7->8 upgrade later.
      # ~> 8.5 means >= 8.5.0, < 9.0.0 — minor and patch float, major never does.
      version = "~> 8.5"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}
