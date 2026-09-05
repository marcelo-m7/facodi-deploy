# FACODI Deploy — Canonical Coolify Runtime Design

Date: 2026-09-05
Status: proposed for implementation
Repository: `marcelo-m7/facodi-deploy`
Target: existing Coolify application serving `facodi.com`

## 1. Context

`facodi-deploy` currently mixes two deployment architectures:

- an active Coolify Docker Compose definition under `deploy/coolify/docker-compose.yml`;
- an older Google Cloud Run / Cloud SQL / Terraform delivery architecture spread across workflows, Terraform roots, scripts and operational documentation.

The production-like Coolify resource already has persistent PostgreSQL and Odoo filestore data. The migration must therefore be performed in place and must not recreate or rename the persistent state by accident.

Before this refactor, the exact repository state was archived as GitHub release `v0.1.0`, targeting commit `96d660537f0f7c47d8368bf20af915626cf809aa`.

## 2. Goals

1. Make Coolify the only canonical runtime architecture in `facodi-deploy`.
2. Keep the existing Coolify resource, domain routing and persistent data intact.
3. Align addon composition with the currently verified FACODI repositories.
4. Add an explicit, fail-closed, one-shot migration phase before the persistent Odoo service starts.
5. Configure the FACODI Website to support English, Portuguese (Portugal), Spanish and French, with English as the default language, using standard Odoo mechanisms.
6. Remove active Cloud Run / Cloud SQL / Terraform deployment paths so the repository has one clear operational model.
7. Validate the same Compose runtime in CI that Coolify will execute.

## 3. Non-goals

- Rewriting FACODI business logic in this repository.
- Replacing Odoo Website, `website_slides`, Portal or Odoo's native translation/theme lifecycle.
- Moving the current PostgreSQL database or filestore to another provider.
- Changing the public domain away from `facodi.com`.
- Introducing an external application proxy inside the repository; Coolify remains responsible for public HTTP/TLS routing.
- Rebuilding user content, `website_page` records, courses, contacts or uploaded filestore data.

## 4. Source composition

The deploy repository continues to compose independent addon repositories as Git submodules.

Required pins for this migration:

```text
addons/facodi-learning
  -> c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18
  -> Odoo module: facodi_learning

addons/facodi-theme
  -> be35673a5649f5e6f7b01777905d0899e3daaf7b
  -> Odoo module: theme_facodi

vendor/odoo-design-themes
  -> a1818df4ade65406c0cacae8b1ea676e6f70095f
  -> runtime module copied: theme_common only
```

`odoo/design-themes` is added as a third pinned submodule solely to provide the verified `theme_common` dependency. The Docker image must not expose all upstream themes.

## 5. Canonical runtime topology

```text
GitHub: marcelo-m7/facodi-deploy
        |
        | Coolify tracks main
        v
Coolify build from deploy/coolify/docker-compose.yml
        |
        +--------------------+
        |                    |
        v                    v
PostgreSQL 16             migrate
service: db               one-shot Odoo service
volume: postgres-data       |
                            | successful exit required
                            v
                          odoo
                          persistent service
                          volume: odoo-data
                          expose: 8069
                            |
                            v
                     Coolify proxy/TLS
                            |
                            v
                        facodi.com
```

The Compose service names `db` and `odoo` and the named volumes `postgres-data` and `odoo-data` are preserved. The new `migrate` service is additive.

## 6. Persistent-state contract

The existing Coolify deployment already owns data that must survive this refactor.

The implementation must therefore:

- keep `postgres-data` unchanged;
- keep `odoo-data` unchanged;
- keep the deployment inside the same existing Coolify resource;
- avoid adding explicit Compose `name:` values to those volumes during this migration, because changing from Coolify's current project-scoped names could attach different empty volumes;
- mount `odoo-data` into both `migrate` and `odoo`, because module/theme updates can affect filestore-backed assets;
- never run `docker compose down -v`, volume pruning or database recreation as part of normal deployment.

