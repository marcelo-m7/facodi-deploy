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
gap_unit = next(
  (
    record
    for record in curriculum.unit_ids
    if not record._facodi_public_coverage_rows(website=website)
  ),
  None,
)
if not gap_unit:
    raise RuntimeError("A public curricular unit without reviewed coverage is required")
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
print("FACODI_RUNTIME_GAP_UNIT_CODE=" + gap_unit.external_unit_code)
print("FACODI_RUNTIME_GAP_UNIT_ID=" + str(gap_unit.id))

# Publication governance is enabled by the migration. Model the production
# contract in the disposable fixture instead of bypassing it: create canonical
# content unpublished, record explicit review evidence, approve as an eLearning
# Manager, and only then publish.
slide = env["slide.slide"].create(
  {
    "channel_id": course.id,
    "name": "FACODI Runtime Public Module Item",
    "slide_category": "document",
    "is_published": False,
    "website_published": False,
    "is_preview": True,
  }
)
admin = env.ref("base.user_admin")
manager_group = env.ref("website_slides.group_website_slides_manager")
if manager_group not in admin.group_ids:
    admin.write({"group_ids": [(4, manager_group.id)]})
review = env["facodi.learning.content.review"].create(
  {
    "slide_id": slide.id,
    "author": "FACODI CI",
    "rights_mode": "original",
    "usage_basis": "Disposable runtime fixture created by FACODI CI.",
    "purpose": "Validate governed public module rendering in the disposable runtime.",
  }
)
review.with_user(admin).action_approve()
slide.write({"is_published": True, "website_published": True})

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

submission_fields = env["facodi.learning.submission"]._fields
required_trace_fields = {
  "source_state",
  "slide_id",
  "analysis_job_id",
  "analysis_result_id",
  "processing_state",
}
missing_trace_fields = sorted(required_trace_fields - set(submission_fields))
if missing_trace_fields:
  raise RuntimeError(
    "FACODI submission processing trace fields are missing: "
    + ", ".join(missing_trace_fields)
  )
for field_name in (
  "source_state",
  "slide_id",
  "analysis_job_id",
  "analysis_result_id",
  "processing_state",
):
  if not submission_fields[field_name].compute_sudo:
    raise RuntimeError(
      f"FACODI submission trace field {field_name} must compute with audit read privileges"
    )
print(
  "FACODI_SUBMISSION_TRACE_FIELDS="
  + ",".join(sorted(required_trace_fields))
)

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
grep -Fq 'FACODI_SUBMISSION_TRACE_FIELDS=analysis_job_id,analysis_result_id,processing_state,slide_id,source_state' <<<"$state"
runtime_course_route="$(sed -n 's/^FACODI_RUNTIME_COURSE=//p' <<<"$state")"
runtime_gap_unit_code="$(sed -n 's/^FACODI_RUNTIME_GAP_UNIT_CODE=//p' <<<"$state")"
runtime_gap_unit_id="$(sed -n 's/^FACODI_RUNTIME_GAP_UNIT_ID=//p' <<<"$state")"
if [[ -z "$runtime_course_route" || -z "$runtime_gap_unit_code" || -z "$runtime_gap_unit_id" ]]; then
  echo "Runtime curriculum course/unit context is missing" >&2
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
  -e "RUNTIME_GAP_UNIT_CODE=$runtime_gap_unit_code" \
  -e "RUNTIME_GAP_UNIT_ID=$runtime_gap_unit_id" \
  odoo python3 - <<'PY'
import os
import re
import urllib.request
import urllib.error

