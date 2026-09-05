# FACODI Deploy — Cloud Run + Terraform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `marcelo-m7/facodi-deploy` as the reproducible composition and deployment repository for FACODI: pin both addons, build immutable Odoo 19 images, provision Google Cloud with Terraform, and release safely through Cloud Run + Cloud SQL.

**Architecture:** Terraform owns durable infrastructure and IAM. GitHub Actions owns image build and application rollout. Each environment has a Cloud Run service plus a Cloud Run migration job; the job initializes/upgrades Odoo before the service advances to the same immutable image.

**Tech Stack:** Terraform 1.16.1; `hashicorp/google >= 7.45.0, < 8.0.0`; Cloud Run v2, Cloud Run Jobs v2, Cloud SQL PostgreSQL 16, Cloud Storage, Secret Manager, Artifact Registry, IAM/WIF; Docker/Odoo 19 Community; GitHub Actions; Bash; Python 3 stdlib tests.

**Spec:** `docs/superpowers/specs/2026-09-05-facodi-deploy-cloud-run-terraform-design.md`

## Global Constraints

- Default project: `marcelo-497411`; region: `europe-southwest1`.
- `facodi-learning` and `facodi-theme` remain independent repositories consumed as pinned Git submodules.
- Current Odoo technical modules are `facodi_learning` and `website_facodi`.
- Base image: `odoo:19.0`; database: PostgreSQL 16.
- Cloud Run v1 policy: `workers=0`, `max_cron_threads=1`, `max_instance_count=1`, `proxy_mode=true`.
- Do not use the upstream Odoo Docker entrypoint unchanged: it treats `PORT` as PostgreSQL port, while Cloud Run reserves `PORT` for HTTP. FACODI uses `PORT` only for HTTP and `DB_PORT=5432`/`PGPORT=5432` for PostgreSQL.
- Odoo database initialization and addon updates execute in a Cloud Run v2 Job before service rollout; the web service never migrates during startup.
- No service-account JSON keys and no secret payloads in Git or Terraform state.
- Terraform creates Secret Manager containers/IAM only. Secret versions and the Cloud SQL `odoo` password are configured outside Terraform.
- Images are addressed by immutable `facodi-deploy` Git SHA; no deployment uses `latest` as source of truth.
- Terraform ignores application-driven image changes on the Cloud Run service and migration job.
- Production remains disabled until staging acceptance passes, including Cloud Storage filestore persistence tests.

---

## Target files

```text
.github/workflows/{ci,build-image,terraform-plan,terraform-apply,deploy-staging,deploy-production}.yml
addons/{facodi-learning,facodi-theme}/
docker/{Dockerfile,entrypoint.sh}
infrastructure/terraform/
  bootstrap/
  shared/
  modules/facodi-runtime-gcp/
  environments/{staging,production}/
scripts/{build-image,configure-database-user,deploy-runtime,verify-runtime,validate-repository}.sh
tests/{test_entrypoint.sh,test_repository_contract.py}
docs/operations.md
.gitmodules
.gitignore
README.md
```

## Task 1: Pin the addon repositories and create the static contract

**Files:** `.gitmodules`, `.gitignore`, both `addons/` gitlinks, `scripts/validate-repository.sh`, `tests/test_repository_contract.py`.

**Interfaces:** Produces pinned source inputs and `bash scripts/validate-repository.sh`, used by all later tasks and CI.

- [ ] **Step 1: Write the failing repository contract test.**

```python
from pathlib import Path
import configparser
import unittest

ROOT = Path(__file__).resolve().parents[1]

class RepositoryContractTest(unittest.TestCase):
    def test_submodules_and_modules(self):
        parser = configparser.ConfigParser()
        parser.read(ROOT / ".gitmodules")
        paths = {parser[s]["path"] for s in parser.sections()}
        self.assertEqual(paths, {"addons/facodi-learning", "addons/facodi-theme"})
        self.assertTrue((ROOT / "addons/facodi-learning/facodi_learning/__manifest__.py").is_file())
        self.assertTrue((ROOT / "addons/facodi-theme/website_facodi/__manifest__.py").is_file())

    def test_generated_credentials_and_state_are_ignored(self):
        ignored = (ROOT / ".gitignore").read_text()
        for pattern in ("gha-creds-*.json", "*.tfstate", "*.tfstate.*", ".terraform/"):
            self.assertIn(pattern, ignored)
```

