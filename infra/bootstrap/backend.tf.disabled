# Bootstrap's own state, after the chicken-and-egg is resolved.
#
# Sequence (see docs/runbooks/bootstrap.md):
#   1. terraform apply with NO backend block — state is local, the bucket does not
#      exist yet.
#   2. The apply creates the bucket.
#   3. Rename this file to backend.tf.
#   4. terraform init -migrate-state — Terraform copies local state into the bucket
#      it just created and asks you to confirm.
#   5. Delete the local terraform.tfstate* files. They are gitignored, but a
#      plaintext copy of state on a laptop is still a copy of your secrets.
#
# It ships as .disabled rather than commented out so that step 3 is a rename and
# cannot be half-done.

terraform {
  backend "gcs" {
    bucket = "ogbn-fetcher-tfstate"
    prefix = "bootstrap"
  }
}
