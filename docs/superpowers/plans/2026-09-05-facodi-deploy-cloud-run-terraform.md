# FACODI Deploy — Cloud Run + Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `marcelo-m7/facodi-deploy` as a reproducible FACODI composition/deployment repository that pins the two FACODI addons, builds immutable Odoo 19 images, provisions Google Cloud with Terraform, and deploys safely to Cloud Run with Cloud SQL.

**Architecture:** Terraform owns durable Google Cloud infrastructure and IAM; GitHub Actions owns application image build and rollout. `staging` and `production` are isolated environment stacks. A Cloud Run migration job applies Odoo initialization/module updates before the corresponding Cloud Run service is advanced to the same immutable image.

**Tech Stack:** Terraform 1.16.1; HashiCorp Google provider `>= 7.45.0, < 8.0.0`; Google Cloud Run v2, Cloud Run Jobs v2, Cloud SQL PostgreSQL 16, Cloud Storage, Secret Manager, Artifact Registry, IAM/WIF; Docker/Odoo 19 Community; GitHub Actions; Bash; Python 3 stdlib tests.

**Spec:** `docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md`

## Global Constraints

- Default Google Cloud project: `marcelo-497411`.
- Default Google Cloud region: `europe-southwest1`.
- Runtime v1 is Google Cloud only, but application deployment is called through `scripts/deploy-runtime.sh` rather than embedding runtime logic in workflows.
- `facodi-learning` and `facodi-theme` remain independent Git repositories and are consumed only as pinned Git submodules.
- Current technical modules are `facodi_learning` and `website_facodi`; module discovery still uses `__manifest__.py` rather than assuming repository names equal technical module names.
- Base image is `odoo:19.0`.
- Cloud SQL database version is PostgreSQL 16.
- Cloud Run Odoo service starts with `workers=0`, `max_cron_threads=1`, `max_instance_count=1`, `proxy_mode=true`.
- The official Odoo Docker entrypoint cannot be used unchanged because it interprets environment variable `PORT` as the PostgreSQL port, while Cloud Run reserves `PORT` for the HTTP listener. The FACODI image therefore has its own entrypoint and uses `DB_PORT=5432` for PostgreSQL.
- A Cloud Run v2 Job performs database initialization/module upgrades before service image rollout. The service itself does not run migrations during startup.
- No service-account JSON keys.
- No secret payloads in Git, Terraform variables, Terraform resources, Terraform outputs, or Terraform state.
- Secret Manager secret containers and IAM are Terraform-managed; secret versions and the Cloud SQL `odoo` user's password are configured operationally outside Terraform.
- Images are deployed by immutable `facodi-deploy` Git SHA; `latest` is never the deployment source of truth.
- Terraform ignores application-driven image changes on both Cloud Run service and migration job.
- Production infrastructure and public access remain disabled until staging acceptance checks pass.
- Cloud Storage filestore is a staging-gated compatibility decision. Production cannot be enabled until attachments, Website/eLearning images, asset generation, redeploy persistence, and ordinary concurrent reads/writes are verified.

---

## File Structure

```text
facodi-deploy/
├── .github/workflows/
│   ├── ci.yml
│   ├── build-image.yml
│   ├── terraform-plan.yml
│   ├── terraform-apply.yml
│   ├── deploy-staging.yml
│   └── deploy-production.yml
├── addons/
│   ├── facodi-learning/          # gitlink
│   └── facodi-theme/             # gitlink
├── docker/
│   ├── Dockerfile
│   └── entrypoint.sh
├── infrastructure/terraform/
│   ├── bootstrap/
│   ├── shared/
│   ├── modules/facodi-runtime-gcp/
│   └── environments/
│       ├── staging/
│       └── production/
├── scripts/
│   ├── build-image.sh
│   ├── configure-database-user.sh
│   ├── deploy-runtime.sh
│   ├── verify-runtime.sh
│   └── validate-repository.sh
├── tests/
│   ├── test_entrypoint.sh
│   └── test_repository_contract.py
├── docs/operations.md
├── .gitmodules
├── .gitignore
└── README.md
```

