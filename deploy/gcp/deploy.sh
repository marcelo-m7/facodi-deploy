#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
env_file="${1:-$root/deploy/gcp/.env}"
if [[ ! -f "$env_file" ]]; then
  echo "Missing GCP environment file: $env_file" >&2
  exit 64
fi
env_file="$(realpath "$env_file")"

# This is a trusted, operator-owned shell environment file. Keep it private.
set -a
# shellcheck disable=SC1090
source "$env_file"
set +a
: "${FACODI_GCP_DOMAIN:?Set FACODI_GCP_DOMAIN in the environment file}"
: "${GCP_DB_PASSWORD:?Set GCP_DB_PASSWORD in the environment file}"
: "${GCP_ODOO_ADMIN_PASSWORD:?Set GCP_ODOO_ADMIN_PASSWORD in the environment file}"
if [[ ! "$FACODI_GCP_DOMAIN" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ || "$FACODI_GCP_DOMAIN" != *.* ]]; then
  echo "FACODI_GCP_DOMAIN must be a DNS hostname without scheme or path." >&2
  exit 64
fi
if [[ "$GCP_DB_PASSWORD" == replace-with-* || "$GCP_ODOO_ADMIN_PASSWORD" == replace-with-* ]]; then
  echo "Replace the example passwords before deployment." >&2
  exit 64
fi
if [[ "$FACODI_GCP_DOMAIN" == "facodi.com" || "$FACODI_GCP_DOMAIN" == "www.facodi.com" ]]; then
  echo "Use a separate GCP hostname; production domain cutover requires a separate procedure." >&2
  exit 64
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or discard local changes before building the deployment image." >&2
  exit 64
fi
if git submodule status | grep -Eq '^[-+U]'; then
  echo "Submodule checkout differs from the pinned gitlinks; initialize exact revisions." >&2
  exit 64
fi

revision="$(git rev-parse HEAD)"
export FACODI_IMAGE="facodi-gcp:${revision}"
compose=(docker compose --project-name facodi-gcp --env-file "$env_file" -f "$root/deploy/gcp/docker-compose.yml")

"${compose[@]}" config --quiet
# Build with the currently serving application still running. Exact commit tag
# is shared by the one-shot migration and the persistent Odoo service.
docker build -f docker/Dockerfile -t "$FACODI_IMAGE" .
"${compose[@]}" up -d db
# A failed migration leaves Odoo stopped; it must never serve a partially
# upgraded database. Caddy may show 502 while the application is stopped.
"${compose[@]}" stop odoo
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d --no-deps odoo caddy
"${compose[@]}" ps
