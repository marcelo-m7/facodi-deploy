# FACODI Low-Downtime Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace rebuild-on-every-deploy behavior with deterministic release classification, one immutable GHCR image per releasable revision, and health-gated Coolify promotion while preserving fail-closed Odoo migrations.

**Architecture:** GitHub Actions validates and classifies changes, builds one immutable image only when runtime inputs changed, and publishes it to GHCR. Coolify consumes that exact image for both migration and serving; compatible releases use readiness-gated replacement while migration-required releases retain a serialized fail-closed path.

**Tech Stack:** GitHub Actions, Docker Buildx, GHCR, Docker Compose, Coolify, Bash, Python 3, Odoo 19 Community, PostgreSQL 16.

**Spec:** `docs/superpowers/specs/2026-09-26-low-downtime-release-pipeline-design.md`

## Global Constraints

- Production PostgreSQL and `odoo-data` volumes must never be recreated by ordinary deployment.
- Migration and persistent Odoo must execute the same immutable image digest.
- Unknown compatibility escalates to `MIGRATION_REQUIRED`.
- External AI/Supabase availability must not determine Website readiness.
- Documentation/test-only changes must not restart production.
- Cancellation must never interrupt a non-reversible production mutation.
- Existing healthy Coolify production remains the rollback boundary until the image-based preview path is proven.
- Database-incompatible rollback restores PostgreSQL and filestore as a pair.

## Review Focus

- A diff containing both harmless and migration-sensitive paths must resolve to the highest-risk class, never the first matching class.
- Git submodule pointer changes must be classified by owning addon and must not silently become `NO_DEPLOY`.
- A newer workflow may cancel build/preflight work but must not cancel an entered production mutation/promotion critical section.
- Missing/invalid `FACODI_IMAGE` or digest must fail before migration/server startup rather than falling back to a local build.
- Readiness must fail for inaccessible DB/unloaded registry but remain healthy when optional AI providers are unavailable.

---

### Task 1: Deterministic Release Classifier

**Files:**
- Create: `scripts/classify-release.py`
- Create: `tests/test_release_classifier.py`
- Modify: `scripts/validate-repository.sh`

**Interfaces:**
- Consumes: newline-separated changed paths from git diff or repeated CLI path arguments.
- Produces: machine-readable `release_class` in `NO_DEPLOY|RUNTIME_ONLY|MODULE_UPDATE|MIGRATION_REQUIRED` and an affected Odoo module list for `MODULE_UPDATE`.

- [ ] **Step 1: Write failing classifier tests**

Cover: docs/tests-only → `NO_DEPLOY`; Docker runtime → `RUNTIME_ONLY`; theme addon source/gitlink → `MODULE_UPDATE` with `theme_facodi`; manifest/migration/canonical module-set/migrate.py changes → `MIGRATION_REQUIRED`; mixed paths choose highest risk; unknown runtime-relevant addon paths escalate conservatively; submodule pointers cannot be ignored.

- [ ] **Step 2: Run tests and verify failure**

Run: `python3 -m unittest tests/test_release_classifier.py -v`  
Expected: FAIL because classifier does not exist.

- [ ] **Step 3: Implement classifier CLI**

Implement focused pure functions `classify_path(path: str) -> Classification` and `classify_paths(paths: list[str]) -> ReleaseDecision`; CLI emits JSON and optional GitHub-output key/value lines. Risk precedence is `NO_DEPLOY < RUNTIME_ONLY < MODULE_UPDATE < MIGRATION_REQUIRED`.

- [ ] **Step 4: Run classifier and repository contracts**

Run: `python3 -m unittest tests/test_release_classifier.py -v && bash scripts/validate-repository.sh`  
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -am "feat: classify FACODI release impact"`

### Task 2: Build One Immutable GHCR Image

**Files:**
- Create: `.github/workflows/release.yml`
- Modify: `docker/Dockerfile`
- Modify: `tests/test_repository_contract.py`

**Interfaces:**
- Consumes: Task 1 release decision and exact `github.sha`.
- Produces: `ghcr.io/marcelo-m7/facodi:sha-<sha>`, immutable digest, and release metadata; `NO_DEPLOY` produces no image.

- [ ] **Step 1: Add failing repository/workflow contract tests**

Assert release workflow uses classifier, skips image build for `NO_DEPLOY`, uses Buildx cache, authenticates to GHCR with package write permission, tags by exact SHA, and exports image digest.

- [ ] **Step 2: Run contract tests and verify failure**

Run: `python3 -m unittest tests/test_repository_contract.py -v`  
Expected: FAIL on missing release workflow/contracts.

- [ ] **Step 3: Implement build/publish workflow**

Keep PR CI unchanged. On eligible `main` revisions, classify first; build once with recursive submodules and Buildx cache; publish SHA tag; record digest. Do not deploy yet.

- [ ] **Step 4: Validate workflow/repository contracts**

Run: `bash scripts/validate-repository.sh`  
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -am "feat: publish immutable FACODI release images"`