### Task 1: Pin addon sources and establish the repository contract

**Files:**
- Create: `.gitmodules`
- Create: `.gitignore`
- Create: `addons/facodi-learning` as Git submodule
- Create: `addons/facodi-theme` as Git submodule
- Create: `scripts/validate-repository.sh`
- Create: `tests/test_repository_contract.py`

**Interfaces:**
- Consumes: `https://github.com/marcelo-m7/facodi-learning.git`, `https://github.com/marcelo-m7/facodi-theme.git`.
- Produces: pinned addon gitlinks and `bash scripts/validate-repository.sh` as the static contract used by local development and CI.

- [ ] **Step 1: Add a failing repository-contract test**

```python
# tests/test_repository_contract.py
from pathlib import Path
import configparser
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RepositoryContractTest(unittest.TestCase):
    def test_expected_submodules_and_manifests_exist(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, {"addons/facodi-learning", "addons/facodi-theme"})
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/website_facodi/__manifest__.py").is_file())

    def test_no_credential_files_are_tracked_by_contract(self):
        ignored = (ROOT / ".gitignore").read_text()
        self.assertIn("gha-creds-*.json", ignored)
        self.assertIn("*.tfstate", ignored)
        self.assertIn("*.tfstate.*", ignored)

if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify that it fails before submodules/config exist**

Run: `python3 -m unittest tests/test_repository_contract.py -v`

Expected: FAIL because `.gitmodules`/submodule manifests do not exist yet.

- [ ] **Step 3: Add the two submodules and ignore generated credentials/state**

Run:

```bash
git submodule add https://github.com/marcelo-m7/facodi-learning.git addons/facodi-learning
git submodule add https://github.com/marcelo-m7/facodi-theme.git addons/facodi-theme
git submodule update --init --recursive
```

Create `.gitignore` with:

```gitignore
gha-creds-*.json
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
.env
.env.*
!.env.example
__pycache__/
```

- [ ] **Step 4: Implement static validation**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

test -f .gitmodules
for manifest in \
  addons/facodi-learning/facodi_learning/__manifest__.py \
  addons/facodi-theme/website_facodi/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

python3 -m unittest tests/test_repository_contract.py -v
bash -n scripts/*.sh 2>/dev/null || true
```

- [ ] **Step 5: Re-run the contract test**

Run: `bash scripts/validate-repository.sh`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules .gitignore addons scripts/validate-repository.sh tests/test_repository_contract.py
git commit -m "build: pin FACODI addon submodules"
```

### Task 2: Build a Cloud Run-safe Odoo 19 image

**Files:**
- Create: `docker/Dockerfile`
- Create: `docker/entrypoint.sh`
- Create: `scripts/build-image.sh`
- Create: `tests/test_entrypoint.sh`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: pinned addon directories from Task 1 and runtime env vars `PORT`, `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `ODOO_DB`, `ODOO_ADMIN_PASSWD`, `FACODI_MODULES`.
- Produces: one Odoo image with `/mnt/extra-addons/facodi_learning` and `/mnt/extra-addons/website_facodi`; entrypoint modes `serve` and `migrate`.

- [ ] **Step 1: Write an entrypoint test that proves Cloud Run `PORT` is not reused as the DB port**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/wait-for-psql.py" <<'SH'
#!/usr/bin/env bash
printf 'wait %s\n' "$*"
SH
cat >"$tmp/odoo" <<'SH'
#!/usr/bin/env bash
printf 'odoo %s\n' "$*"
SH
chmod +x "$tmp/wait-for-psql.py" "$tmp/odoo"

