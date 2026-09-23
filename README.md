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

A `facodi-deploy` commit pins the exact source revisions baked into its Odoo image. The authoritative pins are the superproject gitlinks; this table documents the revisions selected by this integration:

| Source | Runtime modules | Pinned revision |
| --- | --- | --- |
| `marcelo-m7/facodi-ai` | `facodi_ai`, `facodi_ai_website` | `a041a674175a221c0ad6a1a97095d22e38f69e72` |
| `marcelo-m7/facodi-learning` | `facodi_learning` | `56e7eb326f8680fdd737ce98fae43ed4a290653b` |
| `marcelo-m7/facodi-theme` | `theme_facodi` | `827371a1499dbe8ed1d4bed1da906aab1be7daea` |
| `marcelo-m7/monodoo` | `monodoo_backend` and its dependencies | `bbc6f6affc730de7cf75c98c0d6d30da10740095` |
| `marcelo-m7/monynha-odoo` | `theme_monynha`, `monynha_content`, `monynha_lead_generator` | `5c9d4513487eb87f8fd3fe36b76765f25a13096d` |
| `odoo/design-themes` | only `theme_common` | `a1818df4ade65406c0cacae8b1ea676e6f70095f` |

The repository pins the Processing Plane source at `supabase/facodi-processing-plane`. It persists FACODI Supabase migrations, Edge Functions, shared helpers and live function snapshots outside `addons/`, so the Odoo image build does not absorb Supabase worker code by accident.

The FACODI learning pin provides the public official-curriculum golden path: UAlg LESTI 2026/27 is reconciled idempotently from a curated official-source fixture, remains separate from canonical `slide.channel` courses, exposes curricular-unit detail pages and a covered/partial/gap matrix, and renders only Manager-reviewed coverage that still passes native Odoo learner visibility.

The Coolify acceptance gate follows a real curricular unit from the curriculum index through the matrix to its public unit page, and verifies the explicit gap state plus official-source provenance.

The FACODI theme owns Website presentation and footer navigation. It must remain presentation-only: business data access belongs in the owning addon, not in theme QWeb templates.

The Monynha source remains available to the shared image but its optional `theme_monynha`, `monynha_content` and `monynha_lead_generator` modules are not part of the FACODI automatic installation set. Its Website chrome remains isolated from `theme_facodi`.

The migration gate requests `monodoo_backend`, which owns the required generic backend dependencies. It installs missing requested capabilities on existing databases before updating the complete requested module set. Monodoo remains an independently versioned source: FACODI consumes the pinned release and does not copy its implementation into this repository.

The repository contract validates the expected source paths, required addon manifests and the exact checked-out submodule revision against each superproject gitlink, so the deployment source composition cannot silently drift from the commit being deployed.

The Processing Plane scaffold is validated separately as a non-addon source boundary: the contract requires its bootstrap docs, Supabase config, captured live snapshots and extracted function sources to exist, while the Docker build must continue to ignore the `supabase/` tree.

## Migration lifecycle

The runtime image exposes two entrypoint modes:

```text
serve    -> long-running Odoo HTTP process
migrate  -> one-shot database/module/theme/language migration
```

For a fresh database, the migration initializes Odoo and the canonical FACODI modules without demo data. For an existing database it performs a guarded preflight, initializes any newly required module that is not yet installed, and then updates the complete requested module set. The known historical `website_facodi` presentation-only transition is accepted only when its ownership shape is unambiguous; otherwise migration fails closed.

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

Install the disposable browser-acceptance dependencies when running the full suite locally:

```bash
python3 -m pip install -r tests/requirements.txt
python3 -m playwright install --with-deps chromium
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

That test builds the canonical image, creates disposable volumes, runs migration twice to prove idempotency, starts Odoo, verifies Website language state, confirms all four Monodoo addons are installed, checks the Home client-action contract, authenticates a disposable admin session in a real Chromium browser, and requires the Monodoo Home, theme runtime and AppsBar to render without browser errors. It also preserves the existing HTTP checks for the FACODI Website/eLearning routes. The host port used by Chromium is exposed only through `tests/docker-compose.ci.yml`; the production Coolify Compose file does not publish Odoo directly.

GitHub Actions runs the same canonical Coolify acceptance path on pull requests and on `main`.

## Local development

For a disposable local environment that runs the checked-out Odoo 19 source and
the pinned addon worktrees through bind mounts, follow [`docs/development.md`](docs/development.md).
It is intentionally separate from the canonical Coolify runtime and its persistent volumes.

## Architecture inventory

[`ARCHITECTURE.md`](ARCHITECTURE.md) records the ownership boundary, source pins, runtime module contract, and a dated read-only inventory of the live Website, navigation, and learning data. It separates deployment contracts from observations so operational facts do not become implicit migration behavior.

## Deployment and rollback boundary

Operational deployment must update the existing Coolify resource instead of replacing it, so `postgres-data` and `odoo-data` remain attached.

Release `v0.1.0` is the preserved source snapshot from before the Coolify-canonical refactor. It is a source/history rollback boundary, not a promise that a newer database can be downgraded without restoring persistence.

If a deployed migration must be rolled back, restore the matching PostgreSQL backup and `odoo-data` backup together, then deploy the known-good source revision. See [`docs/operations.md`](docs/operations.md) for the production procedure.

## Security and operational invariants

- no plaintext production secrets are committed;
- PostgreSQL and Odoo ports are not published directly to the host by the production Compose file;
- migration failure prevents `odoo` startup;
- deploys must not run `docker compose down -v` against the production resource;
- persistent volume names and the existing Coolify resource identity must be preserved;
- language handling remains standard Odoo Website behavior;
- exact source pins are part of the repository contract.
