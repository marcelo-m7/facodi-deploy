# FACODI deployment operations

This runbook is the operator procedure for the canonical FACODI Odoo 19 Community deployment serving `facodi.com` through the existing Coolify resource.

The production invariant is simple: keep the existing Coolify resource, keep the project-scoped `postgres-data` and `odoo-data` volumes attached, let the one-shot migration gate succeed before Odoo starts, and verify the Website/eLearning runtime after every consequential deployment.

## 1. Canonical deployment shape

The active lifecycle is:

```text
db (PostgreSQL 16)
  ↓
migrate (one shot, fail closed)
  ↓
odoo (persistent HTTP service)
```

Canonical file:

```text
deploy/coolify/docker-compose.yml
```

Persistent volumes:

```text
postgres-data:/var/lib/postgresql/data
odoo-data:/var/lib/odoo
```

Do not rename these volumes, add explicit Compose `name:` overrides, delete them, or recreate the Coolify resource simply to deploy a revision.

The existing generated secret contract is `$SERVICE_PASSWORD_64_POSTGRES`. A normal deployment of this refactor must not introduce an additional mandatory secret.

## 2. Pre-deployment backup gate

Before the first deployment of this runtime design, and before later revisions that contain schema/data migrations:

1. Temporarily stop automatic redeploys for the FACODI Coolify resource while backups are taken.
2. Back up the PostgreSQL database from the existing `postgres-data` persistence.
3. Back up the matching `odoo-data` volume from the same application state.
4. Record the current Coolify resource identifier, domain configuration for `facodi.com`, environment variables and current source revision.
5. Confirm Coolify still points to `deploy/coolify/docker-compose.yml` in this repository.
6. Confirm no operator action will delete or recreate the existing project volumes.

Database and filestore backups are a pair. A rollback across an Odoo migration must restore them together.

## 3. Source and image preflight

The deployment commit must resolve all submodules recursively:

```bash
git submodule update --init --recursive
```

The repository contract pins the expected revisions for:

- `facodi-learning` / `facodi_learning`;
- `facodi-theme` / `theme_facodi`;
- `monynha-odoo` / `theme_monynha` and `monynha_lead_generator`;
- `odoo/design-themes`, exposing only `theme_common`.

Monynha modules are baked into the shared image but are not part of `FACODI_MODULES`; they must not be installed into the FACODI database by the canonical migration gate unless a future, separately reviewed change intentionally alters that contract.

