# FACODI deployment operations

This runbook describes the first Google Cloud deployment for `marcelo-m7/facodi-deploy`. Defaults are project `marcelo-497411` and region `europe-southwest1`.

## 1. Administrator prerequisite

The first bootstrap must be executed by a Google Cloud identity that can create Workload Identity Federation resources, service accounts, enable APIs and modify project IAM. Terraform cannot bypass Google Cloud IAM. If the current operator lacks those permissions, a project administrator/Owner must grant them first.

No service-account JSON key is required or supported by this repository.

## 2. Bootstrap Terraform state and GitHub federation

Authenticate locally with an administrative identity, then initialize the bootstrap without its remote backend and apply it:

```bash
gcloud auth application-default login
gcloud config set project marcelo-497411

terraform -chdir=infrastructure/terraform/bootstrap init -backend=false
terraform -chdir=infrastructure/terraform/bootstrap plan
terraform -chdir=infrastructure/terraform/bootstrap apply
```

The bootstrap creates `marcelo-497411-facodi-tfstate`, the GitHub WIF pool/provider, and the `facodi-terraform` service account. The state bucket has versioning, public-access prevention and Terraform `prevent_destroy`.

After the successful apply, migrate the bootstrap state into the bucket it created:

```bash
terraform -chdir=infrastructure/terraform/bootstrap init \
  -migrate-state \
  -backend-config="bucket=marcelo-497411-facodi-tfstate" \
  -backend-config="prefix=bootstrap"
```

Record these bootstrap outputs:

```bash
terraform -chdir=infrastructure/terraform/bootstrap output
```

Configure the following GitHub repository variables:

```text
GCP_PROJECT_ID=marcelo-497411
GCP_REGION=europe-southwest1
TERRAFORM_STATE_BUCKET=marcelo-497411-facodi-tfstate
GCP_WORKLOAD_IDENTITY_PROVIDER=<bootstrap workload_identity_provider output>
GCP_TERRAFORM_SERVICE_ACCOUNT=<bootstrap terraform_service_account output>
GCP_DEPLOY_SERVICE_ACCOUNT=facodi-github-deploy@marcelo-497411.iam.gserviceaccount.com
TERRAFORM_PLAN_ENABLED=false
DEPLOY_STAGING_ENABLED=false
DEPLOY_PRODUCTION_ENABLED=false
```

Keep the three enable flags false until their prerequisites are complete.

## 3. Apply shared infrastructure

The shared stack creates/enables common APIs, the `facodi` Artifact Registry Docker repository and the application deployment identity.

```bash
terraform -chdir=infrastructure/terraform/shared init \
  -backend-config="bucket=marcelo-497411-facodi-tfstate" \
  -backend-config="prefix=shared"
terraform -chdir=infrastructure/terraform/shared plan
terraform -chdir=infrastructure/terraform/shared apply
```

After this succeeds, `TERRAFORM_PLAN_ENABLED` can be changed to `true` so pull requests receive remote-state-backed Terraform plans. Pull requests never apply Terraform.

## 4. Create staging persistence with runtime disabled

The committed staging values intentionally begin with:

```hcl
runtime_enabled       = false
public_access_enabled = false
initial_image_uri      = ""
min_instances          = 0
```

Initialize and apply staging:

```bash
terraform -chdir=infrastructure/terraform/environments/staging init \
  -backend-config="bucket=marcelo-497411-facodi-tfstate" \
  -backend-config="prefix=environments/staging"
terraform -chdir=infrastructure/terraform/environments/staging plan
terraform -chdir=infrastructure/terraform/environments/staging apply
```

This creates the staging Cloud SQL instance/database, runtime service account, Cloud Storage bucket and Secret Manager containers without creating the Cloud Run service/job yet.

## 5. Populate staging secrets outside Terraform

Secret payloads must never be passed through Terraform. Set them in the shell, send them to Secret Manager through stdin, then remove them from the shell environment:

```bash
read -rsp 'Staging DB password: ' DB_PASSWORD && echo
read -rsp 'Staging Odoo admin password: ' ODOO_ADMIN_PASSWD && echo

printf '%s' "$DB_PASSWORD" | \
  gcloud secrets versions add facodi-staging-db-password \
  --data-file=- --project marcelo-497411

printf '%s' "$ODOO_ADMIN_PASSWD" | \
  gcloud secrets versions add facodi-staging-admin-passwd \
  --data-file=- --project marcelo-497411

unset DB_PASSWORD ODOO_ADMIN_PASSWD
```

