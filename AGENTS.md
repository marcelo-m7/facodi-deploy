# FACODI Deploy Agent Guide

## Scope and ownership

- This repository is the canonical deployment composition for the FACODI Odoo 19 Community instance at `facodi.com`.
- It owns the Docker image, Coolify Compose lifecycle, migration gate, source pins and deployment contracts. Business logic belongs in the addon submodules.
- Before editing an addon, identify its owning repository. Changes under `addons/facodi-ai`, `addons/facodi-learning` or `addons/facodi-theme` must be made in that repository, then consumed here by updating the submodule gitlink.
- Initialize source pins before validation with `git submodule update --init --recursive`. Do not replace a gitlink with copied addon code or mutable branch contents.

## Domain and implementation boundaries

- Keep standard Odoo eLearning authoritative: `slide.channel` is the sole course model and `slide.slide` is canonical course content. Do not introduce parallel course, learner-progress or prerequisite models.
- `facodi_learning` owns course discovery, analysis provenance, reviewed course/content mappings, curriculum references, curricular units, coverage and reusable curriculum modules. `theme_facodi` owns presentation only; do not move domain queries or editorial data into theme QWeb.
- A curriculum reference/unit is external evidence, not a FACODI degree, credit or enrolment record. Coverage types are `covers`, `partial`, `supports` and `equivalent`; `equivalent` never grants academic equivalence, ECTS, credits or transcript status.
- Public curriculum data must be explicit and reviewed: render only validated, Website-published references and approved coverage. Public helpers may `sudo()` only to locate editorial audit/module data, then must re-read `slide.channel` and `slide.slide` as the caller and filter standard publication, visibility and website boundaries.
- Reusable learning composition is `reference -> unit -> module assignment -> module item -> one course or one slide`. Do not create a competing pathway model. Existing live mapping for UAlg LESTI UC `19411018` (Probabilidades e Estatística) uses approved evidence and existing course/content records only; do not invent content to close gaps.
- A module item targets exactly one existing `slide.channel` or `slide.slide`. Use the public projection helpers in `facodi_learning`; they enforce `website_published`, native visibility and Website scope before returning a URL. Do not make audit relations readable to Public/Portal users to simplify rendering.
- Coverage is review history: create it as a proposal, then use `action_approve()` or `action_reject()` as an eLearning Manager. Approved/rejected coverage is immutable. Never write a terminal state, reviewer fields, generated provenance or confidence evidence through caller-provided context.
- Public course-template extensions must keep their helper payloads and QWeb keys in sync. `approved_course_curriculum_links`, for example, needs `coverage_label`; test an anonymous course with approved coverage, not only the curriculum index.
- `facodi_ai` is a reusable server-side service layer for provider, connection, profile, prompt and request audit; `facodi_ai_website` is its optional Website translation plugin. Provider calls must be on demand, structured, auditable and fail closed. Never claim provider-driven curriculum suggestions are complete without an actual validated provider output, review action and regression coverage.
- AI credentials are write-only configuration: resolve them from `ir.config_parameter` with environment fallback, never expose them in fields, payloads, traces or user-facing errors. Database values take precedence; do not add a context-based bypass for default-connection or review invariants.

## UI and translations

- Preserve standard Website, Website Builder, `website_slides`, Portal and Odoo translation mechanisms. The theme provides FACODI styling, header/snippets and eLearning presentation; it does not own routes, menus, controllers or learning data.
- English is the QWeb source language. Use native module `.po` catalogues for `pt_PT`, `es_ES` and `fr_FR`; QWeb entries for `ir.ui.view` must use `model_terms:ir.ui.view,arch_db:<xmlid>`, not `arch`.
- Keep public curriculum routes stable: `/curriculos`, `/mapa-curricular`, `/unidades-curriculares`, `/curriculos/<reference>/unidades/<code>`, `/unidades-curriculares/<reference>/<slug>` and `/modulos/<id>`.
- When adding a menu/view reference in an Odoo manifest, load its action before the menu and load its parent menu before child menus. Fresh installation is the discriminating check; upgrade-only checks can hide ordering defects.
- Extend `website_slides` with QWeb inheritance and standard URL generation; do not replace its controllers or synthesize locale prefixes. Verify the default route and `/pt` route in a browser after public Website changes. Keep English as the source language and let native Website localization choose the canonical URL.

## Runtime invariants