- [ ] **Step 2: Verify RED.** Run `python3 -m unittest tests/test_repository_contract.py -v`; expect failure because submodules/config are absent.

- [ ] **Step 3: Add pinned submodules.**

```bash
git submodule add https://github.com/marcelo-m7/facodi-learning.git addons/facodi-learning
git submodule add https://github.com/marcelo-m7/facodi-theme.git addons/facodi-theme
git submodule update --init --recursive
```

Create `.gitignore`:

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

- [ ] **Step 4: Implement validation.**

```bash
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
test -f .gitmodules
for manifest in addons/facodi-learning/facodi_learning/__manifest__.py addons/facodi-theme/website_facodi/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done
python3 -m unittest tests/test_repository_contract.py -v
```

- [ ] **Step 5: Verify GREEN.** Run `bash scripts/validate-repository.sh`; expect exit 0.
- [ ] **Step 6: Commit.** `git commit -am "build: pin FACODI addon submodules"` after staging the new files/gitlinks.

## Task 2: Build a Cloud Run-safe Odoo 19 image

**Files:** `docker/Dockerfile`, `docker/entrypoint.sh`, `scripts/build-image.sh`, `tests/test_entrypoint.sh`; update `scripts/validate-repository.sh`.

**Interfaces:** `docker/entrypoint.sh serve` starts Odoo; `docker/entrypoint.sh migrate` initializes or upgrades `facodi_learning,website_facodi`.

- [ ] **Step 1: Write a failing test for the `PORT` collision and runtime arguments.** Use fake `wait-for-psql.py`, `psql`, and `odoo` binaries in a temporary `PATH`; set `PORT=8080`, `DB_PORT=5432`; assert the fake Odoo process sees `PORT=8080`, `PGPORT=5432`, and `--http-port=8080`.

```bash
cat >"$tmp/odoo" <<'SH'
#!/usr/bin/env bash
printf 'PORT=%s PGPORT=%s args=%s\n' "$PORT" "$PGPORT" "$*"
SH
# ...make fake helpers executable, invoke entrypoint, then:
grep -q 'PORT=8080 PGPORT=5432' "$tmp/output"
grep -q -- '--http-port=8080' "$tmp/output"
```

- [ ] **Step 2: Verify RED.** Run `bash tests/test_entrypoint.sh`; expect missing entrypoint failure.

- [ ] **Step 3: Implement the entrypoint without passing DB passwords on argv.**

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

export PGHOST="$DB_HOST" PGPORT="$DB_PORT" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" PGDATABASE="$ODOO_DB"
wait-for-psql.py --timeout=60

common=("--database=${ODOO_DB}" "--admin-passwd=${ODOO_ADMIN_PASSWD}")
case "${1:-serve}" in
  serve)
    exec odoo "${common[@]}" "--http-port=${PORT}" --proxy-mode --workers=0 --max-cron-threads=1
    ;;
  migrate)
    if psql -Atqc "select to_regclass('public.ir_module_module') is not null" | grep -qx t; then
      exec odoo "${common[@]}" --stop-after-init "--update=${FACODI_MODULES}"
    else
      exec odoo "${common[@]}" --stop-after-init "--init=base,${FACODI_MODULES}"
    fi
    ;;
  *) echo "usage: $0 {serve|migrate}" >&2; exit 64 ;;
