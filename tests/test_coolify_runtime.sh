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

unit = curriculum.unit_ids.filtered(
  lambda record: record.external_unit_code == "19411018"
)
if not unit:
    raise RuntimeError("Validated curriculum unit 19411018 is missing")
course = env["slide.channel"].create(
  {
    "name": "FACODI Runtime Curriculum Course",
    "website_id": website.id,
    "website_published": True,
    "is_published": True,
    "visibility": "public",
    "enroll": "public",
  }
)
coverage = env["facodi.learning.curriculum.coverage"].create(
  {
    "channel_id": course.id,
    "curriculum_unit_id": unit.id,
    "coverage_type": "covers",
    "confidence": 1.0,
  }
)
coverage.action_approve()
print("FACODI_RUNTIME_COURSE=" + course.website_url)

slide = env["slide.slide"].create(
  {
    "channel_id": course.id,
    "name": "FACODI Runtime Public Module Item",
    "slide_category": "document",
    "is_published": True,
    "website_published": True,
  }
)
module = env["facodi.learning.curriculum.module"].create(
  {
    "name": "FACODI Runtime Public Module",
    "website_published": True,
  }
)
env["facodi.learning.curriculum.module.item"].create(
  {
    "module_id": module.id,
    "slide_id": slide.id,
  }
)
env["facodi.learning.curriculum.module.assignment"].create(
  {
    "curriculum_unit_id": unit.id,
    "module_id": module.id,
  }
)
print("FACODI_RUNTIME_MODULE=" + module._facodi_public_path())

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
runtime_course_route="$(sed -n 's/^FACODI_RUNTIME_COURSE=//p' <<<"$state")"
if [[ -z "$runtime_course_route" ]]; then
  echo "Runtime curriculum course route is missing" >&2
  exit 1
fi
runtime_module_route="$(sed -n 's/^FACODI_RUNTIME_MODULE=//p' <<<"$state")"
if [[ -z "$runtime_module_route" ]]; then
  echo "Runtime curriculum module route is missing" >&2
  exit 1
fi

"${compose[@]}" exec -T \
  -e "RUNTIME_COURSE_ROUTE=$runtime_course_route" \
  -e "RUNTIME_MODULE_ROUTE=$runtime_module_route" \
  odoo python3 - <<'PY'
import os
import re
import urllib.request
import urllib.error

base = "http://127.0.0.1:8069"
runtime_course_route = os.environ["RUNTIME_COURSE_ROUTE"]
runtime_module_route = os.environ["RUNTIME_MODULE_ROUTE"]
curriculum_body = b""

class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self, request, fp, code, msg, headers, newurl):
    return None

no_redirect = urllib.request.build_opener(NoRedirect)

for legacy_route, canonical_route in (
  ("/curriculos", "/roadmaps"),
  ("/mapa-curricular", "/roadmaps"),
  ("/curriculos/1", "/roadmaps/1"),
  ("/curriculos/1/unidades/19411017", "/roadmaps/1/units/19411017"),
):
  try:
    no_redirect.open(base + legacy_route, timeout=15)
  except urllib.error.HTTPError as error:
    if error.code != 301 or error.headers.get("Location") != canonical_route:
      raise RuntimeError(
        f"{legacy_route} must permanently redirect to {canonical_route}"
      ) from error
  else:
    raise RuntimeError(f"{legacy_route} did not return a permanent redirect")
  print(f"PASS {legacy_route} -> {canonical_route}")

for route in (
  "/",
  "/pt/",
  "/es/",
  "/fr/",
  "/slides",
  "/roadmaps",
  "/pt/roadmaps",
):
    response = urllib.request.urlopen(base + route, timeout=15)
    if response.status != 200:
        raise RuntimeError(f"{route} returned HTTP {response.status}")
    body = response.read()
    if route == "/roadmaps":
        curriculum_body = body
        if b"Engenharia de Sistemas e Tecnologias Inform" not in body:
            raise RuntimeError("public roadmap page does not expose the validated LESTI reference")
        if b"Curriculum Map" in body:
          raise RuntimeError("public roadmap navigation retains the legacy curriculum label")
    if route == "/pt/roadmaps" and b"Roadmaps" not in body:
      raise RuntimeError("Portuguese public roadmap is not rendered")
    print(f"PASS {route}")

detail_match = re.search(rb'href="(/roadmaps/[0-9]+)"', curriculum_body)
if not detail_match:
  raise RuntimeError("public roadmap index does not link to a roadmap detail page")

detail_route = detail_match.group(1).decode("utf-8")
detail = urllib.request.urlopen(base + detail_route, timeout=15)
detail_body = detail.read()
if detail.status != 200:
    raise RuntimeError(f"{detail_route} returned HTTP {detail.status}")
if b"Roadmap" not in detail_body:
  raise RuntimeError("roadmap detail does not expose the public roadmap matrix")
if b"FACODI Runtime Public Module" not in detail_body:
  raise RuntimeError("roadmap detail does not expose published learning modules")

unit_match = re.search(rb'href="(/roadmaps/[0-9]+/units/19411017)"', detail_body)
if not unit_match:
  raise RuntimeError("roadmap detail does not link Base de Dados II to its public unit page")

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

course = urllib.request.urlopen(base + runtime_course_route, timeout=15)
course_body = course.read()
if course.status != 200:
  raise RuntimeError(f"{runtime_course_route} returned HTTP {course.status}")
if "Ligação a currículos oficiais".encode() not in course_body:
  raise RuntimeError("public course does not render approved curriculum alignment")
print(f"PASS {runtime_course_route}")

module = urllib.request.urlopen(base + runtime_module_route, timeout=15)
module_body = module.read()
if module.status != 200:
  raise RuntimeError(f"{runtime_module_route} returned HTTP {module.status}")
if b"FACODI Runtime Public Module Item" not in module_body:
  raise RuntimeError("public module does not render its published learning item")
print(f"PASS {runtime_module_route}")
PY
python3 -m pytest tests/test_odoo_backend.py -q

echo "PASS: disposable Coolify runtime"
