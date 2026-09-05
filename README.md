# FACODI Deploy

`facodi-deploy` is the canonical deployment-composition repository for the FACODI Odoo 19 Community runtime serving `facodi.com` through the existing Coolify resource.

The repository does not own FACODI business logic. It pins independent addon repositories, builds one reproducible Odoo image, defines the canonical Coolify Compose lifecycle, and provides the migration and acceptance tests that must pass before a revision is deployed.

## Canonical runtime

The only active runtime architecture in this repository is:

```text
Coolify
  |
  +--> db       PostgreSQL 16
  |      |
  |      +--> postgres-data
  |
  +--> migrate  one-shot, fail-closed migration gate
  |      |
  |      +--> odoo-data
  |
  +--> odoo     persistent Odoo 19 Community service
         |
         +--> odoo-data
         +--> facodi.com
```

The canonical Compose file is:

```text
deploy/coolify/docker-compose.yml
```

The `odoo` service starts only after PostgreSQL is healthy and the one-shot `migrate` service exits successfully. A failed migration therefore blocks the long-running application from starting.

The existing Coolify resource and its project-scoped named volumes must be preserved. Do not recreate the resource merely to deploy a new revision, and do not introduce explicit Compose `name:` overrides for these volumes:

- `postgres-data` — PostgreSQL data;
- `odoo-data` — Odoo filestore and persistent application data.

## Source composition

A `facodi-deploy` commit pins the exact source revisions baked into its Odoo image:

| Source | Runtime modules | Pinned revision |
| --- | --- | --- |
| `marcelo-m7/facodi-learning` | `facodi_learning` | `c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18` |
| `marcelo-m7/facodi-theme` | `theme_facodi` | `639405d3473203b85f174af53198cbc05658fae0` |
| `marcelo-m7/monynha-odoo` | `theme_monynha`, `monynha_lead_generator` | `e2f26bf6e9d4d232b5cb56f4ff1e2a05626bf425` |
| `odoo/design-themes` | only `theme_common` | `a1818df4ade65406c0cacae8b1ea676e6f70095f` |

The Monynha modules are available in the shared image but are intentionally not included in `FACODI_MODULES`; the FACODI migration gate does not install them into the FACODI database automatically. The pinned Monynha revision is the merged M3 Theme Completion release state, so the image contains the completed Odoo-native branded theme while preserving this installation boundary.

## Migration lifecycle

The runtime image exposes two entrypoint modes:

```text
serve    -> long-running Odoo HTTP process
migrate  -> one-shot database/module/theme/language migration
```

For a fresh database, the migration initializes Odoo and the FACODI modules without demo data. For an existing database it performs a guarded preflight before updating `facodi_learning` and `theme_facodi`. The known historical `website_facodi` presentation-only transition is accepted only when its ownership shape is unambiguous; otherwise migration fails closed.

After module operations, standard Odoo mechanisms are used to:

- activate English, Portuguese (Portugal), Spanish and French;
- keep English (`en_US`) as the Website default;
- expose `pt_PT`, `es_ES` and `fr_FR` on the Website;
- load theme translations;
- apply `theme_facodi` through the Odoo theme API.

The migration does not rewrite arbitrary Website pages, courses, contacts or Website Builder content directly.

## Coolify environment contract

The canonical Compose deployment keeps the existing Coolify-generated PostgreSQL secret contract:

```text
$SERVICE_PASSWORD_64_POSTGRES
```

The migration does not introduce a new mandatory production secret. `DB_HOST`, `DB_PORT`, `DB_USER`, `ODOO_DB`, `FACODI_MODULES` and the generated Odoo configuration are wired by the Compose/entrypoint layer.

## Validation

Initialize all pinned sources first:

```bash
git submodule update --init --recursive
```

Run the fast repository contract and Compose validation:

```bash
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
```

Run the disposable end-to-end runtime acceptance test:

```bash
bash tests/test_coolify_runtime.sh
```

That test builds the canonical image, creates disposable volumes, runs migration twice to prove idempotency, starts Odoo, verifies Website language state, and requires successful HTTP responses from the FACODI Website/eLearning routes.

GitHub Actions runs the same canonical Coolify acceptance path on pull requests and on `main`.

## Deployment and rollback boundary

Operational deployment must update the existing Coolify resource instead of replacing it, so `postgres-data` and `odoo-data` remain attached.

Release `v0.1.0` is the preserved source snapshot from before the Coolify-canonical refactor. It is a source/history rollback boundary, not a promise that a newer database can be downgraded without restoring persistence.

If a deployed migration must be rolled back, restore the matching PostgreSQL backup and `odoo-data` backup together, then deploy the known-good source revision. See [`docs/operations.md`](docs/operations.md) for the production procedure.

## Security and operational invariants

- no plaintext production secrets are committed;
- PostgreSQL and Odoo ports are not published directly to the host by this Compose file;
- migration failure prevents `odoo` startup;
- deploys must not run `docker compose down -v` against the production resource;
- persistent volume names and the existing Coolify resource identity must be preserved;
- language handling remains standard Odoo Website behavior;
- exact source pins are part of the repository contract.
