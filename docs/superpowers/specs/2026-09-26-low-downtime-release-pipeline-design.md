# FACODI Low-Downtime Release Pipeline Design

**Date:** 2026-09-26  
**Status:** Approved design, pending implementation plan

## 1. Intent

FACODI must stop treating every merge or repository change as a production rebuild that can make `facodi.com` unavailable. The release pipeline must minimize rebuilds, collapse rapid changes into the newest releasable state, preserve the existing fail-closed Odoo migration guarantees, and keep the currently healthy production revision serving traffic until a compatible replacement is ready.

Success means:

- documentation/test-only changes do not deploy production;
- one immutable application image is built per releasable revision;
- `migrate` and `odoo` execute the exact same image digest;
- compatible releases use a rolling/health-gated traffic switch;
- schema/data-incompatible Odoo migrations use an explicit controlled maintenance path;
- failed new revisions do not replace a healthy old revision;
- rollback of compatible releases does not require rebuilding an old image;
- rapid successive merges do not cause a deployment storm.

Zero downtime is a target for compatible releases, not a promise for database-incompatible migrations.

## 2. Current Problem

The canonical Coolify Compose currently declares the same repository `build:` for both the one-shot `migrate` service and the persistent `odoo` service. Coolify therefore owns source compilation as part of deployment. The persistent service is also gated on completion of `migrate`, and the runbook treats migration as mandatory for every routine redeploy.

This combines four distinct concerns:

1. source validation;
2. image construction;
3. Odoo module/database update;
4. runtime replacement.

As a result, changes that do not need all four operations can still incur the full lifecycle and its availability cost.

## 3. Architectural Decision

GitHub Actions becomes the image producer. Coolify becomes the production runtime/release orchestrator.

The canonical flow is:

```text
PR
 |
 +-- repository/contracts/tests
 +-- disposable Odoo migration/runtime acceptance
 +-- browser acceptance
 |
merge to main
 |
change classifier
 +-- NO_DEPLOY ----------------------------> stop
 +-- RUNTIME_ONLY ----+
 +-- MODULE_UPDATE ---+--> build once --> GHCR immutable image
 +-- MIGRATION_REQUIRED+                    |
                                             v
                                           Coolify
                                             |
                                  release-class-specific gate
                                             |
                                         readiness
                                             |
                                      traffic switch
```

Production images are immutable and identified by commit SHA and digest, for example:

```text
ghcr.io/marcelo-m7/facodi:sha-<git-sha>
```

A mutable convenience tag may exist, but production state and rollback must be traceable to an immutable SHA/digest.

## 4. Single-Image Invariant

The production Compose must stop declaring independent `build:` blocks for `migrate` and `odoo`.

Both services consume the same release image:

```yaml
migrate:
  image: ${FACODI_IMAGE}

odoo:
  image: ${FACODI_IMAGE}
```

The image includes the pinned FACODI addon sources and runtime dependencies. A migration can therefore never run source bytes different from the persistent server that follows it.

GitHub Actions should use Docker Buildx caching so unchanged base/runtime/dependency layers are reused rather than rebuilt from scratch.

## 5. Change Classification

Classification is deterministic from Git diff and repository contracts. AI must not decide whether a database change is safe.

Four classes are defined.

### 5.1 NO_DEPLOY

Examples:

- documentation;
- Superpowers specs/plans;
- README-only changes;
- tests that do not alter the production runtime;
- CI-only changes that do not change runtime inputs.

Behavior:

- run appropriate CI;
- do not build a production image;
- do not invoke Coolify;
- do not restart Odoo.

### 5.2 RUNTIME_ONLY

Changes that require a new image/runtime but no Odoo module update or schema/data operation.

Behavior:

- build and publish one immutable image;
- deploy through the compatible rolling path;
- require readiness before traffic switch.

### 5.3 MODULE_UPDATE

Changes to installed Odoo addons that require an Odoo module update but are not classified as a schema/data-incompatible migration.

