# FACODI Deploy — Cloud Run + Terraform Design

## Purpose

Create `marcelo-m7/facodi-deploy` as the dedicated composition, infrastructure and delivery repository for FACODI.

The repository does not own FACODI business logic. It pins the independent `facodi-learning` and `facodi-theme` repositories as Git submodules, builds one immutable Odoo 19 Community image from those pinned revisions, provisions the target infrastructure with Terraform, and deploys application revisions through GitHub Actions.

The architecture is runtime-neutral at the repository boundary, while the first concrete runtime implementation is Google Cloud Run backed by Cloud SQL PostgreSQL.

This design implements the direction tracked in issue #1.

## Design principles

1. `facodi-deploy` is a deployment/composition repository, not an addon monorepo.
2. FACODI addons remain independently versioned repositories.
3. A commit in `facodi-deploy` identifies the exact addon revisions and deployment configuration used for a release.
4. Terraform owns durable cloud infrastructure and IAM.
5. GitHub Actions owns application build and release flow.
6. Ordinary application deployments do not require a Terraform apply.
7. GitHub authenticates to Google Cloud through OIDC / Workload Identity Federation; no service-account JSON key is created or stored.
8. Production is never enabled implicitly by repository initialization or staging validation.
9. Infrastructure modules expose provider-neutral deployment concepts where practical, but only Google Cloud is implemented in v1.

## Repository boundaries

`facodi-deploy` owns:

- pinned Git submodule revisions for FACODI addons;
- Docker image composition;
- Terraform configuration;
- Google Cloud IAM and Workload Identity Federation required by deployment;
- Artifact Registry;
- Cloud Run runtime configuration;
- Cloud SQL PostgreSQL;
- persistent filestore storage;
- Secret Manager integration;
- CI validation;
- infrastructure plan/apply workflows;
- staging and production application deployment workflows;
- operational documentation and verification scripts.

`facodi-deploy` does not own:

- Odoo business models or application logic;
- FACODI theme source code;
- FACODI learning source code;
- duplicated copies of addon repositories;
- user-generated FACODI data;
- long-lived Google credentials.

## Source composition

The repository consumes these independent repositories as Git submodules:

```text
addons/
├── facodi-learning/  -> https://github.com/marcelo-m7/facodi-learning
└── facodi-theme/     -> https://github.com/marcelo-m7/facodi-theme
```

The Docker build resolves the pinned submodule commits and copies the actual Odoo modules into `/mnt/extra-addons`.

`facodi_learning` is expected from `facodi-learning`. The theme technical module is discovered from the pinned `facodi-theme` repository by locating its `__manifest__.py`; the deployment repository does not hard-code the repository directory name as the Odoo technical module name.

The image build must discover valid Odoo modules by `__manifest__.py` rather than assuming that the repository directory and technical module directory have the same name.

No deployment workflow follows the moving `main` branch of an addon at runtime. A new addon version becomes deployable only when the corresponding submodule pointer is intentionally updated in `facodi-deploy`.

## Target repository structure

```text
facodi-deploy/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       ├── deploy-staging.yml
│       └── deploy-production.yml
├── addons/
│   ├── facodi-learning/
│   └── facodi-theme/
├── docker/
│   ├── Dockerfile
│   └── entrypoint.sh
├── infrastructure/
│   └── terraform/
│       ├── bootstrap/
│       ├── shared/
│       ├── modules/
│       │   ├── artifact-registry/
│       │   ├── github-wif/
│       │   ├── runtime-identity/
│       │   └── facodi-runtime-gcp/
│       └── environments/
│           ├── staging/
│           └── production/
├── scripts/
│   ├── build-image.sh
│   ├── deploy-runtime.sh
│   ├── validate-repository.sh
│   └── verify-runtime.sh
├── docs/
│   └── superpowers/
│       ├── specs/
│       └── plans/
├── .gitmodules
├── .gitignore
└── README.md
```

The structure intentionally keeps the application release interface outside Terraform. `scripts/deploy-runtime.sh` is the stable repository-level deployment interface. In v1 it dispatches to Google Cloud Run behavior. A future runtime may replace the implementation without changing image composition or addon pinning.

## Infrastructure lifecycle

Terraform is responsible for infrastructure that should be declarative, reviewable and reproducible.