Before the first deployment of this architecture, PostgreSQL and `odoo-data` must be backed up as one rollback unit.

## 7. Image composition

The Docker image remains based on `odoo:19.0`.

It will:

1. copy the two FACODI addon repositories into a build-only source directory;
2. copy only `vendor/odoo-design-themes/theme_common/` from the official design-themes pin;
3. discover and place `facodi_learning`, `theme_facodi` and `theme_common` in `/mnt/extra-addons`;
4. include the runtime/migration helpers required by the Compose services;
5. run persistent Odoo as the `odoo` user;
6. keep `admin_passwd` in a generated private Odoo config rather than passing it as a CLI option.

No `git pull`, submodule update or other source mutation occurs inside a running container.

## 8. Environment compatibility

The first migration must continue to accept the environment variables already supplied by the current Coolify Compose definition:

```text
SERVICE_PASSWORD_64_POSTGRES
DB_HOST=db
DB_PORT=5432
DB_USER=odoo
DB_PASSWORD=$SERVICE_PASSWORD_64_POSTGRES
ODOO_DB=facodi
ODOO_ADMIN_PASSWD=$SERVICE_PASSWORD_64_POSTGRES
FACODI_MODULES=facodi_learning,theme_facodi
PORT=8069
```

Separating the Odoo master password from the PostgreSQL password can be done later as a dedicated secret-rotation task. It is not required for this in-place migration because introducing a new mandatory secret would make the existing Coolify resource fail before operators can stage the change.

## 9. One-shot migration service

A new Compose service named `migrate` uses the same built image, database environment and `odoo-data` volume as the persistent Odoo service.

Runtime ordering:

```text
db healthy
   -> migrate starts
      -> migrate exits 0
         -> odoo starts
```

`odoo` declares `depends_on` with `migrate: condition: service_completed_successfully`. A non-zero migration exit prevents the persistent service from starting on an incompletely migrated database.

The migration service has `restart: "no"` and is expected to be recreated by each Coolify deployment together with the new application revision.

## 10. Migration behavior

Migration logic is idempotent and fail-closed.

### 10.1 Database readiness

Wait for PostgreSQL using the official Odoo image tooling / PostgreSQL client environment. Failure to connect within the configured timeout aborts migration.

### 10.2 Fresh database

If the Odoo registry tables do not exist, initialize the database with the required FACODI modules and no demo data.

### 10.3 Existing database

If the Odoo registry already exists:

1. inspect the module registry before mutation;
2. reconcile only the known `website_facodi -> theme_facodi` legacy transition when that legacy module is actually present;
3. abort if both old and new module records or unexpected legacy XML-ID ownership create ambiguity;
4. update `facodi_learning` and `theme_facodi` through normal Odoo module update mechanisms;
5. load the shipped Odoo translations;
6. configure the website languages through standard Odoo models/APIs;
7. apply/reapply `theme_facodi` through the standard Website theme lifecycle.

Migration must not directly rewrite `website_page`, courses, contacts or arbitrary Website Builder content.

## 11. Website languages

The resulting FACODI Website must have these languages active/published:

```text
English             default
Português (Portugal) pt_PT
Español              es_ES
Français             fr_FR
```

The implementation uses Odoo's standard language activation and Website configuration. It must not introduce custom language routes, per-language QWeb branching or a JavaScript translation store.

English remains the canonical source language of `theme_facodi`. Portuguese, Spanish and French are supplied by the module's native `.po` catalogs.

After translations are loaded, `theme_facodi` is selected/reapplied through Odoo's standard theme API so website-specific copied views receive the translated theme content.

## 12. Coolify Compose contract

The canonical Compose file remains at:

```text
deploy/coolify/docker-compose.yml
```

This avoids requiring a path change in the existing Coolify resource during the data-sensitive migration.

Required services:

- `db` — PostgreSQL 16 with the existing persistent volume;
- `migrate` — one-shot database/module/theme/language migration;
- `odoo` — long-running Odoo 19 service with existing filestore volume.

