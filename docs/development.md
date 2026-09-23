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
bash scripts/dev.sh update facodi_ai,facodi_ai_website
```

Use an Odoo shell in the same source and addon context when inspecting local data:

```bash
bash scripts/dev.sh shell
```

`bash scripts/dev.sh down` stops local services but retains the two local-only
volumes. Delete `facodi-dev-postgres` and `facodi-dev-odoo` explicitly only when
you intentionally want a fresh local database and filestore.

## Boundaries

Develop business logic in its owning addon repository, not in this deployment
repository. This repository consumes those changes through submodule gitlinks.
Keep the development Compose file and its volumes separate from the Coolify
runtime, and validate integration changes with the repository's existing checks.