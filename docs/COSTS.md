# Running cost

Estimates for one dev environment at low traffic. The budget is $50/month with
alerts at 50, 90 and 100 percent — which **emails you and does not stop
spending** (§8.13).

## After Milestone 1

| Item | Monthly | Note |
|---|---|---|
| Cloud SQL `db-f1-micro`, 10 GB SSD | ~$13 | The largest fixed line, and the only real cost at M1 |
| VPC, subnet, Private Service Access | $0 | Peering itself is free |
| VPC flow logs | <$1 | 50% sampling; raise sampling only while debugging |
| Artifact Registry | <$1 | Cleanup policies keep it from creeping |
| GCS menu snapshots | <$1 | 90-day lifecycle |
| Secret Manager | <$1 | Two secrets, few accesses |
| Cloud Logging / Monitoring | ~$0 | Within free tier |
| **M1 total** | **~$15** | |

Not yet created: Cloud Run (M2, $0–3 scaling to zero), Pub/Sub and BigQuery (M9,
effectively free at this volume), Vertex AI inference (M4, $5–20 front-loaded
during ingestion). Twilio is billed separately, roughly $1 plus per-message.

## The lever that matters

Cloud SQL compute is most of the bill and you are not using it between work
sessions:

```hcl
# infra/envs/dev/terraform.tfvars
sql_activation_policy = "NEVER"
```

Apply that and compute billing stops; storage keeps billing and the data
survives. Set it back to `ALWAYS` when you next work on it.

Do this through Terraform rather than `gcloud sql instances patch`. The gcloud
route works and then the next apply quietly starts the instance again, because
config still says `ALWAYS` — you would be paying for an instance you believed
was stopped.

## What actually causes a surprise bill

Not the steady state. The things that have turned a $30 month into a $600 one
for people learning on their own account:

- a job that retries forever against a failing dependency
- `min_instances` left above zero after an experiment
- a Vertex AI batch re-run over the full venue set because of a prompt change
- flow log sampling raised to 1.0 and left there

The budget alert catches all of these late, by email, after the money is spent.
Reading the alert the day it arrives is the actual control.

## Verify rather than trust this file

```bash
gcloud billing accounts list
```

Then open the billing console's cost table and group by service. These numbers
are order-of-magnitude; the pricing calculator and your actual bill are the
authority.
