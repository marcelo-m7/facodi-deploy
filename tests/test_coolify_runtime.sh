#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

project="facodi-ci-${GITHUB_RUN_ID:-local}-$$"
compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file .env.ci
  -f deploy/coolify/docker-compose.yml
  -f tests/docker-compose.ci.yml
)

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

curriculum = env["facodi.learning.curriculum.reference"].search(
    [
        ("provider", "=", "ualg"),
        ("external_id", "=", "ualg-1941-2026-27"),
    ],
    limit=1,
)
if not curriculum:
    raise RuntimeError("Validated UAlg LESTI curriculum reference is missing")
if not curriculum.website_published or not curriculum.validated_at:
    raise RuntimeError("UAlg LESTI curriculum reference is not publicly validated")
if len(curriculum.unit_ids) != 43:
    raise RuntimeError(f"UAlg LESTI curriculum expected 43 units, got {len(curriculum.unit_ids)}")
print(f"FACODI_LESTI_CURRICULUM={curriculum.external_programme_code}:{len(curriculum.unit_ids)}")

admin = env.ref("base.user_admin")
admin.password = "facodi-ci-admin"
env.cr.commit()
PY
} 2>&1)"

echo "$state"
grep -Fq 'FACODI_DEFAULT_LANG=en_US' <<<"$state"
for code in en_US pt_PT es_ES fr_FR; do
  grep -Eq "FACODI_LANGS=.*(^|,)${code}(,|$)|FACODI_LANGS=.*${code}" <<<"$state"
done
grep -Fq 'FACODI_LESTI_CURRICULUM=1941:43' <<<"$state"

"${compose[@]}" exec -T odoo python3 - <<'PY'
import re
import urllib.request

base = "http://127.0.0.1:8069"
curriculum_body = b""

for route in (
  "/",
  "/pt/",
  "/es/",
  "/fr/",
  "/slides",
  "/curriculos",
  "/mapa-curricular",
  "/pt/mapa-curricular",
):
    response = urllib.request.urlopen(base + route, timeout=15)
    if response.status != 200:
        raise RuntimeError(f"{route} returned HTTP {response.status}")
    body = response.read()
    if route == "/curriculos":
        curriculum_body = body
        if b"Engenharia de Sistemas e Tecnologias Inform" not in body:
            raise RuntimeError("public curriculum page does not expose the validated LESTI reference")
    if route == "/mapa-curricular" and b"Published learning paths" not in body:
      raise RuntimeError("public curriculum map does not expose published learning paths")
    if route == "/pt/mapa-curricular" and b"Mapa curricular" not in body:
      raise RuntimeError("Portuguese public curriculum map is not translated")
    print(f"PASS {route}")

detail_match = re.search(rb'href="(/curriculos/[0-9]+)"', curriculum_body)
if not detail_match:
    raise RuntimeError("public curriculum index does not link to a curriculum detail page")

detail_route = detail_match.group(1).decode("utf-8")
detail = urllib.request.urlopen(base + detail_route, timeout=15)
detail_body = detail.read()
if detail.status != 200:
    raise RuntimeError(f"{detail_route} returned HTTP {detail.status}")
if b"Cobertura FACODI" not in detail_body:
    raise RuntimeError("curriculum detail does not expose the public coverage matrix")

unit_match = re.search(rb'href="(/curriculos/[0-9]+/unidades/19411017)"', detail_body)
if not unit_match:
    raise RuntimeError("curriculum detail does not link Base de Dados II to its public unit page")

unit_route = unit_match.group(1).decode("utf-8")
unit = urllib.request.urlopen(base + unit_route, timeout=15)
unit_body = unit.read()
if unit.status != 200:
    raise RuntimeError(f"{unit_route} returned HTTP {unit.status}")
if b"BASE DE DADOS II" not in unit_body.upper():
    raise RuntimeError("public curricular-unit page does not render Base de Dados II")
if b"Sem cobertura publicada" not in unit_body:
    raise RuntimeError("empty reviewed coverage must render as a public editorial gap")
if b"Consultar fonte oficial" not in unit_body:
    raise RuntimeError("public curricular-unit page lost official-source provenance")
print(f"PASS {unit_route}")
PY
python3 -m pytest tests/test_odoo_backend.py -q

echo "PASS: disposable Coolify runtime"
