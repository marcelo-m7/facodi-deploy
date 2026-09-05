#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

project="facodi-ci-${GITHUB_RUN_ID:-local}-$$"
compose=(docker compose --project-name "$project" --env-file .env.ci -f deploy/coolify/docker-compose.yml)

cleanup() {
  "${compose[@]}" logs --no-color >"/tmp/${project}-compose.log" 2>&1 || true
  "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" build
"${compose[@]}" up -d db

# A clean database must initialize successfully and an immediate second run
# must be idempotent before the persistent service is allowed to start.
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d odoo

healthy=0
for _attempt in $(seq 1 90); do
  container_id="$("${compose[@]}" ps -q odoo)"
  if [[ -n "$container_id" ]]; then
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
    if [[ "$status" == "healthy" ]]; then
      healthy=1
      break
    fi
    if [[ "$status" == "unhealthy" || "$status" == "exited" || "$status" == "dead" ]]; then
      echo "Odoo entered terminal state: $status" >&2
      "${compose[@]}" logs --no-color >&2 || true
      exit 1
    fi
  fi
  sleep 2
done

if [[ "$healthy" -ne 1 ]]; then
  echo "Odoo did not become healthy in time" >&2
  "${compose[@]}" logs --no-color >&2 || true
  exit 1
fi

state="$({
  "${compose[@]}" exec -T odoo bash -lc \
    'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"' <<'PY'
website = env["website"].search([], order="id", limit=1)
if not website:
    raise RuntimeError("FACODI Website record is missing")
print("FACODI_DEFAULT_LANG=" + website.default_lang_id.code)
print("FACODI_LANGS=" + ",".join(sorted(website.language_ids.mapped("code"))))
PY
} 2>&1)"

echo "$state"
grep -Fq 'FACODI_DEFAULT_LANG=en_US' <<<"$state"
for code in en_US pt_PT es_ES fr_FR; do
  grep -Eq "FACODI_LANGS=.*(^|,)${code}(,|$)|FACODI_LANGS=.*${code}" <<<"$state"
done

"${compose[@]}" exec -T odoo python3 - <<'PY'
import urllib.request

for route in ("/", "/pt/", "/es/", "/fr/", "/slides"):
    response = urllib.request.urlopen("http://127.0.0.1:8069" + route, timeout=15)
    if response.status != 200:
        raise RuntimeError(f"{route} returned HTTP {response.status}")
    response.read(256)
    print(f"PASS {route}")
PY

echo "PASS: disposable Coolify runtime"