Typical candidates include compatible Python behavior, QWeb/XML, SCSS/assets and theme changes.

Behavior:

- build one immutable image;
- update only the affected canonical addon set when safely derivable;
- perform a health/readiness-gated rollout;
- avoid updating unrelated modules merely because they are part of the canonical runtime.

Module update is deliberately distinct from database-incompatible migration.

### 5.4 MIGRATION_REQUIRED

Examples include:

- canonical module set additions/removals;
- manifest dependency changes with installation implications;
- model/field/schema changes;
- explicit migration scripts;
- `docker/migrate.py` behavior changes;
- guarded data transformations;
- changes whose compatibility cannot be proven by the deterministic classifier.

Behavior:

- require the migration release path;
- preserve fail-closed semantics;
- require backup/rollback preparation where production data can be changed;
- allow a controlled maintenance window if the old application cannot safely serve against the migrated database.

When uncertain, classification escalates to `MIGRATION_REQUIRED`.

## 6. Module Update Strategy

The current canonical `FACODI_MODULES` remains the authoritative installed module contract. It is not necessary to update every canonical module on every compatible release.

The release tooling should derive an affected update set from changed addon ownership where possible. The migration system retains the full canonical set for installation/invariant checks.

A theme-only release should therefore be able to update `theme_facodi` without unnecessarily updating `facodi_learning`, `facodi_ai`, `website_forum` and other unchanged modules.

The classifier must never infer that an explicit migration script or manifest-level installation change is a lightweight module update.

## 7. Rolling Deployment and Readiness

For compatible releases, the healthy previous Odoo revision continues serving traffic while the new revision starts.

```text
OLD healthy -> serving
NEW starting
NEW ready
traffic -> NEW
OLD drain/stop
```

The traffic switch must occur only after readiness succeeds.

The current `/web/login` health probe is insufficient as the sole readiness signal. A lightweight readiness surface should prove at least:

- Odoo process is serving;
- target PostgreSQL database is reachable;
- Odoo registry for the target database is loaded;
- FACODI Website runtime is available.

Readiness must not depend on Gemini, OpenAI, Supabase or another external AI/processing provider. Processing-plane degradation must not remove the public learning site from service.

Liveness and readiness should be treated separately where supported by the runtime/orchestrator.

## 8. Migration Release Path

A migration-required release follows:

```text
CI green
 -> immutable image published
 -> backup gate (when data/schema impact exists)
 -> migration preflight
 -> fail-closed migrate
 -> smoke validation
 -> start new Odoo
 -> readiness
 -> traffic switch
```

If the database operation is incompatible with the old application revision, the pipeline may enter a controlled maintenance window before mutating production data. The design does not attempt unsafe blue/green operation across incompatible database schemas.

Database and `odoo-data`/filestore remain a rollback pair whenever a migration can affect attachment/data consistency.

## 9. Deployment-Storm Control

Production release workflows use concurrency control. A newer not-yet-promoted main revision supersedes obsolete intermediate release work when safe.

Conceptually:

```yaml
concurrency:
  group: facodi-production
  cancel-in-progress: true
```

Cancellation must not interrupt a production database migration after it has entered a non-cancellable mutation phase. The workflow therefore needs an explicit boundary between cancellable build/preflight work and serialized production mutation/promotion.

Rapid source changes should converge on the newest releasable revision instead of causing multiple sequential rebuild/redeploy cycles.

## 10. Superproject as Release Manifest

`facodi-deploy` remains the production release manifest.

Changes in:

- `facodi-theme`;
- `facodi-learning`;
- `facodi-ai`;
- other pinned addon sources

do not independently constitute a FACODI production release. Their tested gitlinks are intentionally aggregated in `facodi-deploy`, allowing several owner-repository changes to ship in one image and one production deployment.

This is particularly important for iterative frontend work, where multiple visual corrections should not create multiple production outages.

## 11. Rollback

Every promoted release records enough metadata to identify:

- Git SHA;
- immutable image digest;
- previous production SHA/digest;
- deployment class;
- migration/update set;
- migration/promotion timestamp.