esac
```

- [ ] **Step 4: Compose the image.**

```dockerfile
FROM odoo:19.0
LABEL org.opencontainers.image.source="https://github.com/marcelo-m7/facodi-deploy"
USER root
COPY addons/ /opt/facodi-addon-sources/
COPY docker/entrypoint.sh /usr/local/bin/facodi-entrypoint
RUN set -eux; chmod 0755 /usr/local/bin/facodi-entrypoint; mkdir -p /mnt/extra-addons; \
    for manifest in /opt/facodi-addon-sources/*/*/__manifest__.py; do \
      d="$(dirname "$manifest")"; n="$(basename "$d")"; test ! -e "/mnt/extra-addons/$n"; cp -a "$d" "/mnt/extra-addons/$n"; \
    done; chown -R odoo:odoo /mnt/extra-addons
USER odoo
ENTRYPOINT ["/usr/local/bin/facodi-entrypoint"]
CMD ["serve"]
```

- [ ] **Step 5: Add `scripts/build-image.sh`.** It must run `docker build -f docker/Dockerfile -t "$IMAGE" .` and push only when its second argument is `--push`.
- [ ] **Step 6: Verify GREEN.** Run `bash -n docker/entrypoint.sh scripts/build-image.sh`, `bash tests/test_entrypoint.sh`, and `docker build -f docker/Dockerfile -t facodi-odoo:test .`; all must exit 0.
- [ ] **Step 7: Commit.** `git commit -m "build: add Cloud Run safe Odoo image"`.

## Task 3: Terraform bootstrap and shared infrastructure

**Files:** `infrastructure/terraform/bootstrap/{versions,variables,main,outputs}.tf`; `infrastructure/terraform/shared/{versions,backend,variables,main,outputs}.tf`.

**Interfaces:** Bootstrap consumes a locally authenticated GCP administrator once. It produces state bucket, WIF provider, and Terraform identity. Shared stack produces Artifact Registry and application deployment identity.

- [ ] **Step 1: Pin Terraform/provider.** Every root uses:

```hcl
terraform {
  required_version = ">= 1.16.0, < 1.17.0"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 7.45.0, < 8.0.0" }
  }
}
```

- [ ] **Step 2: Implement bootstrap.** Create `marcelo-497411-facodi-tfstate` with uniform access, public-access prevention, versioning, and `prevent_destroy`; WIF pool `github`; provider `facodi-deploy`; SA `facodi-terraform`. Provider condition is exactly `assertion.repository == 'marcelo-m7/facodi-deploy'` with subject/repository/ref mappings. Grant the repo principal `roles/iam.workloadIdentityUser` on the Terraform SA. Grant that SA: `roles/serviceusage.serviceUsageAdmin`, `roles/artifactregistry.admin`, `roles/run.admin`, `roles/cloudsql.admin`, `roles/storage.admin`, `roles/secretmanager.admin`, `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`.

- [ ] **Step 3: Implement shared stack with partial GCS backend.**

```hcl
terraform { backend "gcs" {} }
```

Enable `run.googleapis.com`, `sqladmin.googleapis.com`, `artifactregistry.googleapis.com`, `secretmanager.googleapis.com`, `iam.googleapis.com`, `iamcredentials.googleapis.com`, `sts.googleapis.com`, `serviceusage.googleapis.com`. Create Docker Artifact Registry `facodi` in Madrid and SA `facodi-github-deploy`. Bind the same repo principal to that SA, grant Artifact Registry Writer on repository `facodi`, and project `roles/run.developer`.

- [ ] **Step 4: Validate without cloud mutations.**

```bash
terraform -chdir=infrastructure/terraform/bootstrap fmt -check
terraform -chdir=infrastructure/terraform/bootstrap init -backend=false
terraform -chdir=infrastructure/terraform/bootstrap validate
terraform -chdir=infrastructure/terraform/shared fmt -check
terraform -chdir=infrastructure/terraform/shared init -backend=false
terraform -chdir=infrastructure/terraform/shared validate
```

- [ ] **Step 5: Commit.** `git commit -m "infra: add Terraform bootstrap and shared resources"`.

## Task 4: Reusable GCP runtime module

**Files:** `infrastructure/terraform/modules/facodi-runtime-gcp/{variables,main,outputs}.tf`.

**Interfaces:** Inputs include project, region, `staging|production`, `initial_image_uri`, enable flags, sizing, and deployment SA email. Outputs include service/job names, DB connection name, secret IDs, bucket, runtime SA, service URI.

- [ ] **Step 1: Define inputs with valid HCL.**

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
variable "runtime_enabled" { type = bool; default = false }
variable "public_access_enabled" { type = bool; default = false }
variable "min_instances" { type = number; default = 0 }
variable "max_instances" { type = number; default = 1 }
variable "database_tier" { type = string; default = "db-custom-1-3840" }
variable "deploy_service_account_email" { type = string }
```

