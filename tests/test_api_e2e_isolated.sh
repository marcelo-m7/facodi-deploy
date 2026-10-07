#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
api_source="${FACODI_API_SOURCE:-}"
if [[ -z "$api_source" || ! -f "$api_source/__manifest__.py" ]]; then
  echo "Set FACODI_API_SOURCE to the isolated facodi_api addon directory" >&2
  exit 2
fi
api_source="$(realpath "$api_source")"
if [[ "$api_source" != /tmp/facodi-api-e2e-*/facodi_api ]]; then
  echo "Refusing API source outside /tmp/facodi-api-e2e-*" >&2
  exit 2
fi

project="facodi-api-e2e-$(date -u +%Y%m%d%H%M%S)-$$"
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
export FACODI_API_SOURCE="$api_source"
export FACODI_E2E_HTTP_PORT="$port"
export FACODI_E2E_DB_USER="api_e2e_$$"
export FACODI_E2E_DB_PASSWORD="$(openssl rand -hex 24)"
export FACODI_E2E_DATABASE="facodi_api_e2e"
export FACODI_E2E_PROJECT="$project"

compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file /dev/null
  -f tests/docker-compose.api-e2e.yml
)

cleanup() {
  status=$?
  container_ids="$("${compose[@]}" ps -aq 2>/dev/null || true)"
  while IFS= read -r container_id; do
    [[ -z "$container_id" ]] && continue
    label="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container_id" 2>/dev/null || true)"
    if [[ "$label" != "$project" ]]; then
      echo "Refusing cleanup: container $container_id has unexpected project label" >&2
      return 1
    fi
  done <<< "$container_ids"
  volume_names="$(docker volume ls -q --filter "label=com.docker.compose.project=$project")"
  while IFS= read -r volume_name; do
    [[ -z "$volume_name" ]] && continue
    label="$(docker volume inspect --format '{{ index .Labels "com.docker.compose.project" }}' "$volume_name")"
    if [[ "$label" != "$project" ]]; then
      echo "Refusing cleanup: volume $volume_name has unexpected project label" >&2
      return 1
    fi
  done <<< "$volume_names"
  if [[ "$status" -ne 0 ]]; then
    "${compose[@]}" logs --no-color >&2 || true
  fi
  "${compose[@]}" down --volumes --remove-orphans >/dev/null
  return "$status"
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" up -d db

db_id="$("${compose[@]}" ps -q db)"
if [[ -z "$db_id" ]]; then
  echo "Isolated PostgreSQL container was not created" >&2
  exit 1
fi
for _attempt in $(seq 1 60); do
  db_state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$db_id")"
  [[ "$db_state" == healthy ]] && break
  [[ "$db_state" == unhealthy || "$db_state" == exited || "$db_state" == dead ]] && {
    echo "Isolated PostgreSQL entered terminal state: $db_state" >&2
    exit 1
  }
  sleep 1
done
if [[ "$(docker inspect --format '{{.State.Health.Status}}' "$db_id")" != healthy ]]; then
  echo "Timed out waiting for isolated PostgreSQL" >&2
  exit 1
fi

odoo_args=(
  --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons
  --database="$FACODI_E2E_DATABASE"
  --without-demo=true
  --workers=0
  --max-cron-threads=0
  --http-interface=0.0.0.0
)
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --init=facodi_api --stop-after-init
echo "PASS clean install"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --update=facodi_api --stop-after-init
echo "PASS first upgrade"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --update=facodi_api --stop-after-init
echo "PASS repeated upgrade"

"${compose[@]}" up -d odoo
odoo_id="$("${compose[@]}" ps -q odoo)"
for _attempt in $(seq 1 80); do
  odoo_state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$odoo_id")"
  [[ "$odoo_state" == healthy ]] && break
  [[ "$odoo_state" == unhealthy || "$odoo_state" == exited || "$odoo_state" == dead ]] && {
    echo "Odoo entered terminal state: $odoo_state" >&2
    exit 1
  }
  sleep 1
done
if [[ "$(docker inspect --format '{{.State.Health.Status}}' "$odoo_id")" != healthy ]]; then
  echo "Timed out waiting for isolated Odoo" >&2
  exit 1
fi

"${compose[@]}" exec -T odoo odoo shell --no-http \
  --db_host=db \
  --db_user="$FACODI_E2E_DB_USER" \
  --db_password="$FACODI_E2E_DB_PASSWORD" \
  --database="$FACODI_E2E_DATABASE" <<'PY'
params = env["ir.config_parameter"].sudo()
enabled = params.get_param("facodi_api.pipeline_enabled", "false")
assert enabled.lower() not in ("true", "1"), f"pipeline unexpectedly enabled: {enabled!r}"
cron = env.ref("facodi_api.ir_cron_facodi_pipeline_process")
assert not cron.active, "pipeline cron unexpectedly active"
assert env["facodi.pipeline.run"].search_count([]) == 0, "fresh install contains pipeline runs"
print("PASS pipeline gate and cron default disabled")
PY

python3 tests/api_http_e2e.py

echo "PASS isolated Odoo HTTP health at http://127.0.0.1:$port"