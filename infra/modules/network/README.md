# network

Custom-mode VPC, one regional subnet, and the Private Service Access range that
makes a private-IP Cloud SQL instance possible.

## The part that matters

`google_compute_global_address` with `purpose = "VPC_PEERING"` reserves a range,
and `google_service_networking_connection` peers it to Google's service
producer network. Without both, a Cloud SQL instance with `ipv4_enabled = false`
cannot be created — and the error does not mention Private Service Access.

That is the moment people give up and switch to a public IP with authorized
networks (§8.3). Private networking is most of what the networking half of a
DevOps role actually is, so fix the peering rather than the symptom.

The module makes the dependency explicit: pass `psa_connection_id` into the
`cloud-sql` module, where a `precondition` references it. A precondition's
references are real dependencies, so the instance is ordered after the peering.

## Addressing

| Range | Purpose |
|---|---|
| `subnet_cidr` | The subnet. Direct VPC egress uses ~2 addresses per Cloud Run instance, so size for `max_instances` plus headroom |
| `psa_cidr` | Reserved for managed services. `/20` or larger; must not overlap the subnet |

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | `string` | — | Project owning the VPC |
| `network_name` | `string` | — | VPC name |
| `region` | `string` | — | Subnet region |
| `subnet_cidr` | `string` | — | Subnet primary range |
| `psa_cidr` | `string` | — | Private Service Access range |
| `routing_mode` | `string` | `REGIONAL` | `REGIONAL` or `GLOBAL` |
| `enable_flow_logs` | `bool` | `true` | Flow logs on the subnet |
| `flow_log_sampling` | `number` | `0.5` | Sampling fraction |
| `enable_cloud_nat` | `bool` | `false` | Cloud Router + NAT |

## Outputs

`network_id`, `network_name`, `network_self_link`, `subnet_id`, `subnet_name`,
`subnet_cidr`, `psa_range_name`, `psa_connection_id`.

## Notes

- `enable_cloud_nat` uses `count`, the one case the brief allows it: a true
  on/off toggle. It is the M4 exercise — switch egress to `ALL_TRAFFIC` so menu
  fetching leaves from one stable IP. A NAT gateway bills hourly regardless of
  traffic.
- The default internet route is kept. With `ALL_TRAFFIC` egress and no NAT, a
  service silently loses all internet access, which is a baffling debugging
  session (§8.2).