For compatible releases, a failed candidate must not replace the healthy old revision. A post-promotion runtime regression can roll back to the previously published immutable image without rebuilding it.

For an incompatible migration, source/image rollback alone is not sufficient. Restore the matching pre-migration PostgreSQL and `odoo-data` backup pair before running the previous image.

## 12. CI and Production Gates

PR CI remains comprehensive and disposable:

- recursive submodule checkout;
- repository contracts;
- migration unit tests;
- Compose validation;
- fresh database migration;
- immediate idempotent migration;
- Odoo runtime health;
- Website/eLearning HTTP checks;
- authenticated backend/browser acceptance where applicable.

Production release is a separate concern. Passing CI does not imply that every merge needs deployment.

The release classifier controls whether an image is built and whether Coolify is invoked.

## 13. Expected Behavior Matrix

| Change | Image | Odoo update | Production deployment |
|---|---:|---:|---|
| docs/README/spec only | No | No | No |
| test-only | No | No | No |
| compatible runtime change | Yes | No | rolling |
| theme/QWeb/SCSS requiring addon update | Yes | affected modules only | rolling/health-gated |
| compatible addon Python change | Yes | affected modules only | rolling/health-gated |
| new canonical Odoo module | Yes | migration gate | controlled |
| model/schema/data migration | Yes | migration gate | controlled |
| several rapid merges | newest relevant release | classified once per promoted revision | obsolete pre-promotion work cancelled |

## 14. Safety Invariants

The implementation must preserve all of these:

1. Production PostgreSQL and filestore volumes are never recreated as part of ordinary deployment.
2. A candidate revision never receives production traffic before readiness succeeds.
3. Migration failure never gets bypassed by manually starting the candidate Odoo service.
4. Migration and Odoo server use the same immutable image digest.
5. Unknown migration compatibility escalates rather than being treated as rolling-safe.
6. External AI/provider availability is not part of Website readiness.
7. A documentation/test-only merge cannot restart production.
8. Cancellation cannot terminate an in-progress non-reversible production mutation.
9. Rollback metadata identifies the exact previous image; no rebuild is required for compatible rollback.
10. Database-incompatible rollback restores PostgreSQL and filestore consistently.

## 15. Implementation Boundaries

Likely implementation surfaces in `facodi-deploy` include:

- production/release GitHub Actions workflows;
- deterministic change-classification script and tests;
- Docker Buildx/GHCR publishing;
- production Compose switching from `build:` to immutable `image:`;
- module-update versus migration invocation contract;
- readiness implementation and acceptance tests;
- Coolify release configuration/documentation;
- rollback/release metadata and operational runbook.

The implementation must be phased so the existing healthy Coolify deployment remains the rollback boundary until the image-based release path has passed disposable and preview validation.

## 16. Rollout Phases

### Phase A — classification and image pipeline
Add deterministic classification, tests, Buildx caching and immutable GHCR publishing without changing production runtime.

### Phase B — image-based preview
Make preview/staging consume the immutable image and prove migrate/server image identity, readiness and rollback behavior.

### Phase C — production image consumption
Switch production Compose from source `build:` to `image:` only after Phase B is green. Preserve existing volumes and resource identity.

### Phase D — rolling compatible releases
Enable health-gated traffic replacement for `RUNTIME_ONLY` and `MODULE_UPDATE` classes.

### Phase E — optimized migration/update paths
Use affected-module updates for compatible releases while retaining the conservative full migration gate for `MIGRATION_REQUIRED`.

### Phase F — operational hardening
Verify cancellation boundaries, release metadata, rollback drills, backup procedure and deployment-storm behavior.

## 17. Non-Goals

This design does not:

- replace Coolify;
- move the production database out of the current persistence model;
- introduce Kubernetes;
- promise zero downtime across incompatible Odoo database migrations;
- make AI responsible for release safety decisions;
- bypass Odoo's standard module APIs;
- make owner repositories independently deploy production.