### Bootstrap stack

Terraform remote state creates a bootstrap dependency: the GCS state bucket and initial GitHub federation cannot depend on a backend that does not exist yet.

`infrastructure/terraform/bootstrap/` therefore runs once with an authenticated Google Cloud administrator and an initial local Terraform state. It creates:

- the GCS bucket used by Terraform remote state;
- the Workload Identity Pool and GitHub provider for `marcelo-m7/facodi-deploy`;
- the GitHub Terraform service account;
- the minimum IAM grants required for the subsequent Terraform workflows.

After the first successful bootstrap apply, the bootstrap state itself is migrated into the newly created GCS backend. The bucket is protected from accidental deletion and is not destroyed as part of ordinary environment teardown.

This one-time operation requires an operator who already has the project-level permissions needed to create WIF and IAM bindings. Terraform does not bypass Google Cloud IAM policy.

### Shared infrastructure

`infrastructure/terraform/shared/` manages resources that are common to both environments:

- required Google APIs;
- Artifact Registry Docker repository;
- shared deployment identities where appropriate.

A single Artifact Registry repository stores immutable FACODI images addressed by Git commit SHA.

### Environment stacks

`staging` and `production` are separate Terraform root modules and separate Terraform state objects.

Each environment owns its own:

- Cloud Run service;
- Cloud SQL PostgreSQL instance and database;
- runtime service account;
- Cloud Storage filestore bucket;
- Secret Manager secret resources and IAM bindings;
- environment-specific runtime policy.

The first implementation deliberately prefers environment isolation over sharing the same PostgreSQL instance. This avoids staging activity competing with production and prevents two Terraform states from managing the same database instance.

Production infrastructure may remain unapplied until explicitly approved.

## Terraform implementation policy

The Google provider uses `google_cloud_run_v2_service` rather than the legacy Cloud Run v1 Terraform resource. The current HashiCorp Google provider documentation recommends Cloud Run v2 for broader feature support and a better resource model.

Terraform configuration must:

- pin a supported Terraform core version range;
- pin the HashiCorp Google provider to a compatible version range rather than an unbounded latest version;
- use `terraform fmt -check` and `terraform validate` in CI;
- expose environment differences through input variables rather than duplicated resource definitions;
- use deletion protection for production Cloud SQL;
- avoid storing secret payloads in Terraform state.

Terraform creates Secret Manager secret containers and IAM policy, but secret values are populated outside Terraform so passwords do not become Terraform state values.

## Application lifecycle

Application releases are independent from infrastructure changes.

The delivery flow is:

```text
facodi-deploy commit
      |
      v
checkout --recursive
      |
      v
repository validation
      |
      v
Docker build: Odoo 19 + pinned addons
      |
      v
Artifact Registry
      |
      v
runtime deployment adapter
      |
      v
Cloud Run revision
```

Images are tagged by immutable Git commit SHA. Mutable tags such as `latest` are not the deployment source of truth.

An ordinary application deployment updates only the Cloud Run container image. It must not change database configuration, IAM, storage, secrets, scaling policy or other infrastructure settings.

To prevent Terraform from treating an application image rollout as infrastructure drift, the Cloud Run Terraform resource ignores changes to the deployed container image while continuing to manage the remaining service configuration. Terraform establishes the service and its runtime contract; GitHub Actions advances the image revision.

## GitHub Actions model

### CI

`ci.yml` runs for pull requests and relevant pushes and performs checks that require no Google credentials:

- recursive submodule checkout;
- repository contract validation;
- Odoo addon manifest discovery;
- Docker build validation;
- shell syntax checks;
- Terraform format checks;
- Terraform initialization without backend where appropriate;
- Terraform validation.

### Terraform plan

`terraform-plan.yml` authenticates through WIF and creates plans for infrastructure changes. Pull requests that touch Terraform files expose the plan result for review.

No pull request event performs `terraform apply`.

### Terraform apply

`terraform-apply.yml` is explicitly dispatched and uses GitHub Environments for deployment protection. Production apply requires the `production` environment and is not enabled merely by pushing code.

### Staging deployment

`deploy-staging.yml` builds an immutable image and deploys it to the staging Cloud Run service after CI succeeds and the staging deployment gate is enabled.

### Production deployment

