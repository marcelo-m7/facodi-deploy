#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

: "${FACODI_IMAGE:?FACODI_IMAGE must point to the already-built candidate image}"

project="facodi-prebuilt-rollback-${GITHUB_RUN_ID:-local}-$$"
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
    echo "=== FACODI prebuilt rollback persistence logs ===" >&2
    cat "/tmp/${project}.log" >&2 || true
  fi
  "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT

wait_for_odoo() {
  local id state
  for _ in {1..90}; do
    id="$("${compose[@]}" ps -q odoo)"
    if [[ -n "$id" ]]; then
      state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$id" 2>/dev/null || true)"
      [[ "$state" == "healthy" ]] && return 0
      [[ "$state" == "unhealthy" || "$state" == "exited" || "$state" == "dead" ]] && return 1
    fi
    sleep 2
  done
  return 1
}

original_image="$FACODI_IMAGE"
rollback_image="facodi-prebuilt:rollback-${GITHUB_SHA:-local}"
docker tag "$original_image" "$rollback_image"

"${compose[@]}" config --quiet
"${compose[@]}" up -d db
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d odoo
wait_for_odoo || { echo "Initial Odoo did not become healthy" >&2; exit 1; }

db_id="$("${compose[@]}" ps -q db)"
odoo_id="$("${compose[@]}" ps -q odoo)"
postgres_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' "$db_id")"
odoo_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/odoo"}}{{.Name}}{{end}}{{end}}' "$odoo_id")"
[[ -n "$postgres_volume" && -n "$odoo_volume" ]] || { echo "Persistent volume names could not be resolved" >&2; exit 1; }

"${compose[@]}" exec -T db psql -U odoo -d facodi -v ON_ERROR_STOP=1 -c "CREATE TABLE IF NOT EXISTS facodi_ci_release_sentinel (value text primary key); INSERT INTO facodi_ci_release_sentinel(value) VALUES ('keep-me') ON CONFLICT DO NOTHING;" >/dev/null
"${compose[@]}" exec -T odoo sh -lc 'printf "%s\n" keep-me > /var/lib/odoo/facodi-ci-release-sentinel'

FACODI_IMAGE="$rollback_image" "${compose[@]}" up --abort-on-container-exit --exit-code-from migrate --force-recreate migrate
FACODI_IMAGE="$rollback_image" "${compose[@]}" up -d --force-recreate odoo
wait_for_odoo || { echo "Rollback-alias Odoo did not become healthy" >&2; exit 1; }

db_id_after="$("${compose[@]}" ps -q db)"
odoo_id_after="$("${compose[@]}" ps -q odoo)"
postgres_volume_after="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' "$db_id_after")"
odoo_volume_after="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/odoo"}}{{.Name}}{{end}}{{end}}' "$odoo_id_after")"
[[ "$postgres_volume_after" == "$postgres_volume" ]] || { echo "PostgreSQL volume changed across image rollback" >&2; exit 1; }
[[ "$odoo_volume_after" == "$odoo_volume" ]] || { echo "Odoo data volume changed across image rollback" >&2; exit 1; }
db_sentinel="$("${compose[@]}" exec -T db psql -U odoo -d facodi -Atc "SELECT value FROM facodi_ci_release_sentinel WHERE value='keep-me';")"
[[ "$db_sentinel" == "keep-me" ]] || { echo "Database sentinel was lost across image rollback" >&2; exit 1; }
file_sentinel="$("${compose[@]}" exec -T odoo cat /var/lib/odoo/facodi-ci-release-sentinel)"
[[ "$file_sentinel" == "keep-me" ]] || { echo "Odoo data sentinel was lost across image rollback" >&2; exit 1; }

FACODI_IMAGE="$original_image" "${compose[@]}" up --abort-on-container-exit --exit-code-from migrate --force-recreate migrate
FACODI_IMAGE="$original_image" "${compose[@]}" up -d --force-recreate odoo
wait_for_odoo || { echo "Original-image Odoo did not become healthy after rollback round-trip" >&2; exit 1; }

db_sentinel="$("${compose[@]}" exec -T db psql -U odoo -d facodi -Atc "SELECT value FROM facodi_ci_release_sentinel WHERE value='keep-me';")"
[[ "$db_sentinel" == "keep-me" ]] || { echo "Database sentinel was lost after rollback round-trip" >&2; exit 1; }
file_sentinel="$("${compose[@]}" exec -T odoo cat /var/lib/odoo/facodi-ci-release-sentinel)"
[[ "$file_sentinel" == "keep-me" ]] || { echo "Odoo data sentinel was lost after rollback round-trip" >&2; exit 1; }

echo "PASS image rollback preserved PostgreSQL and Odoo persistent volumes"