- `deploy/coolify/docker-compose.yml` is the only active production runtime definition: PostgreSQL 16 -> one-shot `migrate` -> persistent `odoo`.
- The existing Coolify resource and the named volumes `postgres-data` and `odoo-data` are persistent production state. Never rename, delete, recreate or detach them to deploy a revision.
- The `migrate` service is a fail-closed gate. A failed migration must keep `odoo` stopped; do not bypass it or manually start Odoo against a partially migrated database.
- Keep PostgreSQL and Odoo unpublished to host ports in the production Compose file. Do not add a Compose `name:` override.
- The migration must remain idempotent and use standard Odoo APIs. Preserve its guarded `website_facodi` -> `theme_facodi` transition and do not add arbitrary rewrites of Website pages, courses, contacts or Website Builder content.

## Secrets and live instance work

- Never print, commit, paste into chat, or add real values from `.env`. It is ignored local state; use `.env.ci` for disposable tests and Coolify-generated `SERVICE_PASSWORD_64_POSTGRES` / `SERVICE_PASSWORD_64_ODOO_ADMIN` in production.
- For explicit live Odoo API work, load the local `.env` securely, confirm the target is `https://facodi.com` and the `facodi` database, and prefer standard Odoo models and reversible, narrowly scoped changes.
- Do not assume a live API credential exists merely because the variable is declared. Report authentication or availability blockers without weakening repository security.
- Database and `odoo-data` backups are a matched pair for migrations and rollback. Never use `docker compose down -v` against production persistence.
- Live editorial mapping starts with a read-only inventory of canonical units, public courses, existing assignments/items and coverage identities. Create only the missing diff, call model review actions rather than direct state writes, then re-read and assert publication/approval. Keep a guarded, idempotent operation script under `scripts/` when it documents a repeatable mapping; never encode live secrets or make it a migration side effect.

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
- `tests/test_coolify_runtime.sh` is the disposable end-to-end check: fresh migration, idempotent migration, Odoo health, Website languages and standard-webclient browser acceptance.
- Do not copy the test-only host port publication from `tests/docker-compose.ci.yml` into production.
- The runtime test also asserts the validated UAlg LESTI reference has 43 units and verifies anonymous `/curriculos`, `/mapa-curricular`, `/pt/mapa-curricular` and a UC detail route. Stop the local dev `odoo` service first when port `8069` is occupied; this does not affect persistent data.
- If the host Python lacks `pytest`, use a disposable virtual environment outside the repository and prepend its `bin` directory to `PATH`; do not bypass the final backend check.
- For a learning-addon change, update the module locally before testing it: `bash scripts/dev.sh update facodi_learning`. Cover proposed-to-reviewed lifecycle and public/anonymous visibility separately. For Website work, also verify desktop and mobile widths and check for horizontal overflow.

## Local development

- Read [`docs/development.md`](docs/development.md) before changing Odoo modules. Use `bash scripts/dev.sh init` for a fresh local database, `bash scripts/dev.sh update <module>` after addon changes, and `bash scripts/dev.sh shell` for Odoo-context inspection.
- Local Compose state is isolated in `facodi-dev-postgres` and `facodi-dev-odoo`; never use their lifecycle commands as a model for the persistent Coolify volumes.
- Set `ODOO_SOURCE_PATH` when the default sibling Odoo 19 Community checkout is unavailable. Keep the runtime API compatible with Odoo 19 Community.

## Documentation and change discipline

- Read [`README.md`](README.md) for architecture and source composition, [`docs/operations.md`](docs/operations.md) for deployment/backup/rollback procedure, and [`docker/migrate.py`](docker/migrate.py) before changing migration behavior.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) is the ownership and installed-module inventory; use it to determine whether a change belongs here, in an addon submodule, or outside the Odoo image.
- Keep changes small and preserve the existing public module and environment contracts. Update tests or documentation when a contract changes.
- Do not commit generated local state, credentials, runtime logs or unrelated submodule changes.
- For live Odoo XML-RPC work, use a target guard for exactly `https://facodi.com` and database `facodi`, avoid printing environment values, make the smallest reversible operation, and verify the persisted result through standard models. Source deployment and live business-data changes are separate operations.
- Treat dated audit reports and old plans as evidence, not current contracts. For current pins, enabled modules and runtime behavior, consult `git submodule status`, `deploy/coolify/docker-compose.yml`, `docker/migrate.py`, and the executable tests before editing.