PATH="$tmp:$PATH" \
PORT=8080 \
DB_HOST=/cloudsql/marcelo-497411:europe-southwest1:facodi-staging-pg \
DB_PORT=5432 \
DB_USER=odoo \
DB_PASSWORD=test-password \
ODOO_DB=facodi_staging \
ODOO_ADMIN_PASSWD=test-admin \
FACODI_MODULES=facodi_learning,website_facodi \
bash "$root/docker/entrypoint.sh" serve >"$tmp/output"

grep -q -- '--http-port=8080' "$tmp/output"
grep -q -- '--db_port=5432' "$tmp/output"
! grep -q -- '--db_port=8080' "$tmp/output"
```

- [ ] **Step 2: Verify the test fails because the custom entrypoint does not exist**

Run: `bash tests/test_entrypoint.sh`

Expected: FAIL with missing `docker/entrypoint.sh`.

- [ ] **Step 3: Implement the custom entrypoint**

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${DB_PORT:=5432}"
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${ODOO_DB:?ODOO_DB is required}"
: "${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD is required}"
: "${FACODI_MODULES:=facodi_learning,website_facodi}"

DB_ARGS=(
  "--db_host=${DB_HOST}"
  "--db_port=${DB_PORT}"
  "--db_user=${DB_USER}"
  "--db_password=${DB_PASSWORD}"
  "--database=${ODOO_DB}"
)

wait-for-psql.py "${DB_ARGS[@]}" --timeout=60

case "${1:-serve}" in
  serve)
    exec odoo \
      "${DB_ARGS[@]}" \
      "--http-port=${PORT}" \
      --proxy-mode \
      --workers=0 \
      --max-cron-threads=1 \
      "--admin-passwd=${ODOO_ADMIN_PASSWD}"
    ;;
  migrate)
    if psql "host=${DB_HOST} port=${DB_PORT} user=${DB_USER} dbname=${ODOO_DB} password=${DB_PASSWORD}" \
      -Atqc "select 1 from information_schema.tables where table_name='ir_module_module'" | grep -q '^1$'; then
      exec odoo "${DB_ARGS[@]}" --stop-after-init "--update=${FACODI_MODULES}" "--admin-passwd=${ODOO_ADMIN_PASSWD}"
    else
      exec odoo "${DB_ARGS[@]}" --stop-after-init "--init=base,${FACODI_MODULES}" "--admin-passwd=${ODOO_ADMIN_PASSWD}"
    fi
    ;;
  *)
    echo "usage: $0 {serve|migrate}" >&2
    exit 64
    ;;
esac
```

- [ ] **Step 4: Implement the image composition**

```dockerfile
FROM odoo:19.0

LABEL org.opencontainers.image.source="https://github.com/marcelo-m7/facodi-deploy"
LABEL org.opencontainers.image.title="FACODI Odoo"

USER root
COPY addons/ /opt/facodi-addon-sources/
COPY docker/entrypoint.sh /usr/local/bin/facodi-entrypoint
RUN set -eux; \
    chmod 0755 /usr/local/bin/facodi-entrypoint; \
    mkdir -p /mnt/extra-addons; \
    for manifest in /opt/facodi-addon-sources/*/*/__manifest__.py; do \
      module_dir="$(dirname "$manifest")"; \
      module_name="$(basename "$module_dir")"; \
      test ! -e "/mnt/extra-addons/$module_name"; \
      cp -a "$module_dir" "/mnt/extra-addons/$module_name"; \
    done; \
    chown -R odoo:odoo /mnt/extra-addons
USER odoo
ENTRYPOINT ["/usr/local/bin/facodi-entrypoint"]
CMD ["serve"]
```

- [ ] **Step 5: Implement the build wrapper**

```bash
#!/usr/bin/env bash
set -euo pipefail
image="${1:?usage: scripts/build-image.sh IMAGE_URI [--push]}"
push="${2:-}"
docker build -f docker/Dockerfile -t "$image" .
if [[ "$push" == "--push" ]]; then
  docker push "$image"
fi
```