### Task 3: Image-Based Compose Contract

**Files:**
- Modify: `deploy/coolify/docker-compose.yml`
- Modify: `tests/test_repository_contract.py`
- Modify: `tests/test_coolify_runtime.sh`
- Modify: `.env.ci` if required for disposable image selection.

**Interfaces:**
- Consumes: mandatory `FACODI_IMAGE` reference produced by Task 2.
- Produces: `migrate` and `odoo` services consuming exactly the same image reference with no production `build:`.

- [ ] **Step 1: Write failing Compose contract tests**

Assert both services use `${FACODI_IMAGE}`, neither declares `build:`, and missing image configuration fails Compose/preflight rather than building source.

- [ ] **Step 2: Verify tests fail against current Compose**

Run repository contract and `docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet`.  
Expected: contract FAIL because current services build locally.

- [ ] **Step 3: Switch Compose to mandatory immutable image input**

Preserve DB service, named volumes, environment, dependencies and migration fail-closed ordering. Adapt disposable CI runtime to explicitly build/tag a local test image before invoking the production-shape Compose.

- [ ] **Step 4: Prove disposable fresh + idempotent migration still works**

Run: `bash tests/test_coolify_runtime.sh`  
Expected: fresh migration PASS, second migration PASS, Odoo healthy, existing browser/HTTP acceptance PASS.

- [ ] **Step 5: Commit**

`git commit -am "refactor: consume one immutable FACODI image"`

### Task 4: Explicit Module-Update Versus Migration Modes

**Files:**
- Modify: `docker/migrate.py`
- Modify: `docker/entrypoint.sh`
- Modify: `tests/test_migration_contract.py`
- Modify: `tests/test_entrypoint.sh`

**Interfaces:**
- Consumes: `FACODI_RELEASE_CLASS` and optional validated `FACODI_UPDATE_MODULES`.
- Produces: no migration for `RUNTIME_ONLY`; affected-module update for `MODULE_UPDATE`; existing conservative full migration path for `MIGRATION_REQUIRED`.

- [ ] **Step 1: Write failing migration-mode tests**

Cover empty/unknown class rejection, affected module allow-list validation against canonical modules, theme-only update, mixed affected modules, and full conservative migration for `MIGRATION_REQUIRED`.

- [ ] **Step 2: Verify tests fail**

Run: `python3 -m unittest tests/test_migration_contract.py -v && bash tests/test_entrypoint.sh`  
Expected: FAIL on missing release-mode behavior.

- [ ] **Step 3: Implement minimal release-mode dispatch**

Keep existing migration internals authoritative for full migrations. Add a narrowly scoped compatible module-update entry path; never permit arbitrary module names from environment input.

- [ ] **Step 4: Run migration/entrypoint and full repository contracts**

Run: `bash scripts/validate-repository.sh`  
Expected: PASS.

- [ ] **Step 5: Commit**

`git commit -am "feat: separate module updates from migrations"`

### Task 5: FACODI Readiness Surface

**Files:**
- Create or modify in the smallest existing FACODI-owned addon appropriate for runtime health: readiness controller file and addon init import.
- Modify: `deploy/coolify/docker-compose.yml`
- Modify: `tests/test_coolify_runtime.sh`
- Add focused addon/controller tests where the owning repository contract supports them.

**Interfaces:**
- Produces: unauthenticated lightweight `/health/ready` returning success only when Odoo, target DB registry and FACODI Website runtime are ready.
- Must not call external AI/Supabase providers.

- [ ] **Step 1: Add failing readiness acceptance tests**

Assert 2xx when DB/registry/Website are available; prove optional AI environment/provider failure is irrelevant; healthcheck points to readiness rather than `/web/login`.

- [ ] **Step 2: Verify failure**

Run disposable runtime acceptance.  
Expected: FAIL because readiness endpoint does not exist.

- [ ] **Step 3: Implement minimal readiness endpoint and Compose probe**

No external network calls; no write operations; bounded execution time.

- [ ] **Step 4: Run disposable runtime/browser acceptance**

Run: `bash tests/test_coolify_runtime.sh`  
Expected: PASS including readiness.

- [ ] **Step 5: Commit owner addon pin plus deploy integration**

Commit addon implementation in its owning repository first, then update the tested gitlink in `facodi-deploy` with a separate integration commit.

### Task 6: Preview Promotion and Rollback Proof

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `scripts/release-metadata.py`
- Create: `tests/test_release_metadata.py`
- Modify: `docs/operations.md`

