# Local Odoo Development

This environment is for local development only. Production remains defined solely
by `deploy/coolify/docker-compose.yml`; do not point this configuration at a
production database or copy production secrets into `.env.dev`.

## Prerequisites

- Docker Engine and Docker Compose;
- the pinned submodules initialized with `git submodule update --init --recursive`;
- the Odoo 19 source checkout at `../Codoo/odoo/odoo`, or another checkout set
  through `ODOO_SOURCE_PATH`.

The local Odoo source must match the 19.0 Community API used by the addons.

## Start

Create private local configuration, then install the requested modules into the
local database:

```bash
cp .env.dev.example .env.dev
bash scripts/dev.sh init
bash scripts/dev.sh up
```

Open `http://127.0.0.1:8069`. The local database is `facodi_dev` by default and
the master password is the `ODOO_ADMIN_PASSWD` value in `.env.dev`.

The development service runs the official local `odoo-bin` with `workers=0`,
`max-cron-threads=0`, and `--dev=all`. Odoo core and every addon root are bind
mounted and listed individually in `addons_path`; code changes are therefore
picked up by Odoo's development reloader without rebuilding the image.

## Module Workflow

Install requested modules only on a new local database:

```bash
bash scripts/dev.sh init
```

After changing Python models, XML data/views, security rules, JavaScript assets,
or manifests, run a normal Odoo module update before exercising the change:

```bash
bash scripts/dev.sh update facodi_learning
bash scripts/dev.sh update facodi_ai
```

Use an Odoo shell in the same source and addon context when inspecting local data:

```bash
bash scripts/dev.sh shell
```

`bash scripts/dev.sh down` stops local services but retains the two local-only
volumes. Delete `facodi-dev-postgres` and `facodi-dev-odoo` explicitly only when
you intentionally want a fresh local database and filestore.

## Isolated API and Learning acceptance

The API harness accepts any clean Git checkout or worktree containing the tracked
`facodi_api` addon; it no longer requires a historical `/tmp` directory name.
It prints the API and Learning source commits before creating disposable services.
Use `--check-source` for an API-only preflight without fetching or starting Docker:

```bash
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" bash tests/test_api_e2e_isolated.sh --check-source
FACODI_API_SOURCE="$PWD/addons/facodi-api/facodi_api" bash tests/test_api_e2e_isolated.sh
python3 tests/test_repository_contract.py ApiSourcePreflightTest NativeTestVerdictTest -v
```

The full harness validates installation, upgrades, HTTP, the actual scheduler and
restart. When the selected Learning checkout depends on `facodi_api`, it also
installs Learning in a separate disposable database and runs
`facodi_api_consumers`. A legacy Learning pin without that dependency reports
`NOT_EXECUTED`, not a consumer-integration pass. Native acceptance requires a
nonzero test count and a zero-failure/error summary, independently of Odoo's
process exit status.

Both addon sources are read-only mounts. Databases, volumes, network and loopback
ports belong to the uniquely named test project; cleanup checks ownership labels.
This validates the selected source composition only. It does not change deployment
gitlinks, activate production processing or replace the full Coolify/browser and
paired-backup acceptance gates.

## Boundaries

Develop business logic in its owning addon repository, not in this deployment
repository. This repository consumes those changes through submodule gitlinks.
Keep the development Compose file and its volumes separate from the Coolify
runtime, and validate integration changes with the repository's existing checks.