- [ ] **Step 2: Create environment-isolated persistence and IAM.** Names:

```text
facodi-<env>-pg
facodi_<env>
facodi-<env>-runtime
marcelo-497411-facodi-<env>-filestore
facodi-<env>-db-password
facodi-<env>-admin-passwd
```

Cloud SQL uses `database_version = "POSTGRES_16"` and `settings.edition = "ENTERPRISE"` so `db-custom-1-3840` is valid. Enable backups and storage auto-growth. For production set both Terraform `deletion_protection = true` and API-level `settings.deletion_protection_enabled = true`; staging sets them false. Create `google_sql_database` but **not** `google_sql_user`.

Grant runtime SA project `roles/cloudsql.client`, secret accessor only on its two secrets, and bucket `roles/storage.objectUser`. Grant `roles/iam.serviceAccountUser` on the runtime SA to `serviceAccount:${var.deploy_service_account_email}`.

- [ ] **Step 3: Create Cloud Run service and migration job when `runtime_enabled=true`.** Both use Gen2, the same runtime SA, Cloud SQL volume mounted at `/cloudsql`, and GCS volume at `/var/lib/odoo/filestore`:

```hcl
gcs {
  bucket        = google_storage_bucket.filestore.name
  read_only     = false
  mount_options = ["implicit-dirs", "file-mode=0666", "dir-mode=0777"]
}
```

Environment variables are `DB_HOST=/cloudsql/${google_sql_database_instance.main.connection_name}`, `DB_PORT=5432`, `DB_USER=odoo`, `ODOO_DB=facodi_<env>`, `FACODI_MODULES=facodi_learning,website_facodi`. `DB_PASSWORD` and `ODOO_ADMIN_PASSWD` use Secret Manager `value_source.secret_key_ref` version `latest`. Container resources set `cpu_idle = false`; service scaling never exceeds 1. Job args are `migrate`; service uses image default `serve`.

- [ ] **Step 4: Ignore only application image drift.** Service:

```hcl
lifecycle { ignore_changes = [template[0].containers[0].image] }
```

Job:

```hcl
lifecycle { ignore_changes = [template[0].template[0].containers[0].image] }
```

- [ ] **Step 5: Configure invocation IAM.** `allUsers` gets `roles/run.invoker` only when `public_access_enabled=true`. Independently, grant the deployment SA `roles/run.invoker` on the service so authenticated post-deploy verification works while public access is disabled.

- [ ] **Step 6: Commit.** `git commit -m "infra: add FACODI Cloud Run runtime module"`.

## Task 5: Environment roots and DB credential bootstrap

**Files:** `infrastructure/terraform/environments/staging/*`, `production/*`, `scripts/configure-database-user.sh`.

**Interfaces:** Roots consume the module. The DB script copies the Secret Manager DB password into the Cloud SQL `odoo` account without exposing the password to Terraform.

- [ ] **Step 1: Create partial-backend roots.** Both use `terraform { backend "gcs" {} }` and call `../../modules/facodi-runtime-gcp`. Defaults: project `marcelo-497411`, region `europe-southwest1`, `runtime_enabled=false`, `public_access_enabled=false`, `max_instances=1`. Staging `min_instances=0`; production `min_instances=1`. `initial_image_uri` is validated as non-empty whenever runtime is enabled.

