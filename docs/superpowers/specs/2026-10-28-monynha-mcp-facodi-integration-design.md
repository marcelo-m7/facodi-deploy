# Monynha MCP on FACODI — deployment and OAuth consent design

**Status:** approved implementation direction from Marcelo, pending release gates. **Repositories:** `marcelo-m7/facodi-api` and `marcelo-m7/facodi-deploy`.

## Goal and boundaries

Publish the OAuth 2.1 consent UI at `https://facodi.com/oauth/consent` for **Open2** (`wvkjainfwsyiyfcmbtid`) while preparing an independently isolated Monynha MCP service in the existing FACODI Coolify Compose. Open2 remains the identity provider; FACODI's own Supabase processing plane is unrelated. The Odoo Website session is not an Open2 session.

The OAuth UI must show the registered client, exact redirect URI, and requested scopes; allow existing Open2 users to sign in and explicitly approve or deny; preserve `authorization_id`; never expose Open2 secret/service-role keys; and redirect only to a URL returned by the trusted Supabase SDK. Unknown OAuth clients must fail closed by default. The UI is a separate, installable Website addon owned by `facodi-api`, not by the presentation-only theme.

The MCP container has **no Odoo or FACODI Postgres credentials**. It uses a distinct PostgreSQL service, user, database and volume inside the existing Compose, with a separate migration/startup gate. Existing `postgres-data`, `odoo-data`, `db`, `migrate`, and `odoo` services and their dependencies remain unchanged apart from installing the new Website addon. The MCP service is opt-in via a Compose profile until issuer, audience, permitted clients, credentials, DNS and production backups are configured; `MONYNHA_MCP_WRITES_ENABLED=false` is the only default. Use an immutable Git revision for its Docker build context.

Open2's ordinary OAuth access tokens advertise `aud=authenticated` and standard scopes only. The Monynha resource server must continue requiring a **single signed audience matching the full MCP HTTPS resource URL**, a verified top-level `client_id` admitted in both configuration and the Monynha private database, explicit `(iss, sub)` principal binding, and per-connection read policies. Therefore an audience-scoped Open2 Custom Access Token Hook and actual OAuth PKCE token tests are separate activation gates; ordinary Open2 session tokens must never work against MCP. Do not change global Open2 Site URL, apply broad hooks, or merge/deploy without these checks.

## Considered approaches

1. **Independent FACODI Odoo Website addon (chosen):** native `/oauth/consent` on the already-configured Site URL, preserving the existing Odoo/proxy; requires a reviewed Odoo migration.
2. Separate frontend reverse-proxied at `/oauth/consent`: avoids Odoo addon but requires colliding path-based router rules on FACODI's existing domain.
3. Change Open2 Site URL: simpler frontend hosting but breaks unrelated Tube O2 Auth redirects and is prohibited here.

## Release gates

1. API owner addon tests, JS tests, Odoo install/upgrade check and translated mobile UI.
2. Deploy owner's submodule pin, Compose config and preservation contract tests.
3. Explicit Coolify MCP resource domain, secret settings and MCP database backup/restore plan; no host database ports.
4. Verified OAuth issuer discovery, real client registration, PKCE S256, `aud` hook on Open2 and two-tenant denial tests; no live production write operations.
5. Paired Odoo DB/filestore backup and reviewed merge/deploy of `facodi-deploy`, followed by read-only Website/Odoo/MCP browser and HTTP smoke checks.
