#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

: "${FACODI_IMAGE:?FACODI_IMAGE must point to the already-built candidate image}"

project="facodi-prebuilt-fail-${GITHUB_RUN_ID:-local}-$$"
compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file .env.ci
  -f deploy/coolify/docker-compose.prebuilt.yml
)

cleanup() {
  status=$?
  "${compose[@]}" logs --no-color >"/tmp/${project}.log" 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    echo "=== FACODI prebuilt fail-closed logs ===" >&2
    cat "/tmp/${project}.log" >&2 || true
  fi
  "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT

"${compose[@]}" config --quiet

set +e
SUPABASE_URL="https://example.invalid" \
SUPABASE_SECRET_KEY="" \
  "${compose[@]}" up --abort-on-container-exit --exit-code-from migrate migrate odoo
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "Expected migrate to fail when the Supabase credential pair is incomplete" >&2
  exit 1
fi

odoo_id="$("${compose[@]}" ps -aq odoo)"
if [[ -n "$odoo_id" ]]; then
  odoo_state="$(docker inspect --format '{{.State.Status}}' "$odoo_id" 2>/dev/null || true)"
  if [[ "$odoo_state" == "running" ]]; then
    echo "Odoo started even though migrate failed" >&2
    exit 1
  fi
fi

echo "PASS failed migration did not promote the prebuilt Odoo service"
