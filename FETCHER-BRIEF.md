Fetcher — Build Brief (Phase 2, GCP + Terraform)
How to use this: save as FETCHER-BRIEF.md in an empty repo, open Claude Code there, paste the prompt in the box below.
What changed from v1: the application spec is unchanged in substance. Everything about how it runs has been rewritten. Nothing is click-deployed — every Google Cloud resource is created by Terraform, reviewed in a pull request, and applied by CI with no service-account keys anywhere. The infrastructure is now the first thing built, not the last, because it's the part you're here to learn.

The prompt to paste
Read FETCHER-BRIEF.md in full before doing anything else.

It specifies Fetcher, a Phase 2 validation build running on Google Cloud, with
all infrastructure managed by Terraform.

Two things about how I want to work on this, because they change what "good"
means here:

I am building this to get materially better at Terraform and GCP. Do not
optimize for getting me to a working app fastest. When a decision has a
teaching-rich correct answer and a quick hack, take the correct answer and tell
me why in a comment. When I ask for something that would be bad practice, push
back before doing it. I would rather hit a real error and understand it than
have you route around it silently.

And: no resource may be created by console click or gcloud command. If it isn't
in Terraform, it doesn't exist. The one exception is §6 bootstrap, which is
explicitly a chicken-and-egg problem and is handled there.

Do this in order:

1. Read the brief. Then ask me every question you need answered before writing
   code you'd be confident in — infrastructure questions first. Ask them all at
   once. Do not start coding.
2. Write a plan: milestones, the full repo tree, the Terraform module interfaces
   (inputs and outputs for each), and every decision the brief left open. Wait
   for my sign-off.
3. Then build Milestone 0 only, and stop.

The application non-goals in §3 and the confidence-tier rules in §10 are binding.
If anything in the brief is internally inconsistent, or you think a requirement
is wrong, say so before building rather than quietly working around it.

Brief
1. What Fetcher is
Fetcher tells you where to eat and what to order in a city you don't know, based on a health goal you set.
The user is a traveler trying to eat a particular way — managing weight, watching blood sugar — who loses the thread the moment they leave their routine. Every existing app assumes you're home, shopping a familiar store, cooking. Fetcher assumes you're on a street in an unfamiliar city with ninety seconds of patience, and answers the only question that matters: where do I go, and what do I order when I get there.
The output is a specific dish at a specific place plus the modification to ask for — "get the bowl, sub brown rice, dressing on the side, skip the chips." That's what a knowledgeable friend gives you and what no app does.
This phase answers one question: do people use it on a second trip? Every decision should trace back to measuring that.

2. The two goals of this build
Be explicit that this repo serves two purposes, because they occasionally conflict and you need a tiebreaker.
Product goal. Reach 100 users in one city and find out whether 30% come back for a second trip.
Craft goal. Build fluency in Terraform and Google Cloud sufficient to hold a Senior DevOps conversation: module design, remote state, keyless CI/CD, private networking, least-privilege IAM, and observability you configured rather than inherited.
Tiebreaker: when the two conflict, the craft goal wins on infrastructure decisions and the product goal wins on feature decisions. Take the private-IP database even though public IP would ship faster. Do not add a feature because it would be interesting to instrument.

3. Application scope — and the non-goals
Seed city: Washington, DC. Pick one city, not a region, and make city a first-class entity so the second is cheap.
Seed persona: adults managing weight or blood sugar who travel. One persona. Not two.
Build
#
Feature
Why it's in
1
Phone-number onboarding, goal intake with visible pace translation (§9)
The goal is the input to everything
2
Menu ingestion for ~300 DC venues (§10)
The actual hard part, and the only possible moat
3
Deterministic recommendation engine (§11)
The product
4
"Going out tonight" event mode (§12)
Most shareable feature, cheap to build
5
SMS interface via Twilio (§13)
The in-the-moment ask happens on a phone
6
Event instrumentation into BigQuery (§14)
Without it the phase answers nothing

