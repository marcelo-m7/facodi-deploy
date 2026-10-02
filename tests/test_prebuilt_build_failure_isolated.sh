#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

: "${FACODI_IMAGE:?FACODI_IMAGE must point to the already-built candidate image}"

project="facodi-prebuilt-build-fail-${GITHUB_RUN_ID:-local}-$$"
compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file .env.ci
  -f deploy/coolify/docker-compose.prebuilt.yml
  -f tests/docker-compose.ci.yml
)

cleanup() {
  status=$?
  "${compose[@]}" logs --no-color >"/tmp/${project}.log" 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    echo "=== FACODI prebuilt build-failure isolation logs ===" >&2
    cat "/tmp/${project}.log" >&2 || true
  fi
  "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" up -d db
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d odoo

odoo_id=""
for _ in {1..90}; do
  odoo_id="$("${compose[@]}" ps -q odoo)"
  if [[ -n "$odoo_id" ]]; then
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$odoo_id" 2>/dev/null || true)"
    [[ "$state" == "healthy" ]] && break
    [[ "$state" == "unhealthy" || "$state" == "exited" || "$state" == "dead" ]] && {
      echo "Odoo failed before build-failure isolation test (state: $state)" >&2
      exit 1
    }
  fi
  sleep 2
done

if [[ -z "$odoo_id" ]]; then
  echo "Odoo container was not created" >&2
  exit 1
fi

before_id="$odoo_id"
before_state="$(docker inspect --format '{{.State.Health.Status}}' "$before_id")"
[[ "$before_state" == "healthy" ]] || { echo "Odoo is not healthy before failed build" >&2; exit 1; }
curl -fsS --max-time 10 http://127.0.0.1:8069/web/login >/dev/null

set +e
docker build -f tests/definitely-missing.Dockerfile -t facodi-intentional-build-failure . >/tmp/facodi-build-failure.out 2>&1
build_status=$?
set -e
if [[ "$build_status" -eq 0 ]]; then
  echo "Intentional image build unexpectedly succeeded" >&2
  cat /tmp/facodi-build-failure.out >&2 || true
  exit 1
fi

after_id="$("${compose[@]}" ps -q odoo)"
if [[ "$after_id" != "$before_id" ]]; then
  echo "Active Odoo container changed during an unrelated failed image build" >&2
  exit 1
fi
after_state="$(docker inspect --format '{{.State.Health.Status}}' "$after_id")"
[[ "$after_state" == "healthy" ]] || { echo "Odoo lost health after failed image build" >&2; exit 1; }
curl -fsS --max-time 10 http://127.0.0.1:8069/web/login >/dev/null

echo "PASS failed image build left the active Odoo service untouched"