base = "http://127.0.0.1:8069"
runtime_course_route = os.environ["RUNTIME_COURSE_ROUTE"]
runtime_module_route = os.environ["RUNTIME_MODULE_ROUTE"]
runtime_gap_unit_code = os.environ["RUNTIME_GAP_UNIT_CODE"]
runtime_gap_unit_id = os.environ["RUNTIME_GAP_UNIT_ID"]
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
  "/contribuir/recurso",
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
        if b'href="/contribuir/recurso"' not in body:
          raise RuntimeError("public roadmap index does not expose the guided contribution CTA")
    if route == "/pt/roadmaps" and b"Roadmaps" not in body:
      raise RuntimeError("Portuguese public roadmap is not rendered")
    if route == "/contribuir/recurso":
      if b"Suggest a learning resource" not in body:
        raise RuntimeError("guided resource submission form is not public")
      for marker in (
        b'data-metadata-endpoint="/contribuir/recurso/metadata"',
        b'data-facodi-discover-button="1"',
        b'data-facodi-metadata-preview="1"',
        b"Detect details",
      ):
        if marker not in body:
          raise RuntimeError(
            f"guided resource submission form lost URL-first discovery marker: {marker!r}"
          )
      title_match = re.search(
        rb'<input\b[^>]*\bid=["\']facodi_submission_name["\'][^>]*>',
        body,
        flags=re.IGNORECASE,
      )
      if not title_match:
        raise RuntimeError("guided resource submission title field is missing")
      if re.search(
        rb'\brequired(?:\s*=\s*(?:"[^"]*"|\'[^\']*\'|[^\s>]+))?',
        title_match.group(0),
        flags=re.IGNORECASE,
      ):
        raise RuntimeError(
          "resource title still blocks server-side URL metadata discovery without JavaScript"
        )
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

if not re.search(rb'href="/roadmaps/[0-9]+/units/19411017"', detail_body):
  raise RuntimeError("roadmap detail does not link Base de Dados II to its public unit page")

unit_route = f"{detail_route}/units/{runtime_gap_unit_code}"
unit = urllib.request.urlopen(base + unit_route, timeout=15)
unit_body = unit.read()
if unit.status != 200:
    raise RuntimeError(f"{unit_route} returned HTTP {unit.status}")
if b"No published coverage" not in unit_body:
    raise RuntimeError("empty reviewed coverage must render as a public editorial gap")
if b"View official source" not in unit_body:
    raise RuntimeError("public curricular-unit page lost official-source provenance")
expected_contribution_href = (
    f'/contribuir/recurso?curriculum_unit_id={runtime_gap_unit_id}'.encode("utf-8")
)
if expected_contribution_href not in unit_body:
    raise RuntimeError("curricular-unit page does not preserve context in its contribution CTA")
print(f"PASS {unit_route}")

contextual_submission_route = (
    f"/contribuir/recurso?curriculum_unit_id={runtime_gap_unit_id}"
)
contextual_submission = urllib.request.urlopen(
    base + contextual_submission_route, timeout=15
)
contextual_submission_body = contextual_submission.read()
if contextual_submission.status != 200:
    raise RuntimeError(
        f"{contextual_submission_route} returned HTTP {contextual_submission.status}"
    )
if b"Suggested for curricular unit" not in contextual_submission_body:
    raise RuntimeError("guided contribution form lost curricular-unit context")
print(f"PASS {contextual_submission_route}")

course = urllib.request.urlopen(base + runtime_course_route, timeout=15)
course_body = course.read()
if course.status != 200:
  raise RuntimeError(f"{runtime_course_route} returned HTTP {course.status}")
if b"Official curriculum alignment" not in course_body:
  raise RuntimeError("public course does not render approved curriculum alignment")
if b"Contribute to FACODI" not in course_body or b'href="/contribuir/recurso"' not in course_body:
  raise RuntimeError("public course does not expose the guided contribution CTA")
print(f"PASS {runtime_course_route}")

module = urllib.request.urlopen(base + runtime_module_route, timeout=15)
module_body = module.read()
if module.status != 200:
  raise RuntimeError(f"{runtime_module_route} returned HTTP {module.status}")
if b"FACODI Runtime Public Module Item" not in module_body:
  raise RuntimeError("public module does not render its published learning item")
print(f"PASS {runtime_module_route}")
PY

echo "PASS: disposable Coolify runtime"