Do not build — binding
No health-record integration. No Apple Health, no HealthKit, no FHIR, no lab values. If a user types a lab number into free text, do not parse or store it as structured health data.
No native apps. Mobile web only.
No body measurements, avatars, or 3D anything.
No pregnancy, allergy, or medical-condition modes. Different clinical failure cost. One persona.
No accounts, passwords, OAuth, or email. Phone number and an SMS code.
No calorie logging, food diary, streaks, or photo recognition. Fetcher is forward-looking. It never asks what you ate.
No payments, restaurant partnerships, or booking.
No Kubernetes. GKE would teach you things, but it costs an order of magnitude more to run and it is the wrong tool for this workload. Cloud Run is the right answer and knowing why is worth more than the GKE experience. If you want Kubernetes, learn it on a cluster you tear down nightly, not on this.
If a feature seems obviously useful and isn't listed, it is deliberately excluded. Raise it, don't add it.

4. Target architecture
                       GitHub  ──(OIDC, no keys)──►  Workload Identity Federation
                          │                                     │
                    Actions CI                            deployer SA
                          │                                     │
              ┌───────────┴───────────┐                         ▼
              ▼                       ▼                 Artifact Registry
      terraform plan/apply      docker build/push               │
                                                                ▼
   ┌────────────────────────────────────────────────────────────────────────┐
   │  VPC (custom mode)                                                      │
   │                                                                         │
   │   Cloud Run service  ──Direct VPC egress──►  Cloud SQL Postgres         │
   │   (web + SMS webhook)                        (private IP, no public)    │
   │          │                                                              │
   │   Cloud Run job  ─────────────────────────►  (menu ingestion)           │
   └──────────┼──────────────────────────────────────────────────────────────┘
              │
   Cloud Scheduler ──OIDC──► job          Cloud Tasks ──► delayed follow-up SMS
              │
   Pub/Sub ──BigQuery subscription──► BigQuery (instrumentation, cohort analysis)
              │
   GCS (raw menu snapshots)   Secret Manager (Twilio)   Vertex AI (Claude, via IAM)
              │
   Cloud Logging / Monitoring / uptime checks / alert policies / budget alert
One GCP project, one region (us-east4 — closest to you in Arlington, and it keeps Cloud SQL and Cloud Run co-located, which matters for latency and egress cost).

5. Terraform standards
These are the habits that separate someone who has used Terraform from someone who can own it.
Versions. Terraform >= 1.9. Google provider pinned ~> 7.0 (7.0 went GA in late 2025 — read the upgrade guide, it has real breaking changes). Commit .terraform.lock.hcl. Use google-beta only where a resource genuinely requires it, aliased, never as the default provider.
Layout.
infra/
├── bootstrap/                 # local state, applied once, then migrated
├── modules/
│   ├── project-services/
│   ├── network/
│   ├── cloud-sql/
│   ├── artifact-registry/
│   ├── cloud-run-service/
│   ├── cloud-run-job/
│   ├── scheduling/            # Scheduler + Tasks
│   ├── analytics/             # Pub/Sub + BigQuery
│   ├── secrets/
│   └── observability/
└── envs/
    └── dev/                   # backend.tf, main.tf, terraform.tfvars
Why directory-per-environment, not workspaces. Workspaces share one configuration and one backend, so terraform workspace select prod is a single typo away from applying dev's plan to prod, and environments can never diverge in structure. Directory-per-env costs a little duplication in envs/*/main.tf and buys you a separate state file, separate backend config, separate CI job, and a diff you can actually read. Nearly every team that starts with workspaces migrates away.
The mistake people make. Building envs/dev only and assuming prod is a copy. Write the modules so nothing is hardcoded — no project ID, no region, no instance size — from the first module. You are only building dev in this phase, but if a module has us-east4 baked into it, you've learned the wrong lesson.
Go read. HashiCorp's module composition guide, and the terraform-google-modules org on GitHub for interface design worth imitating.
Module interface rules. Every module: typed variable blocks with description and, where a value has a valid range, a validation block. Explicit outputs for anything another module consumes. No provider blocks inside modules. No data source that reaches outside the module's concern.
for_each, not count. count addresses resources by index, so removing the second of five items destroys and recreates three. for_each addresses by key. Use count only for a true on/off toggle.
Refactoring without destruction. When you move or rename a resource, add a moved block rather than letting Terraform destroy and recreate. When you need to adopt something that already exists, use an import block, not terraform import at the CLI — the block is reviewable in a PR.
Guard the irreplaceable. lifecycle { prevent_destroy = true } on the Cloud SQL instance and the state bucket, plus deletion_protection = true on the instance. You will at some point run a plan that wants to destroy the database. This is what stops it.
State is a secret. Terraform state stores generated passwords and secret values in plaintext. The state bucket gets uniform bucket-level access, versioning on, public access prevention enforced, and IAM limited to you and the deployer SA. Never commit a .tfstate. Never terraform apply -auto-approve outside CI.
Quality gates, all in CI (§7). terraform fmt -check -recursive, terraform validate, tflint, and a security scanner (checkov or trivy config). Fail the build on findings; add inline suppressions with a written reason when you disagree.
Worth knowing. Terraform moved to the BUSL licence in 2023; OpenTofu is the MIT-licensed fork and is close to a drop-in replacement. Everything in this brief works with either. Being able to explain the split is a reasonable interview question.

