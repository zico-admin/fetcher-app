# Runbook — bootstrap (Milestone 0)

The one place in this repo where a human applies Terraform from a laptop, and the
one place that starts with local state. Everything after this is applied by CI.

Why it has to work this way: Terraform's state belongs in a GCS bucket, Terraform
creates the bucket, and the bucket does not exist yet. The same loop applies to
the CI identity — CI cannot create the credentials CI needs. So bootstrap runs
once, locally, and then moves its own state into the bucket it just made (§6).

---

## 1. Prerequisites

### Terraform 1.16.4

Your Homebrew Terraform is 1.5.7 — the last MPL-licensed release, which is where
`homebrew/core` stopped after the 2023 BUSL change. The brief needs ≥ 1.9.

```bash
brew uninstall terraform && brew install hashicorp/tap/terraform && terraform version
```

Expect `Terraform v1.16.4`. It must match `.terraform-version` and the `TF_VERSION`
in `.github/workflows/infra.yml`, or local and CI can disagree about a plan.

Optional, but they run in CI and finding out locally is faster:

```bash
brew install tflint checkov
```

### Google credentials

Bootstrap runs as you, `you@example.com`, which holds `roles/resourcemanager.projectCreator`
and `roles/billing.admin`.

```bash
gcloud auth application-default login
```

### A GitHub token

Fine-grained PAT on `zico-admin/fetcher-app`, with these repository permissions:

| Permission | Access | Needed for |
|---|---|---|
| Administration | Read and write | visibility, branch protection |
| Environments | Read and write | the `tf-apply` gate |
| Variables | Read and write | the four `GCP_*` Actions variables |
| Metadata | Read | implied by the others |

It is used by this apply only. It never reaches CI, and it is never written to
disk:

```bash
export TF_VAR_github_token="github_pat_..."
```

---

## 2. Configure

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars` is gitignored here (and only here — environment tfvars are
committed, because CI needs them and they hold nothing confidential).

---

## 3. Apply

```bash
terraform init

# Resolve providers for CI's platform as well as your Mac, so the committed lock
# file works in both places. Without this, CI fails on a missing hash for
# linux_amd64 — a genuinely confusing first error.
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64

terraform plan
```

Read the plan properly. It should create roughly: 1 folder, 2 projects, ~13
`google_project_service`, 2 `time_sleep`, 2 org policies, 1 bucket with 3 IAM
members, 1 WIF pool and provider, 2 service accounts with their bindings and
roles, 1 notification channel, 1 budget, 1 environment, 1 branch protection, 4
Actions variables — **and one import**, adopting the existing GitHub repository.

The import line is the thing to check first. It should read "will be imported",
never "will be created" — creating would mean Terraform does not believe your
repository exists.

```bash
terraform apply
```

### Errors you should expect, and what each means

| Error | Meaning | Fix |
|---|---|---|
| `Project ... already exists` on `google_project` | Project ids are globally unique and permanent, and a deleted project holds its id for 30 days | Change `seed_project_id` / `dev_project_id` in tfvars |
| `googleapi: Error 403 ... SERVICE_DISABLED` naming `orgpolicy` or `billingbudgets` | The quota project for that call does not have the API on. This is the `user_project_override` path in `providers.tf` | Confirm `seed_services` includes it and that `module.seed_services` finished first |
| `Error 403` creating something seconds after its API was enabled | Eventual consistency (§8.1) | The `time_sleep` in the module exists for this; if it still happens, raise `settle_duration` rather than rerunning |
| `Permission denied` on the billing account | Budget creation needs billing permissions this ADC session may lack | Confirm `gcloud billing accounts list` shows the account as OPEN |
| GitHub `422` on `required_approving_review_count` | GitHub rejected 0 approvals | See the comment in `github.tf` — the apply environment is the real gate |

---

## 4. Migrate state into the bucket

```bash
mv backend.tf.disabled backend.tf
terraform init -migrate-state      # answer yes when it offers to copy state
terraform plan                     # must report no changes
rm -f terraform.tfstate terraform.tfstate.backup
```

That last line matters. The files are gitignored, but a plaintext copy of state on
a laptop is still a copy of every secret in it.

---

## 5. Verify

```bash
# No service account keys anywhere. The output should be empty, or show only
# Google-managed keys — a USER_MANAGED key would mean the keyless premise is false.
for sa in tf-plan tf-apply; do
  gcloud iam service-accounts keys list \
    --iam-account="${sa}@ogbn-fetcher-seed.iam.gserviceaccount.com" \
    --managed-by=user --project=ogbn-fetcher-seed
done

# State bucket is locked down.
gcloud storage buckets describe gs://ogbn-fetcher-tfstate \
  --format="yaml(uniformBucketLevelAccess,versioning,publicAccessPrevention)"

# The WIF condition pins the numeric repository id, not a name.
gcloud iam workload-identity-pools providers describe github-oidc \
  --location=global --workload-identity-pool=fetcher-github \
  --project=ogbn-fetcher-seed --format="value(attributeCondition)"
```

---

## 6. Prove the loop

```bash
git switch -c m0-bootstrap
git add -A && git commit -m "M0: bootstrap, keyless CI, dev project services"
git push -u origin m0-bootstrap
```

Open a pull request. Expect the `plan` check to run, authenticate with no key, and
post the plan as a comment. Merge it, then approve the deployment on the `tf-apply`
environment and watch the apply run.

**Milestone 0 is done when that happens**: a GitHub Actions job authenticates to
GCP with no key and plans successfully.

---

## Rebuilding from nothing

Delete the projects, keep this directory, and run it again with new project ids.
That is the actual test of whether this is infrastructure as code. The only
inputs are `terraform.tfvars` and a GitHub token.
