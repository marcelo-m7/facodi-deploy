# FACODI Deploy Product

## Purpose

FACODI Deploy is the production composition for the FACODI Odoo 19 Community instance at `facodi.com`. It builds the immutable integration image, pins independently owned addons, and runs the guarded Coolify lifecycle for database migration and Odoo service startup.

## Users

Deployment operators and maintainers of the FACODI Odoo instance. They need reproducible releases, explicit source provenance, safe upgrades, and a practical rollback procedure that protects production state.

## Scope

This repository owns:

- the Docker image and addon source composition;
- the Coolify Compose definition;
- the fail-closed migration gate;
- exact source gitlinks, validation, and runtime acceptance tests;
- deployment, backup, and rollback documentation.

Business behavior belongs to the addon repositories. `facodi-deploy` must not copy their code or mutate Website Builder content, courses, contacts, or curriculum data as part of deployment.

## Product Constraints

- PostgreSQL 16, one-shot `migrate`, then persistent `odoo` is the only production lifecycle.
- `postgres-data` and `odoo-data` are persistent matched state and must not be recreated or detached during a normal deployment.
- A failed migration keeps Odoo stopped.
- Production Compose does not publish PostgreSQL or Odoo host ports.
- The Website supports English by default plus Portuguese, Spanish, and French through standard Odoo mechanisms.
- Curriculum facts require official sources; AI may propose, while a manager decides and publishes.

## Success Criteria

A revision is deployable when every source pin is reproducible, the migration is idempotent, the requested modules install and update through standard Odoo APIs, and the canonical repository and runtime checks pass without weakening persistence or security invariants.