- [ ] **Step 6: Run syntax, entrypoint, and Docker build checks**

Run:

```bash
bash -n docker/entrypoint.sh scripts/build-image.sh
bash tests/test_entrypoint.sh
docker build -f docker/Dockerfile -t facodi-odoo:test .
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```bash
git add docker scripts/build-image.sh scripts/validate-repository.sh tests/test_entrypoint.sh
git commit -m "build: add Cloud Run safe Odoo image"
```

### Task 3: Create Terraform bootstrap and shared infrastructure

**Files:**
- Create: `infrastructure/terraform/bootstrap/{versions.tf,variables.tf,main.tf,outputs.tf}`
- Create: `infrastructure/terraform/shared/{versions.tf,backend.tf,variables.tf,main.tf,outputs.tf}`

**Interfaces:**
- Consumes: admin ADC credentials for the one-time bootstrap; defaults `project_id=marcelo-497411`, `region=europe-southwest1`, GitHub repo `marcelo-m7/facodi-deploy`.
- Produces: GCS Terraform state bucket, WIF pool/provider, `facodi-terraform` identity, Artifact Registry `facodi`, and `facodi-github-deploy` identity.

- [ ] **Step 1: Add Terraform version/provider constraints to both roots**

```hcl
terraform {
  required_version = ">= 1.16.0, < 1.17.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.45.0, < 8.0.0"
    }
  }
}
```

- [ ] **Step 2: Implement bootstrap resources**

The bootstrap root must create:

```text
GCS bucket: marcelo-497411-facodi-tfstate
WIF pool: github
WIF provider: facodi-deploy
Terraform SA: facodi-terraform@marcelo-497411.iam.gserviceaccount.com
```

The provider condition must restrict tokens to `assertion.repository == 'marcelo-m7/facodi-deploy'`. Map `google.subject=assertion.sub`, `attribute.repository=assertion.repository`, `attribute.ref=assertion.ref`.

Grant the repository principal `roles/iam.workloadIdentityUser` on the Terraform service account. Grant the Terraform service account only the project roles needed by the declared stacks: `roles/serviceusage.serviceUsageAdmin`, `roles/artifactregistry.admin`, `roles/run.admin`, `roles/cloudsql.admin`, `roles/storage.admin`, `roles/secretmanager.admin`, `roles/iam.serviceAccountAdmin`, and `roles/resourcemanager.projectIamAdmin`.

Protect the state bucket with uniform bucket-level access, public-access prevention, versioning, and `lifecycle { prevent_destroy = true }`.

- [ ] **Step 3: Implement shared resources**

The shared root uses a partial GCS backend:

```hcl
terraform {
  backend "gcs" {}
}
```

Create/enable the APIs for Cloud Run, Cloud SQL Admin, Artifact Registry, Secret Manager, IAM Credentials, STS, and Service Usage. Create Artifact Registry repository `facodi` in `europe-southwest1`. Create `facodi-github-deploy` and grant its WIF principal `roles/iam.workloadIdentityUser`. Grant Artifact Registry Writer on repository `facodi` to the deployment SA and project `roles/run.developer` to that SA.

- [ ] **Step 4: Format and validate without touching the cloud**

Run:

```bash
terraform -chdir=infrastructure/terraform/bootstrap fmt -check
terraform -chdir=infrastructure/terraform/bootstrap init -backend=false
terraform -chdir=infrastructure/terraform/bootstrap validate
terraform -chdir=infrastructure/terraform/shared fmt -check
terraform -chdir=infrastructure/terraform/shared init -backend=false
terraform -chdir=infrastructure/terraform/shared validate
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add infrastructure/terraform/bootstrap infrastructure/terraform/shared
git commit -m "infra: add Terraform bootstrap and shared GCP resources"
```

### Task 4: Implement the reusable GCP runtime module

**Files:**
- Create: `infrastructure/terraform/modules/facodi-runtime-gcp/{variables.tf,main.tf,outputs.tf}`

**Interfaces:**
- Consumes: project, region, environment name, initial image URI, runtime/public-enable flags.
- Produces: isolated Cloud SQL PostgreSQL 16, database, runtime SA, GCS filestore bucket, Secret Manager containers, Cloud Run migration job, Cloud Run service, and runtime outputs.

- [ ] **Step 1: Define exact module inputs**

```hcl
variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}
variable "initial_image_uri" { type = string }
variable "runtime_enabled" { type = bool, default = false }
variable "public_access_enabled" { type = bool, default = false }
variable "min_instances" { type = number, default = 0 }
variable "max_instances" { type = number, default = 1 }
variable "database_tier" { type = string, default = "db-custom-1-3840" }
```

- [ ] **Step 2: Create isolated persistent resources**

Use names derived from the environment:

```text
Cloud SQL: facodi-<environment>-pg
Database: facodi_<environment>
Runtime SA: facodi-<environment>-runtime
Bucket: marcelo-497411-facodi-<environment>-filestore
Secrets: facodi-<environment>-db-password, facodi-<environment>-admin-passwd
Cloud Run service: facodi-<environment>
Migration job: facodi-<environment>-migrate
```

Cloud SQL must use `database_version = "POSTGRES_16"`, automatic storage growth, backups enabled, and production deletion protection. Do not create `google_sql_user` because its password would enter Terraform state.

Grant the runtime SA `roles/cloudsql.client`, Secret Manager accessor only on the two environment secrets, and `roles/storage.objectUser` only on the environment filestore bucket.

- [ ] **Step 3: Implement Cloud Run service and migration job behind `runtime_enabled`**

Use `google_cloud_run_v2_service` and `google_cloud_run_v2_job`. Both mount the same Cloud SQL volume at `/cloudsql` and the same GCS filestore volume at `/var/lib/odoo/filestore`. Configure GCS mount options so the non-root `odoo` process can write without assuming an image-specific UID:

```hcl
gcs {
  bucket        = google_storage_bucket.filestore.name
  read_only     = false
  mount_options = ["implicit-dirs", "file-mode=0666", "dir-mode=0777"]
}
```

Service env must include:

```text
DB_HOST=/cloudsql/<instance-connection-name>
DB_PORT=5432
DB_USER=odoo
ODOO_DB=facodi_<environment>
FACODI_MODULES=facodi_learning,website_facodi
```

`DB_PASSWORD` and `ODOO_ADMIN_PASSWD` must use Secret Manager `value_source.secret_key_ref` with version `latest`.

Set execution environment Gen2, `max_instance_count = 1`, `cpu_idle = false`, and service container command/args to use the image default `serve`. Configure the migration job to pass `migrate`.

Add:

```hcl
lifecycle {
  ignore_changes = [template[0].containers[0].image]
}
```

to both the service and migration job so application releases do not become Terraform drift.

- [ ] **Step 4: Add public invocation only when explicitly enabled**

Use `google_cloud_run_v2_service_iam_member` with `member = "allUsers"`, `role = "roles/run.invoker"`, and `count = var.public_access_enabled ? 1 : 0`.

- [ ] **Step 5: Validate module through an environment root in Task 5 rather than applying it directly**

Run after Task 5 root creation: `terraform validate` from both environment roots.

- [ ] **Step 6: Commit**

```bash
git add infrastructure/terraform/modules/facodi-runtime-gcp
git commit -m "infra: add FACODI Cloud Run runtime module"
```

### Task 5: Add staging and production Terraform roots and operational secret bootstrap

**Files:**
- Create: `infrastructure/terraform/environments/staging/{versions.tf,backend.tf,main.tf,variables.tf,terraform.tfvars.example,outputs.tf}`
- Create: `infrastructure/terraform/environments/production/{versions.tf,backend.tf,main.tf,variables.tf,terraform.tfvars.example,outputs.tf}`
- Create: `scripts/configure-database-user.sh`

**Interfaces:**
- Consumes: shared remote infrastructure and externally populated Secret Manager versions.
- Produces: isolated state prefixes `environments/staging` and `environments/production`; one-time operational creation/update of the Cloud SQL `odoo` DB user without putting its password into Terraform state.

- [ ] **Step 1: Wire both roots to the runtime module**

Staging defaults:

```hcl
project_id            = "marcelo-497411"
region                = "europe-southwest1"
runtime_enabled       = false
public_access_enabled = false
min_instances         = 0
max_instances         = 1
database_tier         = "db-custom-1-3840"
```

Production defaults:

```hcl
project_id            = "marcelo-497411"
region                = "europe-southwest1"
runtime_enabled       = false
public_access_enabled = false
min_instances         = 1
max_instances         = 1
database_tier         = "db-custom-1-3840"
```

`initial_image_uri` is required only when `runtime_enabled=true`; use a validation rule requiring a non-empty URI in that case.

- [ ] **Step 2: Implement DB-user configuration outside Terraform**

```bash
#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: scripts/configure-database-user.sh staging|production}"
case "$env_name" in staging|production) ;; *) exit 64 ;; esac