`deploy-production.yml` is protected separately from staging. A push to `main` alone is insufficient to silently provision or deploy production while production remains disabled.

## Identity model

### GitHub Terraform identity

A dedicated service account is impersonated through Workload Identity Federation and is restricted to the repository `marcelo-m7/facodi-deploy`.

It receives only permissions required to manage the declared Terraform resources. The implementation prefers resource-scoped IAM bindings where Google Cloud supports them.

### GitHub application deployment identity

Application rollout uses a distinct deployment identity from the Terraform administrator identity. It needs only the permissions required to publish the image and update the target Cloud Run service, plus service-account use where required.

Separating infrastructure administration from application rollout prevents every normal release from carrying broad infrastructure privileges.

### Runtime identity

Each Cloud Run environment uses its own runtime service account.

The runtime identity receives only:

- Cloud SQL connection permission;
- access to the environment's required Secret Manager secrets;
- access to the environment's filestore bucket;
- Artifact Registry access only when required by the Cloud Run execution model.

Staging and production runtime identities are not shared.

## Runtime v1: Odoo on Cloud Run

The first runtime implementation is intentionally conservative.

```text
Cloud Run
└── Odoo 19 Community
    ├── workers = 0
    ├── max_cron_threads = 1
    ├── proxy_mode = true
    └── single HTTP listener
```

Production starts with:

```text
min instances = 1
max instances = 1
```

Staging may use `min instances = 0` to reduce cost during inactive periods, but staging acceptance tests for cron/background behavior are executed with instance-based CPU allocation or an equivalent configuration that keeps CPU available while the Odoo process is expected to perform background work.

`workers = 0` avoids introducing a separate gevent listener and reverse-proxy routing requirement in v1. Horizontal scaling is intentionally deferred until Odoo cron, session, websocket and filestore behavior have been validated under the chosen Cloud Run model.

The container entrypoint maps Cloud Run's `PORT` environment variable to Odoo's HTTP port and builds the database connection arguments from environment/secret values.

## Database

Each environment uses Cloud SQL PostgreSQL 16 in the same Google Cloud region as its Cloud Run service.

Odoo connects through the Cloud Run / Cloud SQL integration using the instance connection name exposed at `/cloudsql/...` rather than a database port opened to the public internet.

Database credentials are supplied from Secret Manager at runtime.

The Terraform design enables automatic storage growth and configurable sizing. Production uses deletion protection. Staging may use a smaller instance class but remains structurally identical.

Database backup and retention settings are part of the environment Terraform configuration and are not delegated to the application deploy workflow.

## Filestore persistence

Odoo cannot rely on the ephemeral Cloud Run container filesystem for persistent attachments and website assets.

The v1 proposal mounts a dedicated Cloud Storage bucket into the container at the Odoo data/filestore path using Cloud Run's supported Cloud Storage volume mechanism.

This choice is explicitly a staging-gated compatibility decision because a Cloud Storage FUSE mount is not a fully POSIX-equivalent local filesystem.

Before production can be enabled, staging must demonstrate all of the following across a Cloud Run redeploy/revision replacement:

1. create an attachment in Odoo;
2. retrieve the attachment successfully;
3. upload/use an image through Website/eLearning;
4. restart or redeploy the Cloud Run service;
5. retrieve the same attachment and website image after the new revision becomes active;
6. install/update the FACODI addons and verify generated assets remain healthy;
7. verify concurrent normal application reads/writes do not produce filestore errors.

If these checks fail, the Cloud Storage mount is rejected for production and the runtime storage implementation must change before production activation. The repository-level deployment interface remains unchanged so that an alternate persistence implementation can be introduced without changing addon composition.

## Secrets

Secret values are never committed and never passed as Terraform variables containing plaintext credentials.

Terraform manages secret resources and access policy only.

At minimum, each environment has separate values for:

- PostgreSQL/Odoo database password;
- Odoo master/admin database-management password.

GitHub Actions does not need to read application secret payloads for ordinary deployment. Cloud Run resolves them through its runtime identity.

## Artifact Registry

The shared Artifact Registry repository stores FACODI Odoo images.

Canonical image format:

```text
<region>-docker.pkg.dev/<project>/facodi/odoo:<facodi-deploy-git-sha>
```

The build workflow pushes an image only after repository validation succeeds.