Synchronize the Secret Manager database password with the Cloud SQL `odoo` user:

```bash
GCP_PROJECT_ID=marcelo-497411 \
  bash scripts/configure-database-user.sh staging
```

The script reads the secret only for the duration of the command and creates or updates the Cloud SQL user operationally. Terraform deliberately does not manage the SQL user password, so the password never enters Terraform state.

## 6. Build the first immutable image

Resolve the current `facodi-deploy` commit SHA and publish exactly that image:

```bash
SHA="$(git rev-parse HEAD)"
IMAGE="europe-southwest1-docker.pkg.dev/marcelo-497411/facodi/odoo:${SHA}"

gcloud auth configure-docker europe-southwest1-docker.pkg.dev --quiet
bash scripts/build-image.sh "$IMAGE" --push
```

## 7. Activate staging runtime

Edit `infrastructure/terraform/environments/staging/terraform.tfvars` and commit the activation:

```hcl
runtime_enabled       = true
public_access_enabled = false
initial_image_uri      = "europe-southwest1-docker.pkg.dev/marcelo-497411/facodi/odoo:<first-sha>"
min_instances          = 0
```

Apply staging again. The `initial_image_uri` is only the Terraform creation seed; Terraform ignores later application-driven image changes for the Cloud Run service and migration job.

```bash
terraform -chdir=infrastructure/terraform/environments/staging plan
terraform -chdir=infrastructure/terraform/environments/staging apply
```

After the service and migration job exist, set `DEPLOY_STAGING_ENABLED=true`. Subsequent staging releases use GitHub Actions and `scripts/deploy-runtime.sh`; they do not require Terraform apply just to move the image.

## 8. Staging acceptance gate

Production and public access must remain disabled until all of the following have been exercised in staging:

1. create an Odoo attachment and retrieve it;
2. upload an image through Website/eLearning and render it normally;
3. deploy a different immutable Cloud Run revision;
4. retrieve the same attachment and image after the revision replacement;
5. execute the migration job updating `facodi_learning,theme_facodi` and verify generated assets/pages;
6. perform simultaneous ordinary reads/writes in two browser sessions and inspect Cloud Run logs for GCS FUSE/filestore errors;
7. redeploy a previous known-good image using `scripts/deploy-runtime.sh staging <previous-image>` and verify service health;
8. record whether any Odoo migration changed the database incompatibly with the rolled-back image.

For cron/background-process acceptance, temporarily change staging to `min_instances = 1`, apply Terraform, exercise scheduled/background behavior while the service is idle, and inspect Cloud Run/Odoo logs. Restore `min_instances = 0` afterward if cost-saving scale-to-zero behavior is desired.

The Cloud Storage filestore mount is a proposal until these checks pass. If attachment, Website/eLearning asset or concurrency behavior is unreliable, do not enable production; change the persistence implementation behind the same deployment interface instead.

A v1 limitation is that only the Odoo filestore is made persistent. HTTP sessions remain local to the Cloud Run instance, so a revision replacement may log users out. Session clustering/Redis is deliberately outside the v1 scope and should be revisited before introducing horizontal scaling.

## 9. Public staging access

Only after private authenticated verification succeeds should `public_access_enabled` be changed to `true` in the staging Terraform values and applied. DNS is not managed by this initial Terraform design.

## 10. Production

Production repeats the same persistence/secret/runtime sequence with the production stack. Production differs intentionally:

- Cloud SQL deletion protection is enabled both in Terraform and in the Cloud SQL API settings;
- Cloud Run service/job deletion protection is enabled;
- minimum Cloud Run instances is 1;
- committed production values start disabled;
- `DEPLOY_PRODUCTION_ENABLED` remains false until staging acceptance is documented;
- production deployment is manual (`workflow_dispatch`) and protected by the GitHub `production` Environment.

A push to `main` alone does not deploy production.

## Rollback boundary

Application rollback is image-only and does not run Terraform:

```bash
bash scripts/deploy-runtime.sh staging \
  europe-southwest1-docker.pkg.dev/marcelo-497411/facodi/odoo:<known-good-sha>
```

The migration job runs before the service switches image. Therefore a rollback does not reverse database migrations. Any backward-incompatible Odoo schema/data migration must be reviewed explicitly before production deployment.