project="${GCP_PROJECT_ID:-marcelo-497411}"
instance="facodi-${env_name}-pg"
secret="facodi-${env_name}-db-password"
password="$(gcloud secrets versions access latest --project "$project" --secret "$secret")"

if gcloud sql users list --project "$project" --instance "$instance" --format='value(name)' | grep -qx odoo; then
  gcloud sql users set-password odoo --project "$project" --instance "$instance" --password "$password"
else
  gcloud sql users create odoo --project "$project" --instance "$instance" --password "$password"
fi
unset password
```

- [ ] **Step 3: Validate both roots without backend/cloud access**

Run:

```bash
for env in staging production; do
  terraform -chdir="infrastructure/terraform/environments/$env" fmt -check
  terraform -chdir="infrastructure/terraform/environments/$env" init -backend=false
  terraform -chdir="infrastructure/terraform/environments/$env" validate
done
bash -n scripts/configure-database-user.sh
```

Expected: all commands exit 0.

- [ ] **Step 4: Commit**

```bash
git add infrastructure/terraform/environments scripts/configure-database-user.sh
git commit -m "infra: add isolated staging and production stacks"
```

### Task 6: Implement runtime deployment, migration, verification, and rollback-safe image rollout

**Files:**
- Create: `scripts/deploy-runtime.sh`
- Create: `scripts/verify-runtime.sh`

**Interfaces:**
- Consumes: `<environment> <image-uri>` and authenticated `gcloud` session.
- Produces: successful migration job execution followed by service image rollout and verification.

- [ ] **Step 1: Implement the runtime-neutral entry contract**

```bash
#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
image_uri="${2:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
case "$env_name" in staging|production) ;; *) exit 64 ;; esac