The Odoo service only exposes port `8069` to the Compose network. Coolify owns public routing and TLS for `facodi.com`; the Compose file does not publish PostgreSQL or Odoo directly on host ports.

The existing `/web/login` HTTP health check remains the runtime readiness signal unless CI proves a stricter standard Odoo endpoint is more reliable.

## 13. Removal of the obsolete Google runtime

Because release `v0.1.0` preserves the previous architecture, the active branch removes the obsolete deployment implementation rather than keeping two competing operational paths.

Remove from the active repository:

- Cloud Run / Cloud SQL deployment workflows;
- Terraform plan/apply workflows;
- Google Artifact Registry image workflow when it exists only for the retired Cloud Run flow;
- `infrastructure/terraform/**`;
- Cloud Run-specific deployment and database configuration scripts;
- Cloud Run-specific runtime verification scripts;
- operational documentation that instructs operators to deploy FACODI through Cloud Run/Cloud SQL.

Historical Cloud Run design/plan documents may also be removed from the active tree because the tagged `v0.1.0` release preserves them exactly. The new documentation links to that release as the historical rollback/reference boundary.

## 14. CI design

CI must exercise the Coolify deployment shape rather than Terraform.

A pull request run performs:

1. recursive submodule checkout;
2. repository contract validation, including exact addon/upstream pins;
3. `docker compose config` for `deploy/coolify/docker-compose.yml` with CI-safe environment values;
4. immutable Odoo image build;
5. image-content inspection for `facodi_learning`, `theme_facodi` and `theme_common`, and absence of unrelated design themes;
6. PostgreSQL startup on disposable volumes;
7. one-shot `migrate` execution against a fresh database;
8. persistent `odoo` startup and health check;
9. assertions that English is the website default and `pt_PT`, `es_ES`, `fr_FR` are active;
10. a second migration execution to prove idempotency;
11. final HTTP smoke checks for `/`, `/pt`, `/es`, `/fr` and `/slides` where applicable.

CI must fail if Terraform/Cloud Run deployment entry points are accidentally reintroduced as active runtime dependencies.

## 15. Backup and rollback

`v0.1.0` is the source-code rollback point for the pre-refactor deployment.

It is not, by itself, a complete rollback after an Odoo module migration. Before first production deployment:

1. back up PostgreSQL;
2. back up the matching `odoo-data` volume;
3. record the current Coolify resource/environment configuration;
4. deploy the new revision;
5. validate database, filestore, website, courses and multilingual routes.

If migration must be reverted after database/module metadata changed, restore the matching PostgreSQL + filestore backup together with the `v0.1.0` application state.

## 16. Repository documentation after migration

`README.md` becomes Coolify-first and documents:

- exact addon pins;
- the canonical Compose file path;
- existing persistent-volume requirements;
- the `db -> migrate -> odoo` lifecycle;
- required Coolify environment variables;
- backup/rollback requirements;
- local/CI validation commands.

`docs/operations.md` becomes the runbook for `facodi.com`, covering first migration, routine deployment, health verification and rollback.

## 17. Acceptance criteria

The change is ready to merge only when all of the following are true:

- `v0.1.0` remains published against the pre-change SHA;
- `facodi-theme` is pinned to `be35673a5649f5e6f7b01777905d0899e3daaf7b`;
- `facodi-learning` remains pinned to `c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18`;
- `odoo/design-themes` is pinned to `a1818df4ade65406c0cacae8b1ea676e6f70095f` and only `theme_common` is copied;
- the canonical Coolify Compose file preserves `postgres-data` and `odoo-data`;
- migration failure prevents Odoo startup;
- a fresh CI database migrates and starts successfully;
- migration is idempotent on a second run;
- English is default and PT-PT/ES/FR are active through standard Odoo language mechanisms;
- `/`, `/pt`, `/es`, `/fr` and core eLearning routes pass smoke checks;
- active Cloud Run/Terraform deployment paths are removed;
- exact-head CI is green before merge.
