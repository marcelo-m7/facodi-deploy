# FACODI Deploy

`facodi-deploy` is the composition, infrastructure-as-code and delivery repository for FACODI.

It does not contain FACODI business logic. Instead, it pins the independent `facodi-learning` and `facodi-theme` repositories as Git submodules, builds one immutable Odoo 19 Community image, provisions Google Cloud with Terraform, and releases that image through GitHub Actions.

## Runtime v1

```text
GitHub Actions + OIDC/WIF
        |
        +--> Artifact Registry --> Cloud Run service
        |                         Cloud Run migration job
        |
Terraform ---------------------> Cloud SQL PostgreSQL 16
        |                         Cloud Storage filestore
        +-----------------------> Secret Manager + IAM
```

The repository-level application deployment interface is:

```bash
scripts/deploy-runtime.sh <staging|production> <immutable-image-uri>
```

Cloud Run is the first runtime implementation, but workflows call the repository adapter rather than embedding the runtime rollout sequence directly.

## Source composition

```text
addons/
├── facodi-learning/  -> pinned Git submodule (`facodi_learning`)
└── facodi-theme/     -> pinned Git submodule (`theme_facodi`)
```

A `facodi-deploy` commit therefore identifies the exact addon revisions, container composition and deployment configuration used for a release.

## Lifecycle separation

Terraform owns durable infrastructure and IAM. Ordinary application releases do not run `terraform apply`: GitHub Actions builds a SHA-tagged image, runs the Cloud Run migration job, and advances the service to the same image.

Production is disabled by default. The committed production Terraform values start with `runtime_enabled = false` and `public_access_enabled = false`, and the production deployment workflow also requires `DEPLOY_PRODUCTION_ENABLED=true` plus the protected `production` GitHub Environment.

Staging defaults to `min_instances = 0` to control cost. During cron/background acceptance testing, set staging `min_instances = 1` and apply that Terraform change so the Odoo process remains resident while background behavior is evaluated.

## Local static validation

```bash
git submodule update --init --recursive
bash scripts/validate-repository.sh
docker build -f docker/Dockerfile -t facodi-odoo:local .
terraform fmt -check -recursive infrastructure/terraform
```

Terraform roots are under:

```text
infrastructure/terraform/bootstrap
infrastructure/terraform/shared
infrastructure/terraform/environments/staging
infrastructure/terraform/environments/production
```

See [`docs/operations.md`](docs/operations.md) for the one-time bootstrap, state migration, secret provisioning, staging acceptance and production gate.

## Verification status

Static Python tests, shell tests and workflow YAML parsing can be executed without cloud credentials. Docker image build, Terraform provider validation and live Cloud Run/Cloud SQL verification remain separate gates and must succeed before this proposal is considered production-ready.

## Security rules

- no Google service-account JSON keys;
- no plaintext application secrets in Git or Terraform state;
- no SSH deployment path;
- GitHub authenticates with Workload Identity Federation;
- infrastructure and application deployment use separate Google service accounts;
- staging and production use separate runtime identities, databases, buckets and secrets;
- application images are addressed by immutable Git SHA.