- [ ] **Step 2: Implement DB-user bootstrap.**

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

- [ ] **Step 3: Validate roots.**

```bash
for env in staging production; do
  terraform -chdir="infrastructure/terraform/environments/$env" fmt -check
  terraform -chdir="infrastructure/terraform/environments/$env" init -backend=false
  terraform -chdir="infrastructure/terraform/environments/$env" validate
done
bash -n scripts/configure-database-user.sh
```

- [ ] **Step 4: Commit.** `git commit -m "infra: add staging and production roots"`.

## Task 6: Runtime deployment and verification adapter

**Files:** `scripts/deploy-runtime.sh`, `scripts/verify-runtime.sh`.

**Interfaces:** `scripts/deploy-runtime.sh <staging|production> <immutable-image-uri>` updates/executes migration job, then updates service, then verifies it.

- [ ] **Step 1: Implement deployment adapter.**

```bash
#!/usr/bin/env bash
set -euo pipefail
env_name="${1:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
image_uri="${2:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
case "$env_name" in staging|production) ;; *) exit 64 ;; esac
project="${GCP_PROJECT_ID:-marcelo-497411}"
region="${GCP_REGION:-europe-southwest1}"
job="facodi-${env_name}-migrate"
service="facodi-${env_name}"
gcloud run jobs update "$job" --project "$project" --region "$region" --image "$image_uri" --quiet
gcloud run jobs execute "$job" --project "$project" --region "$region" --wait --quiet
gcloud run services update "$service" --project "$project" --region "$region" --image "$image_uri" --quiet
exec "$(dirname "$0")/verify-runtime.sh" "$env_name" "$image_uri"
```

- [ ] **Step 2: Implement `verify-runtime.sh`.** Fail unless `gcloud run services describe` shows Ready=True, expected image URI, runtime SA `facodi-<env>-runtime@marcelo-497411.iam.gserviceaccount.com`, max instances 1, Cloud SQL volume, and GCS volume. Resolve the service URL and verify `/web/login` with an identity token:

```bash
uri="$(gcloud run services describe "$service" --project "$project" --region "$region" --format='value(uri)')"
token="$(gcloud auth print-identity-token)"
curl -fsS -H "Authorization: Bearer $token" "$uri/web/login" >/dev/null
```

- [ ] **Step 3: Syntax-check.** `bash -n scripts/deploy-runtime.sh scripts/verify-runtime.sh` must exit 0.
- [ ] **Step 4: Commit.** `git commit -m "deploy: add Cloud Run migration and rollout adapter"`.

## Task 7: GitHub Actions

**Files:** all six `.github/workflows/*.yml` files.

**Interfaces:** Repository variables: `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_TERRAFORM_SERVICE_ACCOUNT`, `GCP_DEPLOY_SERVICE_ACCOUNT`, `TERRAFORM_STATE_BUCKET`, `TERRAFORM_PLAN_ENABLED`, `DEPLOY_STAGING_ENABLED`, `DEPLOY_PRODUCTION_ENABLED`.

- [ ] **Step 1: CI.** Use `actions/checkout@v7` with recursive submodules and `hashicorp/setup-terraform@v3` with Terraform `1.16.1`. Run repository tests, Docker build, `terraform fmt -check -recursive`, and `init -backend=false && validate` for bootstrap/shared/staging/production. CI needs no Google credentials.

- [ ] **Step 2: Reusable build/push.** Authenticate with `google-github-actions/auth@v3`, install gcloud with `google-github-actions/setup-gcloud@v3`, configure Docker, and push exactly:

```text
europe-southwest1-docker.pkg.dev/marcelo-497411/facodi/odoo:${GITHUB_SHA}
```

Expose `image_uri` as reusable-workflow output.

- [ ] **Step 3: Terraform plan.** PR plan is gated by `${{ vars.TERRAFORM_PLAN_ENABLED == 'true' }}` because initial bootstrap must exist first. Authenticate as Terraform SA; matrix-plan `shared`, `staging`, `production` using state prefixes `shared`, `environments/staging`, `environments/production`. Never apply on PR.