project="${GCP_PROJECT_ID:-marcelo-497411}"
region="${GCP_REGION:-europe-southwest1}"
service="facodi-${env_name}"
job="facodi-${env_name}-migrate"

gcloud run jobs update "$job" --project "$project" --region "$region" --image "$image_uri" --quiet
gcloud run jobs execute "$job" --project "$project" --region "$region" --wait --quiet
gcloud run services update "$service" --project "$project" --region "$region" --image "$image_uri" --quiet
exec "$(dirname "$0")/verify-runtime.sh" "$env_name" "$image_uri"
```

- [ ] **Step 2: Implement live verification**

`verify-runtime.sh` must use `gcloud run services describe` and fail unless:

```text
service exists
Ready=True
deployed container image == expected immutable URI
service account == facodi-<environment>-runtime@marcelo-497411.iam.gserviceaccount.com
max instance count == 1
Cloud SQL volume exists
GCS volume exists
```

Then obtain the service URI with:

```bash
gcloud run services describe "$service" --project "$project" --region "$region" --format='value(uri)'
```

and perform an HTTP request to `/web/login`. When the service is not yet public, use an identity token:

```bash
curl -fsS -H "Authorization: Bearer $(gcloud auth print-identity-token)" "$uri/web/login" >/dev/null
```

- [ ] **Step 3: Add syntax checks and a dry static contract check**

Run:

```bash
bash -n scripts/deploy-runtime.sh scripts/verify-runtime.sh
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add scripts/deploy-runtime.sh scripts/verify-runtime.sh
git commit -m "deploy: add Cloud Run migration and rollout adapter"
```

### Task 7: Add GitHub Actions CI, Terraform, and application delivery workflows

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/build-image.yml`
- Create: `.github/workflows/terraform-plan.yml`
- Create: `.github/workflows/terraform-apply.yml`
- Create: `.github/workflows/deploy-staging.yml`
- Create: `.github/workflows/deploy-production.yml`