**Interfaces:**
- Consumes: immutable image SHA/digest, release class, affected modules and previous release metadata.
- Produces: release record containing SHA, digest, previous SHA/digest, class, update set and timestamp; preview deployment/promotion gate.

- [ ] **Step 1: Write failing metadata and workflow tests**

Assert exact digest is persisted, previous release is retained, malformed/missing digest fails closed, and rollback selects previous digest without rebuild.

- [ ] **Step 2: Verify tests fail**

Run: `python3 -m unittest tests/test_release_metadata.py -v`.  
Expected: FAIL because metadata utility does not exist.

- [ ] **Step 3: Implement release metadata and preview-only promotion**

Production remains untouched. Deploy immutable image to preview, run migration/update mode, readiness and smoke acceptance, then exercise rollback to previous preview image.

- [ ] **Step 4: Verify preview evidence**

Require exact-head CI plus successful preview readiness, image identity and rollback drill. Record evidence in PR/release logs; do not switch production yet.

- [ ] **Step 5: Commit**

`git commit -am "feat: add preview release promotion metadata"`

### Task 7: Production Promotion with Safe Concurrency Boundary

**Files:**
- Modify: `.github/workflows/release.yml`
- Create: `.github/workflows/promote-production.yml` if separating cancellable build from serialized mutation yields clearer boundaries.
- Modify: `tests/test_repository_contract.py`
- Modify: `docs/operations.md`

**Interfaces:**
- Consumes: preview-proven immutable image/digest and release metadata.
- Produces: serialized production promotion; cancellable work ends before mutation starts.

- [ ] **Step 1: Add failing workflow safety tests**

Assert build/preflight concurrency may cancel obsolete work; production mutation/promotion uses a non-cancellable serialized environment/job; `NO_DEPLOY` cannot reach promotion; migration-required path cannot bypass backup/migration gate.

- [ ] **Step 2: Verify contract failure**

Run: `python3 -m unittest tests/test_repository_contract.py -v`.  
Expected: FAIL until safe promotion workflow exists.

- [ ] **Step 3: Implement production promotion workflow**

Use Coolify's supported deployment mechanism/configuration for immutable images. Compatible classes perform readiness-gated replacement; migration-required class enters the explicit serialized migration path.

- [ ] **Step 4: Validate exact-head CI and perform controlled first promotion**

Before first production switch, capture DB + filestore backups and current release metadata. Preserve current Coolify resource identity and named volumes. Promote only the already preview-proven digest.

- [ ] **Step 5: Verify production**

Verify `/`, language routes, `/slides`, `/forum`, `/odoo`, attachments/media, readiness and affected feature. Confirm previous image digest remains available for rollback.

- [ ] **Step 6: Commit operational evidence/runbook updates**

`git commit -am "feat: promote health-gated FACODI releases"`

### Task 8: Deployment-Storm and Rollback Hardening

**Files:**
- Modify: workflow contract tests and release workflows as needed.
- Modify: `docs/operations.md`
- Modify: `ARCHITECTURE.md`

**Interfaces:**
- Consumes: complete release pipeline from Tasks 1–7.
- Produces: documented/tested convergence on newest pre-promotion revision and verified rollback procedures.

- [ ] **Step 1: Add regression contracts for rapid revisions**

Model three successive releasable SHAs: obsolete build/preflight work may cancel, only newest eligible candidate promotes, entered migration mutation cannot be cancelled.

- [ ] **Step 2: Run all repository/unit contracts**

Run: `bash scripts/validate-repository.sh`.  
Expected: PASS.

- [ ] **Step 3: Run full disposable runtime acceptance**

Run: `bash tests/test_coolify_runtime.sh`.  
Expected: PASS.

- [ ] **Step 4: Execute rollback drill**

For a compatible preview/release, select previous immutable digest and verify restoration without image rebuild. For migration-required procedure, verify documented paired DB/filestore restore steps without destructively exercising production unless explicitly scheduled.

- [ ] **Step 5: Update architecture/runbook**

Document classification matrix, immutable-image invariant, promotion boundary, readiness semantics, maintenance-window criteria and rollback metadata.

- [ ] **Step 6: Commit**

`git commit -am "docs: finalize low-downtime release operations"`

## Final Verification Gate

Before merging the implementation branch:

- [ ] Exact PR head has green repository contracts.
- [ ] Exact PR head has green fresh + idempotent Odoo migration acceptance.
- [ ] Browser acceptance is green.
- [ ] Classifier tests cover mixed-risk and submodule-pointer changes.
- [ ] `NO_DEPLOY` demonstrably produces no production image/deployment.
- [ ] `migrate` and `odoo` demonstrably use the same image digest.
- [ ] Preview rollback works without rebuild.
- [ ] Production promotion cannot be cancelled during database mutation.
- [ ] Current production volumes/resource identity are preserved.
- [ ] First production image promotion has a captured rollback point.