A deployment records the immutable URI being deployed so rollback can target a previous known-good image without rebuilding it.

## Runtime-neutral deployment interface

The stable application deployment contract is:

```bash
scripts/deploy-runtime.sh <environment> <image-uri>
```

Valid v1 environments are `staging` and `production`.

The script is responsible for dispatching to the configured runtime implementation. In v1, the implementation updates only the image of the corresponding Cloud Run service and then invokes runtime verification.

The workflow files do not embed a long sequence of Cloud Run-specific commands. This is the boundary that allows a future Compute Engine, GKE or other runtime implementation to be introduced without redesigning the repository's release model.

## Staging and production policy

Staging is the first executable environment.

Production remains disabled until all of these conditions are met:

- Terraform staging plan/apply has completed successfully;
- CI passes;
- Cloud Run starts Odoo successfully;
- Cloud SQL connectivity is verified;
- both pinned FACODI addons are visible/installable;
- filestore persistence checks pass across redeploy;
- a rollback to a previous image has been exercised in staging;
- production secrets have been populated explicitly;
- production infrastructure/deployment gates are enabled explicitly.

The staging and production domains are configuration outputs/operational steps. DNS changes are not automatically performed by the initial Terraform apply; authoritative DNS automation requires a separate explicit design decision.

## Validation contract

`scripts/validate-repository.sh` validates static repository invariants.

`scripts/verify-runtime.sh <environment>` validates the live target after deployment without mutating business data beyond dedicated health/verification operations.

The runtime verification must confirm at least:

- Cloud Run service exists and has a ready revision;
- deployed revision references the expected immutable image;
- service responds to an Odoo HTTP health endpoint;
- Cloud SQL attachment/configuration exists;
- expected runtime service account is attached;
- expected persistent volume configuration is present;
- the deployed service is not scaled beyond the v1 maximum instance policy.

Filestore persistence is a separate explicit staging acceptance test because it requires writing and re-reading Odoo-managed content across revisions.

## Rollback

Application rollback does not run Terraform.

A rollback redeploys a previously published immutable Artifact Registry image to the same Cloud Run service through the runtime deployment adapter.

Infrastructure rollback is handled separately through Terraform review and apply. Database schema/data rollback is not implied by an application image rollback; Odoo module migrations must therefore remain backward-risk-aware and be validated before production updates.

## Security constraints

- no Google service-account JSON keys;
- no repository-stored passwords;
- no public PostgreSQL port required for application operation;
- no SSH-based application deployment;
- separate infrastructure and application deployment identities;
- separate staging and production runtime identities;
- secret values excluded from Terraform state;
- production apply/deploy protected separately from staging;
- Cloud SQL production deletion protection enabled;
- immutable image SHAs used for release and rollback;
- least-privilege IAM preferred over project-wide Editor/Owner roles for automation identities.

## Out of scope for v1

The following are intentionally deferred:

- GKE;
- Compute Engine runtime implementation;
- horizontal Odoo scaling above one Cloud Run instance;
- multiprocessing Odoo workers and separate gevent routing;
- Redis/session clustering;
- automatic DNS cutover;
- automatic data migration from an existing Odoo database;
- a custom Odoo object-storage addon;
- multi-region disaster recovery;
- production activation before staging acceptance criteria pass.

## Success criteria

The proposal is ready for implementation when this design is approved.

The implementation is complete when:

1. `facodi-learning` and `facodi-theme` are pinned as submodules;
2. CI validates the repository and builds the Odoo image without cloud credentials;
3. Terraform bootstrap establishes remote state and WIF without long-lived keys;
4. Terraform can plan and provision the isolated staging runtime;
5. GitHub Actions can publish an immutable image to Artifact Registry through WIF;
6. application deployment can update the staging Cloud Run image without a Terraform apply;
7. Odoo starts against Cloud SQL PostgreSQL 16;
8. staging proves filestore persistence across a revision replacement;
9. runtime verification and image rollback are documented and executable;
10. production remains gated until explicitly enabled.

## Decision summary

The approved architectural direction is **runtime-neutral deployment design + Terraform infrastructure + Google Cloud Run/Cloud SQL as the first runtime implementation**.

Terraform defines where FACODI runs. GitHub Actions defines which immutable FACODI image is running. The addon repositories define what FACODI does.
