# The budget lives in bootstrap, not in the observability module at M9 (deviation
# D5), because a runaway cost can happen on day one and because the budget is
# attached to the BILLING ACCOUNT, not to a project. Granting the CI identity
# billing-account permissions to manage it would be a much worse trade than
# applying it here, by hand, once.
#
# What this does NOT do: stop spending. It sends email. A hard stop needs a
# Pub/Sub budget notification driving a function that detaches billing, which is
# destructive and out of scope (§8.13). Know the difference.

resource "google_monitoring_notification_channel" "budget_email" {
  project      = google_project.seed.project_id
  display_name = "Fetcher owner"
  type         = "email"

  labels = {
    email_address = var.admin_email
  }

  depends_on = [module.seed_services]
}

resource "google_billing_budget" "fetcher" {
  provider = google.seed_quota

  billing_account = var.billing_account
  display_name    = "fetcher — all projects"

  budget_filter {
    # Budget filters take project NUMBERS, not ids.
    projects        = [for p in [google_project.seed, google_project.dev] : "projects/${p.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_threshold_percents

    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.budget_email.id]
    disable_default_iam_recipients   = false
  }
}