6. Bootstrap — the chicken-and-egg
Terraform's state should live in a GCS bucket. Terraform creates the bucket. The bucket doesn't exist yet.
infra/bootstrap/ resolves this and is the one place where you apply with local state:
Enable the handful of APIs needed to do anything at all.
Create the state bucket: versioning on, uniform bucket-level access, public access prevention, lifecycle rule keeping ~30 noncurrent versions.
Create the Workload Identity Pool and its GitHub OIDC provider.
Create the terraform-deployer service account and bind the GitHub repo to it.
Then add a backend "gcs" block to bootstrap itself and run terraform init -migrate-state to move its own state into the bucket it just made.
Commit the resulting terraform.tfstate never. Add it to .gitignore before the first apply, not after.
Why this matters beyond this repo. Every real GCP estate has a bootstrap or "seed" project handled exactly this way. Being able to explain it is a strong signal in an interview.
The mistake people make. Creating the bucket by hand with gsutil and calling it done. You then have an unmanaged resource that nobody can reason about, and no artifact showing how it was configured.
Workload Identity Federation — get the condition right
This is the highest-stakes twenty lines in the repo.
attribute_condition = "assertion.repository == 'YOUR_GH_USER/fetcher' && assertion.ref == 'refs/heads/main'"
Why. WIF lets GitHub Actions authenticate to GCP by exchanging a short-lived OIDC token — no service account JSON key to leak, rotate, or accidentally commit. Long-lived SA keys are the single most common cause of real GCP compromise.
The mistake people make — and it is a live vulnerability, not a style note. Binding the pool to principalSet://.../attribute.repository/*, or omitting attribute_condition entirely. Either means any GitHub repository in the world can mint a token for your service account. Scope to your exact repo, and scope the apply path to main.
Go read. Google's "Configure Workload Identity Federation with deployment pipelines," and the google-github-actions/auth README.
Grant the deployer SA the narrowest roles that let it manage what it manages. roles/owner is not an answer. Expect to iterate here — start narrow, read the permission denials, add specifically. That loop is the IAM lesson.