Before deployment, require:

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
bash tests/test_coolify_runtime.sh
```

The disposable runtime test must prove that a fresh database migrates, an immediate second migration is idempotent, Odoo becomes healthy, the required Website languages are configured and the public FACODI routes respond successfully.

## 4. First Coolify deployment of the canonical runtime

Use this sequence for the first production adoption of the new Compose lifecycle:

1. In Coolify, stop automatic redeploy while the backup gate is completed.
2. Back up PostgreSQL from `postgres-data`.
3. Back up the matching `odoo-data` volume.
4. Record the current Coolify environment variables, `facodi.com` domain settings and resource identifier.
5. Confirm the Compose path remains `deploy/coolify/docker-compose.yml`.
6. Merge/deploy the validated revision **without deleting or recreating the Coolify resource**.
7. Observe the services in order: `db`, then one-shot `migrate`, then `odoo`.
8. Require the `migrate` service to exit successfully. If it fails, do not bypass the gate and do not manually start the new `odoo` service against the partially migrated database.
9. Require the `odoo` service health check for `/web/login` to become healthy.
10. Verify `facodi.com`, existing courses, Website pages, attachments and media before re-enabling unattended redeploy behavior.

The migration service intentionally blocks the persistent Odoo service on non-zero exit.

## 5. What the migration gate does

For a fresh target database the migration initializes Odoo and the FACODI modules without demo data.

For an existing database it first inspects the Odoo module registry. The historical `website_facodi` → `theme_facodi` presentation transition is performed only when the known legacy ownership shape is unambiguous. Unexpected XML IDs, dependent custom views or simultaneous legacy/current registry records cause a fail-closed exit rather than a guessed data rewrite.

After module operations the migration uses standard Odoo APIs to:

- update `facodi_learning` and `theme_facodi`;
- activate `en_US`, `pt_PT`, `es_ES` and `fr_FR`;
- make English the Website default;
- expose the four languages on the Website;
- load theme translations;
- apply `theme_facodi` through the native theme mechanism.

The migration does not directly rewrite arbitrary `website.page` content, course data, contacts or Website Builder records.

## 6. Post-deployment acceptance

After `odoo` is healthy, verify at minimum:

```text
/web/login
/
/pt/
/es/
/fr/
/slides
```

Then verify operational persistence using real existing content:

1. open multiple existing Website pages;
2. open existing eLearning courses and course content;
3. retrieve existing attachments and images;
4. upload or create a disposable attachment/media item if appropriate, then verify it resolves;
5. restart/redeploy the same validated revision through Coolify without removing volumes;
6. verify the same attachment/media still resolves;
7. inspect `db`, `migrate` and `odoo` logs for migration, filestore or permission errors.

Do not treat a healthy login route alone as proof that the migration preserved production content.

## 7. Routine redeploys

For ordinary application revisions:

1. review the addon and migration diff;
2. take PostgreSQL + `odoo-data` backups when schema/data changes are expected;
3. require the exact-head GitHub CI to pass;
4. deploy the revision through the existing Coolify resource;
5. let `migrate` run to completion;
6. require `odoo` to become healthy;
7. verify the public FACODI routes and the areas affected by the revision.

Do not manually skip `migrate` because a previous deployment succeeded. It is designed to be idempotent and is the runtime gate for each deployment.

## 8. Failure handling

### Migration fails before Odoo starts

Keep the application gated. Read the `migrate` logs and determine whether the failure is:

- source/module incompatibility;
- guarded legacy-state ambiguity;
- PostgreSQL/database availability;
- theme or translation API incompatibility;
- invalid runtime configuration.

Do not mutate production tables manually merely to force a green migration. Correct the code or, if necessary, restore the pre-deployment backup pair.

### Odoo fails after migration succeeds

Inspect the persistent service logs and health check. If the database migration is backward compatible, a known-good source revision may be redeployed. If compatibility is uncertain, use the full rollback procedure below instead of assuming image-only rollback is safe.

## 9. Rollback procedure

Release `v0.1.0` preserves the source tree from before the Coolify-canonical refactor and is the historical source rollback boundary.

It is **not** a database downgrade mechanism. If a newer deployment has run an incompatible module/data migration:

1. stop the affected Coolify application services;
2. restore the PostgreSQL backup captured before that deployment;
3. restore the matching `odoo-data` backup from the same point in time;
4. deploy the known-good source revision (including `v0.1.0` when that is the intended boundary);
5. start through the resource's valid lifecycle for that revision;
6. verify `/web/login`, `/`, language routes, `/slides`, courses, attachments and media before reopening normal deployment flow.

Never restore only the database or only `odoo-data` when rolling back across migrations that may have changed attachment/filestore references.

## 10. Commands that must not be used against production persistence

Do not use commands or deployment changes that remove the named volumes, including:

```text
docker compose down -v
```

Do not publish PostgreSQL or Odoo directly to host ports as part of this runtime. Coolify should continue routing the application service through its managed networking/domain layer.

## 11. Verification evidence before merge

A deployment refactor is ready for merge only when the exact PR head has green CI showing:

- recursive submodule checkout;
- repository contract success;
- canonical Coolify Compose validation;
- fresh migration success;
- immediate second migration success;
- healthy persistent Odoo startup;
- correct Website language state;
- successful FACODI Website/eLearning HTTP checks.

Any failure in that matrix keeps the PR in draft/review state until corrected.
