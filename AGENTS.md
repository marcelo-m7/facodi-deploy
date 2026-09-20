# FACODI Deploy Agent Guide

## Scope and ownership

- This repository is the canonical deployment composition for the FACODI Odoo 19 Community instance at `facodi.com`.
- It owns the Docker image, Coolify Compose lifecycle, migration gate, source pins and deployment contracts. Business logic belongs in the addon submodules.
- Before editing an addon, identify its owning repository. Changes under `addons/facodi-ai`, `addons/facodi-learning`, `addons/facodi-theme`, `addons/monodoo` or `addons/monynha-odoo` must be made in that repository, then consumed here by updating the submodule gitlink.
- Initialize source pins before validation with `git submodule update --init --recursive`. Do not replace a gitlink with copied addon code or mutable branch contents.

## Runtime invariants

- `deploy/coolify/docker-compose.yml` is the only active production runtime definition: PostgreSQL 16 -> one-shot `migrate` -> persistent `odoo`.
- The existing Coolify resource and the named volumes `postgres-data` and `odoo-data` are persistent production state. Never rename, delete, recreate or detach them to deploy a revision.
- The `migrate` service is a fail-closed gate. A failed migration must keep `odoo` stopped; do not bypass it or manually start Odoo against a partially migrated database.
- Keep PostgreSQL and Odoo unpublished to host ports in the production Compose file. Do not add a Compose `name:` override.
- The migration must remain idempotent and use standard Odoo APIs. Preserve its guarded `website_facodi` -> `theme_facodi` transition and do not add arbitrary rewrites of Website pages, courses, contacts or Website Builder content.
- Monynha modules may be available in the image but are not part of the automatic FACODI installation set unless a separately reviewed change updates that contract.

## Secrets and live instance work

- Never print, commit, paste into chat, or add real values from `.env`. It is ignored local state; use `.env.ci` for disposable tests and Coolify-generated `SERVICE_PASSWORD_64_POSTGRES` / `SERVICE_PASSWORD_64_ODOO_ADMIN` in production.
- For explicit live Odoo API work, load the local `.env` securely, confirm the target is `https://facodi.com` and the `facodi` database, and prefer standard Odoo models and reversible, narrowly scoped changes.
- Do not assume a live API credential exists merely because the variable is declared. Report authentication or availability blockers without weakening repository security.
- Database and `odoo-data` backups are a matched pair for migrations and rollback. Never use `docker compose down -v` against production persistence.

## Validation

Run the narrowest relevant check after an edit, then the full gate when runtime or integration behavior is affected:

```bash
git submodule update --init --recursive
bash scripts/validate-repository.sh
docker compose --env-file .env.ci -f deploy/coolify/docker-compose.yml config --quiet
python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash tests/test_coolify_runtime.sh
```

- `scripts/validate-repository.sh` covers manifests, exact gitlinks, shell syntax and entrypoint tests.
- `tests/test_coolify_runtime.sh` is the disposable end-to-end check: fresh migration, idempotent migration, Odoo health, Website languages, Monodoo runtime and browser acceptance.
- Do not copy the test-only host port publication from `tests/docker-compose.ci.yml` into production.

## Documentation and change discipline

- Read [`README.md`](README.md) for architecture and source composition, [`docs/operations.md`](docs/operations.md) for deployment/backup/rollback procedure, and [`docker/migrate.py`](docker/migrate.py) before changing migration behavior.
- Keep changes small and preserve the existing public module and environment contracts. Update tests or documentation when a contract changes.
- Do not commit generated local state, credentials, runtime logs or unrelated submodule changes.