7. CI/CD — GitHub Actions, keyless
Two workflows, deliberately separate.
.github/workflows/infra.yml — on pull requests touching infra/**:
fmt -check → init → validate → tflint → checkov → plan → post plan to PR
On merge to main: apply, gated behind a GitHub Environment with a required reviewer (yourself — it still forces you to read the plan).
.github/workflows/app.yml — on pull requests touching app/**: lint, typecheck, vitest. On merge: build the container, push to Artifact Registry tagged with the commit SHA, deploy a new Cloud Run revision.
Why split them. Infrastructure changes and application changes have different blast radii, different reviewers, and different rollback stories. A bad app deploy is one revision rollback. A bad terraform apply can delete a database.
The mistake people make. Tagging images :latest. Then you cannot say which commit is in production, and a rollback is guesswork. Tag with the commit SHA and let Cloud Run's revision history be your rollback mechanism.
Details worth getting right. permissions: id-token: write is required for OIDC and is easy to forget. Concurrency groups so two applies can't race. Never echo a secret. Post the plan as a PR comment so review is real review.

8. The infrastructure, service by service
Each block: what to build, why that way, and the failure mode.
8.1 Project services
google_project_service for every API, disable_on_destroy = false.
Why. API enablement is itself infrastructure. Enabling by console click means a fresh project can't be rebuilt from the repo.
The mistake. API enablement is eventually consistent — resources created immediately after enabling can fail with a confusing permission error. Use explicit depends_on, or a short time_sleep. When you hit this, you'll have learned something that costs most people an afternoon.
8.2 Network
Custom-mode VPC. One subnet in us-east4 with a deliberately chosen CIDR. Private Service Access range (google_compute_global_address with purpose = "VPC_PEERING") plus google_service_networking_connection — this is what lets Cloud SQL have a private IP.
No Cloud NAT initially. Cloud Run uses Direct VPC egress with PRIVATE_RANGES_ONLY, so private traffic goes to the VPC and public traffic exits normally.
Why custom mode. Auto-mode VPC creates a subnet in every region with fixed ranges you didn't choose. It's fine for a demo and a liability in anything real.
Why Direct VPC egress over a Serverless VPC Access connector. Direct VPC egress is GA and is Google's recommended option: it scales to zero with the service and costs only network egress, where a connector runs VMs you pay for whether or not anything is using them (~$8+/month idle). It does consume more IPs, so size the subnet accordingly.
When you'd add Cloud NAT. If you want menu fetching to come from one stable IP — so you can identify your crawler honestly and be blocked or allowed deliberately — switch egress to ALL_TRAFFIC and add Cloud Router + Cloud NAT. That's a good Milestone 4 exercise. Note the cost before you do it.
The mistake. Forgetting that with ALL_TRAFFIC and no NAT, your service silently loses all internet access. This produces a genuinely baffling debugging session.
8.3 Cloud SQL for PostgreSQL
PostgreSQL 16 or 17, Enterprise edition, db-f1-micro (~$11/month, the cheapest shared-core tier), private IP only — ipv4_enabled = false. Automated daily backups on. Point-in-time recovery off for now (it costs, and the data is reconstructible). Defined maintenance window. deletion_protection and prevent_destroy both on.
Use Cloud SQL IAM database authentication (cloudsql.iam_authentication flag) so the Cloud Run service authenticates as its own service account rather than with a password.
Why IAM auth. It removes the password from the system entirely: nothing in Secret Manager, nothing in state, nothing to rotate, and database access revocation becomes an IAM change. If you generate a random_password, it lands in Terraform state in plaintext forever — which is survivable with a locked-down bucket, but avoiding it is better.
The mistake. Public IP with authorized networks, because private IP "wasn't working." It wasn't working because Private Service Access wasn't configured. Fix that instead — private networking is most of what the networking half of a DevOps role actually is.
Cost note. This is your largest fixed line item. You can stop the instance between work sessions; storage still bills, compute doesn't.
8.4 Artifact Registry
One Docker repository, with a cleanup policy retaining the most recent ~20 untagged images.
Why. Container images accumulate silently. A cleanup policy is three lines of Terraform and saves a slow leak. Cost hygiene as code is a habit worth forming early.
8.5 Cloud Run — service
The Next.js app and the Twilio webhook. min_instances = 0, max_instances = 3, concurrency 80, CPU throttled outside requests, its own service account, Direct VPC egress.
Why scale to zero. You have no users yet. Idle cost should be zero. Accept cold starts; note what they cost you and what min_instances = 1 would cost per month, so you can reason about the tradeoff rather than guess.
Why concurrency 80. Cloud Run bills per instance-time, not per request. An instance handling 80 concurrent requests costs the same as one handling 1. This single setting is often the difference between a $5 bill and a $500 bill, and most people never touch it.
The mistake. Deploying the image from the CI job and declaring the Cloud Run service in Terraform, so each fights the other's revision. Resolve it deliberately: have Terraform own the service's shape and lifecycle { ignore_changes = [template[0].containers[0].image] } so CD owns the image tag. Write down the decision in a comment.
8.6 Cloud Run — job
Menu ingestion. Long-running, batch, no HTTP surface. Generous task timeout, retries configured, its own service account.
Why a job, not a service. Jobs are for run-to-completion work. A scrape that takes eleven minutes doesn't belong behind a request timeout.
8.7 Scheduling and async
Cloud Scheduler triggers the ingestion job nightly, authenticating with an OIDC token against the job's invoker endpoint.
Cloud Tasks handles the delayed "did you go?" follow-up — enqueue a task with a scheduled time a few hours out, targeting an authenticated endpoint on the Cloud Run service.
Why Tasks and not a cron that polls the database. Per-item delayed execution with built-in retry and backoff is exactly the problem Cloud Tasks solves. A polling cron is the thing you'd build if you didn't know Tasks existed.
Tasks vs Pub/Sub — know the difference cold. Tasks: one named consumer, per-item scheduling and rate control, you control the delivery target. Pub/Sub: fan-out to many subscribers, no per-message scheduling. Using the wrong one is a common design-review flag.
The mistake. Leaving the Cloud Run endpoint that Tasks calls unauthenticated. Require an OIDC token and verify it.
8.8 Analytics pipeline
The app publishes instrumentation events to a Pub/Sub topic. A BigQuery subscription writes them straight into a table — no consumer code at all.
Why. It's the cleanest managed pipeline GCP offers, it costs effectively nothing at this volume, and cohort retention analysis is a SQL problem, not an application problem. Keeping analytics events out of Postgres also keeps your operational database small.
The mistake. Not defining a schema, landing everything as a JSON blob, and discovering in month three that half your events have a differently-spelled field. Define the schema in Terraform. Partition the table by date.
8.9 Storage
GCS bucket for raw menu HTML and PDF snapshots. Uniform bucket-level access. Lifecycle rule deleting objects after 90 days.
Why keep raw snapshots at all. When an inference looks wrong, you need the input that produced it. This is the difference between debugging and guessing.
8.10 Secrets
Secret Manager for the Twilio account SID and auth token. Granted to the runtime service account only, per-secret, never project-wide.
Note. With Vertex AI (§8.11) and Cloud SQL IAM auth (§8.3) there is no LLM API key and no database password. Twilio may be your only real secret — which is itself the lesson: the best secret management is having fewer secrets.
8.11 Vertex AI for inference
Run ingredient inference against Claude on Vertex AI rather than a direct API. Authenticate with the job's service account via Application Default Credentials and roles/aiplatform.user.
Why. No API key to store, rotate, or leak. Billing consolidates into GCP. Traffic stays inside Google's network. And it teaches the pattern that matters: workload identity instead of shared credentials, which is the same idea as WIF in §6 applied inside the cloud.
Also consider. Document AI's OCR processor for PDF menus, which are common and awful. Price it per page before you wire it in.
8.12 IAM
One dedicated service account per workload: run-web, run-job, scheduler-invoker, terraform-deployer. Least privilege on each. roles/editor appears nowhere.
The single most important GCP security fact. The default compute service account is granted roles/editor on the project automatically, and anything running as it can do almost anything. Disable that with the constraints/iam.automaticIamGrantsForDefaultServiceAccounts org policy, and never run a workload as a default SA.
How to get least privilege right without guessing. Start with nothing, deploy, read the denial, grant exactly that permission, repeat. Tedious the first time and then permanent knowledge. Use IAM Recommender afterwards to catch what you over-granted.
8.13 Observability and cost control
Uptime check on the web app. Log-based metric for recommendation-serving errors. Alert policies on Cloud Run 5xx rate, Cloud SQL disk utilization, and job failure. Email notification channel. All in Terraform.
A google_billing_budget at $50/month with alerts at 50%, 90% and 100%.
Why the budget matters more than it sounds. A misconfigured job that retries forever, or a min_instances you forgot to set back to zero, can turn a $30 month into a $600 month. This has happened to almost everyone who learns on their own account.
What a budget alert does not do. It does not stop spending — it emails you. A hard stop requires a Pub/Sub budget notification triggering a function that disables billing, which is destructive and worth knowing about but not worth building here. Know the distinction; it's a good interview answer.

9. Goal intake and the pace guardrail
The user states a goal in their own words — "lose 15 pounds in one month." Accept it, then translate it visibly.
Compute the implied rate.
Cap the coached rate at the lesser of 2 lb/week or 1% of body weight per week.
If the stated rate exceeds the cap, show the translation before proceeding:
You asked for 15 lb in 4 weeks — about 3.8 lb a week. Fetcher plans at up to 2 lb a week, so it's aiming you at 15 lb by [date]. Faster than that mostly costs you muscle and tends not to stick.
The user keeps their original target as an aspiration; the engine plans to the coached rate. Store both.
Never produce a plan whose implied daily intake falls below 1,500 kcal/day (male) or 1,200 kcal/day (female). Cap and say so.
The guardrail is a visible feature with real copy, not a hidden clamp.
Copy rules, enforced in review: no remaining-allowance framing, no streaks or badges on restriction, no moral vocabulary for food ("clean", "cheat", "guilt-free"), and a short standing line: Fetcher isn't medical advice.
Store stated_target, stated_deadline, coached_rate_lb_per_week, coached_deadline, guardrail_applied.

10. The menu pipeline
Nutrition data for chains is purchasable. Nutrition data for the independent restaurants actually worth eating at does not exist anywhere. Building it is most of this phase's work.
Sourcing, in priority order: the venue's own published nutrition; the venue's own website or PDF menu; Google Places for hours, location, price level, cuisine; manual entry through a small admin form for the top 50.
Do not scrape delivery aggregators (DoorDash, Uber Eats, Grubhub, Yelp menus). Their terms prohibit it. Respect robots.txt, identify the crawler honestly, rate-limit, cache in GCS.
Inference. Derive nutrition estimates and qualitative flags from item name, description, section, and venue cuisine. Store the evidence, prompt version, and model version on every row so a bad batch can be found and re-run.
Flags: high_protein, high_fiber, refined_carb_base, fried, cream_or_butter_sauce, sugar_sweetened, large_format, vegetable_forward, raw_or_undercooked.
Confidence tiers — hard rules
Tier
Means
May be shown as
May satisfy a hard constraint
verified
Human-checked, or venue-published
Exact figures
Yes
menu_stated
Menu names ingredients and preparation
Exact figures, sourced
Yes
inferred
Model estimate from name and cuisine norms
Range only, labelled an estimate
No
unknown
Not enough to go on
No numbers; qualitative only
No

These are not display preferences. An inferred row must be structurally incapable of rendering as a precise number or clearing a hard filter — enforce it in the type system or query layer, not a template, with tests that fail if it leaks.

11. The recommendation engine
Input: profile (coached goal, restrictions, dislikes), lat/lng, timestamp, meal context, optional event context, radius, price ceiling.
Output: 3–5 venues, each with distance, price level, open-now status, 1–2 specific dishes, a one-line why this, the modification line, and a confidence badge per dish.
Architecture requirement. Ranking is a deterministic, pure, unit-tested function — not an LLM call.
candidates
  → hard filters   (open now, radius, price, dislikes, restriction-safe
                    using only verified/menu_stated rows)
  → score          (goal fit, protein & fibre density, refined-carb and fried
                    penalties, portion risk, distance decay, rating,
                    confidence bonus)
  → diversify      (one venue per cuisine; at most one chain)
  → top N
The LLM writes the why this and modification lines from the ranked row. It never reorders. Keep scoring weights in one named, commented config object. Store the full scoring breakdown for every recommendation served — when one is bad you need to know whether the data, the weights, or the copy failed.

12. Event mode — "going out tonight"
The user declares what's coming: "drinking tonight, around 8." Three moments — a dinner recommendation weighted to protein and fat plus a water plan; optionally one message during; and a morning-after breakfast recommendation near them, weighted to eggs, salt, potassium and fluids.
Language constraints. Fetcher does not cure, prevent, treat, flush or detoxify anything. Build a lint check that fails on "cure", "detox", "flush", and "prevents a hangover". It's three lines and it will save you.

13. SMS interface
Onboarding and detail views on the web; the in-the-moment ask over SMS, because that's where someone on a sidewalk is.
Signature-verified Twilio webhook on Cloud Run. Understands a bare city name, "hungry", "dinner", "going out tonight", "where now", "STOP". Replies are two or three options plus a link. Honor STOP/HELP properly and log consent with a timestamp. Mind the segment limit.

14. Instrumentation — built in Milestone 8, designed from Milestone 3
The gate is 100 users, ≥30% using Fetcher on a second trip. If these events aren't recorded, the phase produces no answer.
Publish to Pub/Sub, land in BigQuery: trip_started, rec_served (with scoring breakdown), rec_opened, rec_outcome (went / didn't / no answer, from one follow-up SMS), second_trip, event_declared, morning_after_served.
Build /admin/metrics querying BigQuery: signups, activation, recs per user, follow-through rate, and the second-trip cohort curve. Ugly is fine. Missing is not.

15. Privacy, legal, and data posture
Self-reported weight and goals are health-adjacent. Never send them, or any derived signal, to an analytics or advertising SDK. Keep third-party JS off pages touching goal data.
No health-record ingestion (§3), which keeps the compliance surface small. Don't quietly widen it.
Phone number is the only identifier. No name, email, or address.
One-tap delete that actually deletes, including BigQuery rows and GCS objects.
Footer and first SMS: Fetcher gives food suggestions, not medical advice.
Nothing sensitive in Terraform variables that get logged. Mark sensitive outputs sensitive = true.

16. Milestones
Stop after each. Infrastructure comes first — that ordering is the point.
#
Milestone
Done when
0
Bootstrap: state bucket, WIF, deployer SA, project services; state migrated to GCS
A GitHub Actions job authenticates to GCP with no key and runs terraform plan successfully
1
Network, Cloud SQL (private IP, IAM auth), Artifact Registry, Secret Manager
terraform apply from CI creates everything; you can reach the DB only from inside the VPC
2
Cloud Run service with a hello-world container, full CI/CD both workflows
A merge to main deploys a new revision automatically, tagged with the commit SHA
3
App schema, migrations, scoring function with tests — no UI
pnpm test passes; you can rank a hand-seeded venue set from a script
4
Menu pipeline as a Cloud Run job: GCS snapshots, Vertex AI inference, tiering, admin verify form
50 DC venues ingested; you can verify one in under 60 seconds
5
Web onboarding, goal intake, pace guardrail, recommendation card
You can sign up and get a real recommendation on your phone
6
SMS loop including the Cloud Tasks follow-up
You can text "dinner" from a DC street and get something worth acting on
7
Event mode, all three moments
Morning-after flow fires correctly and passes the copy lint
8
Pub/Sub → BigQuery, observability, alert policies, budget alert, scale to 300 venues
The second-trip cohort curve renders from real data


17. Running cost estimate
Order-of-magnitude, single dev environment, low traffic. Verify against the pricing calculator before you rely on it.
Item
Monthly
Cloud SQL db-f1-micro + 10 GB SSD
~$13
Cloud Run service + job (scale to zero)
$0–3
Artifact Registry
<$1
GCS (menu snapshots)
<$1
Secret Manager
<$1
Cloud Scheduler / Tasks / Pub/Sub
~$0 (free tiers)
BigQuery
~$0 (free tier)
Cloud Logging / Monitoring
~$0 (free tier)
Vertex AI inference
$5–20, front-loaded during ingestion
GCP total
~$20–40
Twilio (separate)
~$1 + per-message

Stopping the Cloud SQL instance between sessions cuts the largest line. Set the budget alert in Milestone 1, not Milestone 8.

18. What you should be able to do afterwards
Use this as a self-check, and as the basis for how you'd describe the project.
Terraform: design a module with a clean interface; explain directory-per-env vs workspaces and defend the choice; use for_each, moved, and import blocks correctly; explain why state is sensitive and how you protected it; run plan in CI and gate apply; read a plan diff and spot a destroy before it happens.
GCP: build a custom VPC with Private Service Access and explain what breaks without it; choose Direct VPC egress over a connector and say why; write least-privilege IAM from denials rather than from roles/editor; explain the default compute SA problem; pick between Cloud Tasks and Pub/Sub on the merits; configure alert policies and a budget rather than inheriting them.
DevOps generally: keyless CI/CD with OIDC and why SA keys are a liability; immutable image tags and revision-based rollback; the difference between a budget alert and a spend control; how to make an on-call-able system out of a side project.
Aligned certifications, if you want an external checkpoint: HashiCorp Terraform Associate covers most of §5–§7; Google Professional Cloud DevOps Engineer covers most of §8. Neither is necessary. Both are easier after building this than before.

19. Ask me these before you start
Answer for yourself first, then ask what you still need. At minimum expect questions about:
GCP project: existing or new, and the billing account and org policy situation
whether the GitHub repo is public or private, and its exact owner/name for the WIF condition
the region choice, and whether us-east4 is right for you
domain name — custom domain on Cloud Run, or the default run.app URL for now
CIDR planning for the VPC subnet and the Private Service Access range
whether to use Cloud SQL IAM auth from the start or begin with a password and migrate (my preference: IAM from the start)
which venue set seeds the 300, and the ranking criteria for choosing them
how a trip is detected versus declared
how much of goal intake lives in SMS versus the web
what happens when a city has no good match in radius — the empty state matters more than it sounds