**Interfaces:**
- Consumes repository variables `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_ARTIFACT_REPOSITORY`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_TERRAFORM_SERVICE_ACCOUNT`, `GCP_DEPLOY_SERVICE_ACCOUNT`, `TERRAFORM_STATE_BUCKET`, `DEPLOY_STAGING_ENABLED`, `DEPLOY_PRODUCTION_ENABLED`.
- Produces: credentialless CI/CD through GitHub OIDC/WIF.

- [ ] **Step 1: Implement CI with no Google credentials**

Use `actions/checkout@v7` with `submodules: recursive`, install Terraform with `hashicorp/setup-terraform@v3` and `terraform_version: 1.16.1`, then run:

```bash
bash scripts/validate-repository.sh
bash tests/test_entrypoint.sh
docker build -f docker/Dockerfile -t facodi-odoo:ci .
terraform fmt -check -recursive infrastructure/terraform
for root in bootstrap shared environments/staging environments/production; do
  terraform -chdir="infrastructure/terraform/$root" init -backend=false
  terraform -chdir="infrastructure/terraform/$root" validate
done
```

- [ ] **Step 2: Implement reusable image build/push**

Authenticate with `google-github-actions/auth@v3`, configure gcloud with `google-github-actions/setup-gcloud@v3`, configure Docker for `${GCP_REGION}-docker.pkg.dev`, and publish:

```text
${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/facodi/odoo:${GITHUB_SHA}
```

The workflow output must be `image_uri`.

- [ ] **Step 3: Implement Terraform plan**

For pull requests touching `infrastructure/terraform/**`, authenticate using `GCP_TERRAFORM_SERVICE_ACCOUNT`. Initialize the selected `shared`, `staging`, or `production` root with:

```bash
terraform init \
  -backend-config="bucket=${TERRAFORM_STATE_BUCKET}" \
  -backend-config="prefix=<root-specific-prefix>"
terraform plan -no-color -out=tfplan
```

Never run apply on a pull-request event.

- [ ] **Step 4: Implement explicit Terraform apply**

Use only `workflow_dispatch`, input `stack` with allowed values `shared`, `staging`, `production`, and GitHub Environment matching staging/production when applicable. Run plan and `terraform apply -auto-approve tfplan`. Do not implement automatic apply on push.

- [ ] **Step 5: Implement staging application deploy**

Trigger on `workflow_dispatch` and optionally `push` to a future `staging` branch, but gate the whole job with:

```yaml
if: ${{ vars.DEPLOY_STAGING_ENABLED == 'true' }}
```

Build/push the SHA image, authenticate as `GCP_DEPLOY_SERVICE_ACCOUNT`, and call:

```bash
bash scripts/deploy-runtime.sh staging "$IMAGE_URI"
```

- [ ] **Step 6: Implement production application deploy**

Production uses GitHub Environment `production`, `workflow_dispatch`, and:

```yaml
if: ${{ vars.DEPLOY_PRODUCTION_ENABLED == 'true' }}
```

Do not deploy production merely because `main` receives a push.

- [ ] **Step 7: Commit**

```bash
git add .github/workflows
git commit -m "ci: add Terraform and Cloud Run delivery workflows"
```

### Task 8: Document bootstrap, first staging rollout, acceptance gate, and repository usage

**Files:**
- Modify: `README.md`
- Create: `docs/operations.md`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: exact operator sequence from empty project permissions to first staging deploy and production gate.

- [ ] **Step 1: Document the one-time bootstrap sequence**

Document these exact phases:

```text
1. Admin authenticates locally with gcloud Application Default Credentials.
2. terraform/bootstrap init -backend=false + apply.
3. terraform/bootstrap init -migrate-state with bucket marcelo-497411-facodi-tfstate and prefix bootstrap.
4. Configure GitHub repository variables with bootstrap outputs.
5. Apply shared stack from GitHub or locally.
6. Apply staging with runtime_enabled=false.
7. Add secret versions for facodi-staging-db-password and facodi-staging-admin-passwd.
8. Run scripts/configure-database-user.sh staging.
9. Build/push the first immutable image.
10. Apply staging with runtime_enabled=true and initial_image_uri set to that SHA image.
11. Run deploy-staging workflow.
12. Perform filestore acceptance tests.
13. Only after acceptance, enable public access and consider production.
```

- [ ] **Step 2: Document secret creation without printing values**

Use commands that read from stdin:

```bash
printf '%s' "$DB_PASSWORD" | gcloud secrets versions add facodi-staging-db-password --data-file=- --project marcelo-497411
printf '%s' "$ODOO_ADMIN_PASSWD" | gcloud secrets versions add facodi-staging-admin-passwd --data-file=- --project marcelo-497411
```

The docs must tell the operator to `unset DB_PASSWORD ODOO_ADMIN_PASSWD` afterward and never place them in `.tfvars`.

- [ ] **Step 3: Document the staging filestore acceptance test**

The checklist must require:

```text
- create and retrieve a normal attachment;
- upload and display a Website/eLearning image;
- deploy another revision of the same application;
- verify both objects remain readable after revision replacement;
- update/install facodi_learning and website_facodi through the migration job;
- verify generated web assets remain healthy;
- perform ordinary simultaneous reads/writes from at least two browser sessions and inspect Cloud Run logs for GCS FUSE/filestore errors;
- exercise an application image rollback without Terraform and record whether the database schema remains compatible.
```

- [ ] **Step 4: Run all local verification**

Run:

```bash
bash scripts/validate-repository.sh
bash tests/test_entrypoint.sh
docker build -f docker/Dockerfile -t facodi-odoo:final-check .
terraform fmt -check -recursive infrastructure/terraform
for root in bootstrap shared environments/staging environments/production; do
  terraform -chdir="infrastructure/terraform/$root" init -backend=false
  terraform -chdir="infrastructure/terraform/$root" validate
done
```

Expected: every command exits 0.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/operations.md scripts/validate-repository.sh
git commit -m "docs: document FACODI deployment operations"
```

## Final verification and review gate

Before claiming implementation complete:

```bash
git status --short
python3 -m unittest tests/test_repository_contract.py -v
bash tests/test_entrypoint.sh
bash scripts/validate-repository.sh
docker build -f docker/Dockerfile -t facodi-odoo:verification .
terraform fmt -check -recursive infrastructure/terraform
```

Then validate every Terraform root with `init -backend=false && validate`, inspect the branch diff for credentials, and confirm that production deploy/apply workflows remain explicitly gated. Do not claim Google Cloud resources exist until a real authenticated Terraform apply and `scripts/verify-runtime.sh staging <immutable-image-uri>` succeed against `marcelo-497411`.