- [ ] **Step 4: Terraform apply.** `workflow_dispatch` only, input `stack` limited to `shared|staging|production`; production uses GitHub Environment `production`. Plan then apply the saved plan; never auto-apply on push.

- [ ] **Step 5: Staging deploy.** Gate on `${{ vars.DEPLOY_STAGING_ENABLED == 'true' }}`, build/push SHA image, authenticate as deployment SA, run `bash scripts/deploy-runtime.sh staging "$IMAGE_URI"`.

- [ ] **Step 6: Production deploy.** `workflow_dispatch` + GitHub Environment `production` + `${{ vars.DEPLOY_PRODUCTION_ENABLED == 'true' }}`. A push to `main` alone does not deploy production.

- [ ] **Step 7: Commit.** `git commit -m "ci: add Terraform and Cloud Run workflows"`.

## Task 8: Operations documentation and final static verification

**Files:** `README.md`, `docs/operations.md`; update validation script as needed.

**Interfaces:** Produces the exact operator runbook and staging acceptance gate.

- [ ] **Step 1: Document first bootstrap sequence exactly.**

```text
1. Authenticate a GCP administrator locally.
2. bootstrap: init -backend=false, plan, apply.
3. Migrate bootstrap state to marcelo-497411-facodi-tfstate prefix bootstrap.
4. Configure GitHub variables from bootstrap outputs.
5. Apply shared stack.
6. Apply staging with runtime_enabled=false.
7. Add latest secret versions for DB password and Odoo admin password.
8. Run scripts/configure-database-user.sh staging.
9. Build/push first immutable image.
10. Apply staging with runtime_enabled=true and initial_image_uri=<that SHA image>.
11. Enable/run staging application deployment.
12. Run filestore and rollback acceptance checks.
13. Only after acceptance, enable public access and consider production.
```

- [ ] **Step 2: Document secret input through stdin and immediate shell cleanup.**

```bash
printf '%s' "$DB_PASSWORD" | gcloud secrets versions add facodi-staging-db-password --data-file=- --project marcelo-497411
printf '%s' "$ODOO_ADMIN_PASSWD" | gcloud secrets versions add facodi-staging-admin-passwd --data-file=- --project marcelo-497411
unset DB_PASSWORD ODOO_ADMIN_PASSWD
```

- [ ] **Step 3: Document mandatory staging filestore acceptance.** Create/retrieve attachment; upload/render Website/eLearning image; deploy a new revision; re-read both; execute migration job updating `facodi_learning,website_facodi`; confirm web assets; perform simultaneous normal reads/writes in two browser sessions and inspect Cloud Run logs for GCS FUSE/filestore errors; exercise image rollback without Terraform and record DB-schema compatibility.

- [ ] **Step 4: Run final local checks.**

```bash
python3 -m unittest tests/test_repository_contract.py -v
bash tests/test_entrypoint.sh
bash scripts/validate-repository.sh
docker build -f docker/Dockerfile -t facodi-odoo:verification .
terraform fmt -check -recursive infrastructure/terraform
for root in bootstrap shared environments/staging environments/production; do
  terraform -chdir="infrastructure/terraform/$root" init -backend=false
  terraform -chdir="infrastructure/terraform/$root" validate
done
git status --short
```

Expected: all test/build/validate commands exit 0 and only intentional uncommitted files appear.

- [ ] **Step 5: Commit.** `git commit -m "docs: document FACODI deployment operations"`.

## Completion gate

Before claiming implementation complete, inspect the branch diff for credentials and verify the production workflows remain gated. Do not claim cloud deployment succeeded until an authenticated Terraform apply has created staging and `scripts/verify-runtime.sh staging <immutable-image-uri>` succeeds against `marcelo-497411`. Application rollback is image-only; it does not reverse Odoo/DB migrations, so any migration requiring backward-incompatible schema changes must be reviewed before production release.
