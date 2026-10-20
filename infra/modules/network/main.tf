locals {
  psa_address = split("/", var.psa_cidr)[0]
  psa_prefix  = tonumber(split("/", var.psa_cidr)[1])
}

# Custom mode, not auto mode (§8.2).
#
# An auto-mode VPC creates a subnet in every region with ranges you did not
# choose, which is fine for a demo and a liability in anything real: you cannot
# plan addressing, you cannot peer cleanly, and you carry subnets in regions you
# will never use.
resource "google_compute_network" "this" {
  project                 = var.project_id
  name                    = var.network_name
  auto_create_subnetworks = false
  routing_mode            = var.routing_mode

  # Keep the default route to the internet. Cloud Run's Direct VPC egress sends
  # only private ranges here; public traffic leaves through Google's edge. Delete
  # this route and egress breaks in ways that are hard to trace.
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "this" {
  project       = var.project_id
  name          = "${var.network_name}-${var.region}"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.subnet_cidr

  # Lets instances and Direct VPC egress reach Google APIs over internal
  # addresses rather than hopping out to the internet and back.
  private_ip_google_access = true

  # Size note: Direct VPC egress consumes roughly two addresses per Cloud Run
  # instance, so the subnet must be large enough for max_instances plus headroom.
  # A /24 is 254 usable — ample for max_instances = 3, and cheap to have spare.

  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []

    content {
      aggregation_interval = "INTERVAL_10_MIN"
      flow_sampling        = var.flow_log_sampling
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Private Service Access: the reserved range Google's managed services (Cloud
# SQL here) allocate their private IPs from. This is what makes a database with
# no public IP possible at all (§8.3).
#
# The range must not overlap the subnet, and it is reserved in the VPC rather
# than assigned to anything you create.
resource "google_compute_global_address" "psa" {
  project       = var.project_id
  name          = "${var.network_name}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = local.psa_address
  prefix_length = local.psa_prefix
  network       = google_compute_network.this.id
}

# The peering itself. Without this, a private-IP Cloud SQL instance cannot be
# created, and the error does not say "you forgot Private Service Access" — it
# says something far less helpful. This is the single most common reason people
# give up and switch to a public IP with authorized networks, which is the wrong
# lesson to learn.
resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa.name]

  # Without this, removing the connection can strand the peering and leave the
  # range un-reusable.
  deletion_policy = "ABANDON"
}

# Cloud NAT is off by default and is the M4 exercise described in §8.2: turn it
# on, switch egress to ALL_TRAFFIC, and menu fetching leaves from one stable IP
# so the crawler can identify itself honestly. Note the cost before you do —
# a NAT gateway bills hourly whether or not anything uses it.
resource "google_compute_router" "nat" {
  count = var.enable_cloud_nat ? 1 : 0

  project = var.project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "nat" {
  count = var.enable_cloud_nat ? 1 : 0

  project                            = var.project_id
  name                               = "${var.network_name}-nat"
  region                             = var.region
  router                             = google_compute_router.nat[0].name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# count, not for_each, on those two: this is a true on/off toggle, which is the
# one case the brief allows it (§5).
