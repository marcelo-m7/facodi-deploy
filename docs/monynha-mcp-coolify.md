# Monynha Odoo MCP in FACODI's Coolify Compose

## Deployment candidate, not yet activated

The `monynha-mcp` Compose profile is **off by default**. It intentionally
leaves `db`, `migrate`, `odoo`, `postgres-data`, and `odoo-data` intact. Pushing
to `facodi-deploy/main` triggers an Odoo Coolify redeploy: therefore keep this
integration in a draft PR until paired Odoo DB/filestore backups and owner CI
are reviewed. The public consent route itself requires the new independent
`facodi_mcp_oauth` addon from the pinned `facodi-api` source.

### Consent UI on facodi.com

Configure these on the existing FACODI Coolify Odoo application:

| Variable | Value |
| --- | --- |
| `MONYNHA_OAUTH_SUPABASE_PUBLISHABLE_KEY` | Open2 **public/publishable** key only; never `service_role` |
| `MONYNHA_OAUTH_ALLOWED_CLIENT_IDS` | JSON array of explicitly reviewed Open2 OAuth **client IDs**; `[]` denies all |

Open2's global Site URL remains `https://facodi.com` and OAuth Authorization
Path remains `/oauth/consent`. These are shared auth settings, not owned by
FACODI's existing Supabase processing-plane project. An Odoo login does not
automatically log the user in to Open2.

### Isolated MCP profile

After approving the MCP HTTPS resource URL and DNS, use Coolify's managed
Docker Compose resource to activate profile `monynha-mcp`. Configure domain
routing for the `monynha-mcp` service at internal port `8000`, at the **root**
path, so `/.well-known/oauth-protected-resource/mcp`, `/mcp`, `/healthz`, and
`/readyz` all reach the same service. No host ports are published.

| Variable | Required action |
| --- | --- |
| `MONYNHA_MCP_DB_PASSWORD` | New high-entropy private password for isolated `monynha-db` PostgreSQL 17 |
| `MONYNHA_MCP_DATABASE_URL` | Full private SQLAlchemy `postgresql+psycopg://...@monynha-db:5432/monynha_mcp` with URL-encoded password |
| `MONYNHA_MCP_PUBLIC_URL` | Full `https://<approved-host>/mcp` URL; also automatically used as JWT audience |
| `MONYNHA_MCP_OAUTH_ALLOWED_CLIENT_IDS` | JSON array of reviewed Open2 OAuth clients; startup refuses empty |
| `MONYNHA_ODOO_KEY_DEFAULT` | Optional authorized Odoo API key only when a private connection references it |

The Compose pins a full immutable SHA from `marcelo-m7/odoo-remote-mcp`.
The container migrates **only** the `monynha_mcp` database on startup, then
serves Streamable HTTP. The Postgres resource has its own durable
`monynha-postgres-data` volume and an internal-only network. Never run the
Monynha Alembic migrations against either FACODI Odoo PostgreSQL or Open2.

The MCP `oauth_provider` is `supabase` and `writes_enabled` is **always false**
in this candidate. Normal Open2 session JWTs have `aud=authenticated` and are
rejected by Monynha: an approved, scope-limited Custom Access Token Hook
must issue a single signed `aud` equal to `MONYNHA_MCP_PUBLIC_URL` **only** for
approved OAuth clients, without changing Tube O2/FACODI normal sessions or
refresh tokens. Verify real PKCE authorization and refresh before activating
this profile; never weaken the MCP `aud` check.

### Acceptance and rollback

1. Confirm Open2 discovery, registered OAuth client, valid `authorization_id`,
   approval, denial, and login error behavior on `/oauth/consent`.
2. Validate a scoped real access token (`iss`, `sub`, `aud`, `client_id`, expiry,
   signature) and reject unbound client, regular Open2 session token,
   wrong issuer and cross-org access. Configure explicit Monynha principal,
   connection and read grants through `monynha-odoo-admin` only.
3. Verify `/readyz`, protected-resource discovery, tool listing and permitted
   read-only Odoo calls, while writes send **zero** Odoo requests.
4. Test backup and restore of `monynha-postgres-data`, and perform paired
   FACODI DB/filestore backup before any Odoo module installation.
5. Roll back by disabling the `monynha-mcp` profile, revoking registered
   Monynha OAuth clients, and reverting the pinned addon integration. Preserve
   the Odoo/Postgres persistent volumes and do not rotate shared Supabase JWT
   signing keys as a Monynha rollback.
