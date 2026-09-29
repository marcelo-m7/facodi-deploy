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
  status=$?
  log_path="/tmp/${project}-compose.log"
  "${compose[@]}" logs --no-color >"$log_path" 2>&1 || true
  if [[ "$status" -ne 0 ]]; then
    echo "=== FACODI disposable runtime logs ===" >&2
    cat "$log_path" >&2 || true
  fi
  "${compose[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  return "$status"
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" build
"${compose[@]}" up -d db

db_container_id="$("${compose[@]}" ps -q db)"
if [[ -z "$db_container_id" ]]; then
  echo "PostgreSQL container was not created" >&2
  exit 1
fi
for _ in {1..60}; do
  db_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$db_container_id" 2>/dev/null || true)"
  [[ "$db_health" == "healthy" ]] && break
  [[ "$db_health" == "unhealthy" || "$db_health" == "exited" || "$db_health" == "dead" ]] && {
    echo "PostgreSQL failed before clean-install preflight (state: $db_health)" >&2
    exit 1
  }
  sleep 1
done
db_health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$db_container_id" 2>/dev/null || true)"
if [[ "$db_health" != "healthy" ]]; then
  echo "Timed out waiting for PostgreSQL healthcheck (state: $db_health)" >&2
  exit 1
fi
echo "PASS PostgreSQL is healthy before clean-install preflight"

if [[ "${FACODI_REQUIRE_EMPTY_DATABASE:-0}" == "1" ]]; then
  empty_database_count="$(
    "${compose[@]}" exec -T db psql -U odoo -d postgres -Atc \
      "SELECT count(*) FROM pg_database WHERE datname = 'facodi';"
  )"
  if [[ "$empty_database_count" != "0" ]]; then
    echo "Clean-install gate expected no pre-existing facodi database" >&2
    exit 1
  fi
  echo "PASS clean-install starts without a facodi database"
fi

# A clean database must initialize successfully and an immediate second run
# must be idempotent before the persistent service is allowed to start.
"${compose[@]}" run --rm migrate

if [[ "${FACODI_REQUIRE_EMPTY_DATABASE:-0}" == "1" ]]; then
  initialized_database_count="$(
    "${compose[@]}" exec -T db psql -U odoo -d postgres -Atc \
      "SELECT count(*) FROM pg_database WHERE datname = 'facodi';"
  )"
  if [[ "$initialized_database_count" != "1" ]]; then
    echo "Clean-install gate did not create the facodi database exactly once" >&2
    exit 1
  fi
  echo "PASS clean-install created facodi database"
fi

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

set +e
state="$({
  "${compose[@]}" exec -T odoo bash -lc \
    'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"' <<'PY'
website = env["website"].search([], order="id", limit=1)
if not website:
    raise RuntimeError("FACODI Website record is missing")
expected_modules = ("facodi_learning", "theme_facodi", "facodi_ai", "facodi_ai_website", "muk_web_theme", "monodoo_core", "monodoo_home")
modules = env["ir.module.module"].search([("name", "in", list(expected_modules))])
module_states = {module.name: module.state for module in modules}
if set(module_states) != set(expected_modules):
    raise RuntimeError("Clean install is missing one or more FACODI modules")
if any(state != "installed" for state in module_states.values()):
    raise RuntimeError("One or more FACODI modules are not fully installed")
print("FACODI_INSTALLED_MODULES=" + ",".join(sorted(expected_modules)))
retired_modules = env["ir.module.module"].search([
    ("name", "in", ["onlyoffice_odoo", "monodoo_theme", "monodoo_backend", "monodoo_appsbar"]),
    ("state", "=", "installed"),
])
if retired_modules:
    raise RuntimeError(
        "Retired backend modules remain installed: " + ",".join(retired_modules.mapped("name"))
    )
home_action = env.ref("monodoo_home.action_monodoo_home", raise_if_not_found=False)
home_menu = env.ref("monodoo_home.menu_monodoo_home", raise_if_not_found=False)
if not home_action or not home_menu:
    raise RuntimeError("Monodoo Home launcher records are missing")
print("FACODI_BACKEND_THEME=muk_web_theme")
print("FACODI_BACKEND_HOME=monodoo_home")
print("FACODI_DEFAULT_LANG=" + website.default_lang_id.code)
print("FACODI_LANGS=" + ",".join(sorted(website.language_ids.mapped("code"))))

hero_view = env["ir.ui.view"].search(
    [
        ("key", "=", "theme_facodi.s_facodi_hero"),
        ("website_id", "=", website.id),
    ],
    limit=1,
)
if not hero_view:
    hero_view = env["ir.ui.view"].search(
        [("key", "=", "theme_facodi.s_facodi_hero")],
        limit=1,
    )
if not hero_view:
    raise RuntimeError("FACODI hero snippet Website view is missing")
hero_arch = str(hero_view.arch_db or "")
for marker in (
    'data-facodi-dot-grid="1"',
    'facodi-dot-grid__canvas',
    'data-base-color="#3979C8"',
    'data-active-color="#37BED2"',
):
    if marker not in hero_arch:
        raise RuntimeError(f"FACODI hero Dot Grid contract missing: {marker}")
print("FACODI_DOT_GRID=canvas,theme,interaction")

community_modules = env["ir.module.module"].search([
    ("name", "in", ["website_forum", "website_slides_forum"]),
])
community_states = {module.name: module.state for module in community_modules}
for module_name in ("website_forum", "website_slides_forum"):
    if community_states.get(module_name) != "installed":
        raise RuntimeError(f"{module_name} is not installed: {community_states.get(module_name)!r}")
for model_name in ("forum.forum", "forum.post"):
    if model_name not in env:
        raise RuntimeError(f"Standard Odoo community model {model_name} is missing")
if "forum_id" not in env["slide.channel"]._fields:
    raise RuntimeError("website_slides_forum did not expose slide.channel.forum_id")
print("FACODI_COMMUNITY_MODULES=website_forum,website_slides_forum")
print("FACODI_COMMUNITY_BRIDGE=slide.channel.forum_id")

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

design_inventory = []
for programme_code, external_id, expected_units in (
  ("1930", "ualg-1930-2026-27", 19),
  ("1454", "ualg-1454-2026-27", 41),
):
  reference = env["facodi.learning.curriculum.reference"].search(
    [
      ("provider", "=", "ualg"),
      ("external_id", "=", external_id),
    ],
    limit=1,
  )
  if not reference:
    raise RuntimeError(f"UAlg design curriculum {external_id} is missing")
  if not reference.website_published or not reference.validated_at:
    raise RuntimeError(f"UAlg design curriculum {external_id} is not publicly validated")
  if reference.external_programme_code != programme_code:
    raise RuntimeError(
      f"UAlg design curriculum {external_id} has unexpected programme code "
      f"{reference.external_programme_code!r}"
    )
  if len(reference.unit_ids) != expected_units:
    raise RuntimeError(
      f"UAlg design curriculum {external_id} expected {expected_units} units, "
      f"got {len(reference.unit_ids)}"
    )
  design_inventory.append(f"{programme_code}:{len(reference.unit_ids)}")
print("FACODI_DESIGN_CURRICULA=" + ",".join(design_inventory))

expected_dtm_support = {"19301001", "19301006", "19301007", "19301008", "19301009"}
dtm_reference = env["facodi.learning.curriculum.reference"].search(
  [("provider", "=", "ualg"), ("external_id", "=", "ualg-1930-2026-27")],
  limit=1,
)
dtm_coverage = env["facodi.learning.curriculum.coverage"].search(
  [
    ("curriculum_unit_id.reference_id", "=", dtm_reference.id),
    ("state", "=", "approved"),
    ("coverage_type", "=", "supports"),
  ]
)
dtm_codes = set(dtm_coverage.mapped("curriculum_unit_id.external_unit_code"))
if not expected_dtm_support.issubset(dtm_codes):
  raise RuntimeError(
    "DTM approved support coverage is missing expected units: "
    + ",".join(sorted(expected_dtm_support - dtm_codes))
  )
print("FACODI_DTM_SUPPORTS=" + ",".join(sorted(expected_dtm_support)))

ldcom_reference = env["facodi.learning.curriculum.reference"].search(
  [("provider", "=", "ualg"), ("external_id", "=", "ualg-1454-2026-27")],
  limit=1,
)
expected_ldcom_support = {"14541153", "14541196"}
ldcom_coverage = env["facodi.learning.curriculum.coverage"].search(
  [
    ("curriculum_unit_id.reference_id", "=", ldcom_reference.id),
    ("state", "=", "approved"),
    ("coverage_type", "=", "supports"),
  ]
)
ldcom_codes = set(ldcom_coverage.mapped("curriculum_unit_id.external_unit_code"))
if not expected_ldcom_support.issubset(ldcom_codes):
  raise RuntimeError(
    "Design de Comunicação approved support coverage is missing expected units: "
    + ",".join(sorted(expected_ldcom_support - ldcom_codes))
  )
print("FACODI_LDCOM_SUPPORTS=" + ",".join(sorted(expected_ldcom_support)))

typography_channel = env.ref("__import__.facodi_ldcom_14541153")
art_history_channel = env.ref("__import__.facodi_ldcom_14541196")
typography_published = typography_channel.slide_ids.filtered(
  lambda slide: slide.is_published and slide.website_published
)
art_history_published = art_history_channel.slide_ids.filtered(
  lambda slide: slide.is_published and slide.website_published
)
if len(typography_published) != 20:
  raise RuntimeError(
    f"Curated Typography I recovery expected 20 published resources, got {len(typography_published)}"
  )
if len(art_history_published) != 22:
  raise RuntimeError(
    f"Curated Art History recovery expected 22 published resources, got {len(art_history_published)}"
  )
print("FACODI_DESIGN_RECOVERY=typography:20,art-history:22")

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
print("FACODI_RUNTIME_ROADMAP=/roadmaps/" + str(curriculum.id))
print(
  "FACODI_RUNTIME_UNIT=/roadmaps/%s/units/%s"
  % (curriculum.id, unit.external_unit_code)
)
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

# Seed a real native Odoo video slide. This protects the exact fullscreen
# rendering path used by production FACODI courses without depending on an
# external metadata request during CI.
video_slide = env["slide.slide"].with_context(
  website_slides_skip_fetch_metadata=True
).create(
  {
    "channel_id": course.id,
    "name": "FACODI Runtime YouTube Video",
    "slide_category": "video",
    "source_type": "external",
    "video_url": "https://www.youtube.com/watch?v=w9gb71ZUJDs",
    "is_published": False,
    "website_published": False,
    "is_preview": True,
  }
)
video_review = env["facodi.learning.content.review"].create(
  {
    "slide_id": video_slide.id,
    "author": "FACODI CI",
    "rights_mode": "external",
    "source_url": "https://www.youtube.com/watch?v=w9gb71ZUJDs",
    "usage_basis": "Public YouTube URL used only to validate native Odoo video embedding.",
    "purpose": "Protect FACODI fullscreen video rendering in the disposable runtime.",
  }
)
video_review.with_user(admin).action_approve()
video_slide.write({"is_published": True, "website_published": True})
if video_slide.slide_category != "video":
    raise RuntimeError("Runtime YouTube fixture was not preserved as video")
if video_slide.slide_type != "youtube_video":
    raise RuntimeError(
      f"Runtime YouTube fixture expected youtube_video, got {video_slide.slide_type!r}"
    )
if not video_slide.youtube_id or "youtube-nocookie.com/embed/" not in str(video_slide.embed_code):
    raise RuntimeError("Runtime YouTube fixture did not produce the native Odoo embed")
print("FACODI_RUNTIME_VIDEO=" + video_slide.website_url)

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

community_submission = env["facodi.learning.submission"].create(
  {
    "name": "FACODI Runtime Pending Community Video",
    "source_url": "https://youtu.be/w9gb71ZUJDs",
    "context": "FACODI_RUNTIME_PRIVATE_CONTEXT_MUST_NOT_LEAK",
    "language": "pt",
  }
)
print("FACODI_RUNTIME_COMMUNITY_TOKEN=" + community_submission.access_token)

admin.password = "facodi-ci-admin"
env.cr.commit()
PY
} 2>&1)"
state_status=$?
set -e

echo "$state"
if [[ "$state_status" -ne 0 ]]; then
  echo "Runtime Odoo state probe failed with exit code $state_status" >&2
  exit "$state_status"
fi
installed_modules="$(sed -n 's/^FACODI_INSTALLED_MODULES=//p' <<<"$state")"
if [[ -z "$installed_modules" ]]; then
  echo "Runtime installed-module inventory is missing" >&2
  exit 1
fi
for module in facodi_ai facodi_ai_website facodi_learning theme_facodi monodoo_core monodoo_home muk_web_theme; do
  if ! grep -Eq "(^|,)${module}(,|$)" <<<"$installed_modules"; then
    echo "Runtime installed-module inventory is missing ${module}: ${installed_modules}" >&2
    exit 1
  fi
done
require_runtime_state() {
  local expected="$1"
  if ! grep -Fq "$expected" <<<"$state"; then
    echo "Runtime state is missing expected value: $expected" >&2
    exit 1
  fi
}

require_runtime_state 'FACODI_DEFAULT_LANG=en_GB'
require_runtime_state 'FACODI_DOT_GRID=canvas,theme,interaction'
runtime_languages="$(sed -n 's/^FACODI_LANGS=//p' <<<"$state")"
if [[ -z "$runtime_languages" ]]; then
  echo "Runtime Website language inventory is missing" >&2
  exit 1
fi
runtime_languages_csv=",$runtime_languages,"
for code in en_GB pt_PT es_ES fr_FR; do
  if [[ "$runtime_languages_csv" != *",$code,"* ]]; then
    echo "Runtime Website language inventory is missing $code: $runtime_languages" >&2
    exit 1
  fi
done
require_runtime_state 'FACODI_LESTI_CURRICULUM=1941:43'
require_runtime_state 'FACODI_DESIGN_CURRICULA=1930:19,1454:41'
require_runtime_state 'FACODI_DTM_SUPPORTS=19301001,19301006,19301007,19301008,19301009'
require_runtime_state 'FACODI_LDCOM_SUPPORTS=14541153,14541196'
require_runtime_state 'FACODI_DESIGN_RECOVERY=typography:20,art-history:22'
require_runtime_state 'FACODI_SUBMISSION_TRACE_FIELDS=analysis_job_id,analysis_result_id,processing_state,slide_id,source_state'
echo "PASS runtime state inventory"
runtime_community_token="$(sed -n 's/^FACODI_RUNTIME_COMMUNITY_TOKEN=//p' <<<"$state")"
if [[ -z "$runtime_community_token" ]]; then
  echo "Runtime community submission token is missing" >&2
  exit 1
fi
runtime_course_route="$(sed -n 's/^FACODI_RUNTIME_COURSE=//p' <<<"$state")"
runtime_roadmap_route="$(sed -n 's/^FACODI_RUNTIME_ROADMAP=//p' <<<"$state")"
runtime_unit_route="$(sed -n 's/^FACODI_RUNTIME_UNIT=//p' <<<"$state")"
runtime_gap_unit_code="$(sed -n 's/^FACODI_RUNTIME_GAP_UNIT_CODE=//p' <<<"$state")"
runtime_gap_unit_id="$(sed -n 's/^FACODI_RUNTIME_GAP_UNIT_ID=//p' <<<"$state")"
if [[ -z "$runtime_course_route" || -z "$runtime_roadmap_route" || -z "$runtime_unit_route" || -z "$runtime_gap_unit_code" || -z "$runtime_gap_unit_id" ]]; then
  echo "Runtime curriculum course/roadmap/unit context is missing" >&2
  exit 1
fi
runtime_module_route="$(sed -n 's/^FACODI_RUNTIME_MODULE=//p' <<<"$state")"
runtime_video_route="$(sed -n 's/^FACODI_RUNTIME_VIDEO=//p' <<<"$state")"
if [[ -z "$runtime_module_route" || -z "$runtime_video_route" ]]; then
  echo "Runtime curriculum module/video route is missing" >&2
  exit 1
fi

"${compose[@]}" exec -T \
  -e "RUNTIME_COURSE_ROUTE=$runtime_course_route" \
  -e "RUNTIME_ROADMAP_ROUTE=$runtime_roadmap_route" \
  -e "RUNTIME_MODULE_ROUTE=$runtime_module_route" \
  -e "RUNTIME_GAP_UNIT_CODE=$runtime_gap_unit_code" \
  -e "RUNTIME_GAP_UNIT_ID=$runtime_gap_unit_id" \
  -e "RUNTIME_COMMUNITY_TOKEN=$runtime_community_token" \
  odoo python3 - <<'PY'
import html
import os
import re
import urllib.request
import urllib.error

base = "http://127.0.0.1:8069"
runtime_course_route = os.environ["RUNTIME_COURSE_ROUTE"]
runtime_roadmap_route = os.environ["RUNTIME_ROADMAP_ROUTE"]
runtime_module_route = os.environ["RUNTIME_MODULE_ROUTE"]
runtime_gap_unit_code = os.environ["RUNTIME_GAP_UNIT_CODE"]
runtime_gap_unit_id = os.environ["RUNTIME_GAP_UNIT_ID"]
runtime_community_token = os.environ["RUNTIME_COMMUNITY_TOKEN"]
curriculum_body = b""

class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self, request, fp, code, msg, headers, newurl):
    return None

no_redirect = urllib.request.build_opener(NoRedirect)

for legacy_route, canonical_route in (
  ("/explorar", "/explore"),
  ("/explorar/areas", "/explore/areas"),
  ("/explorar/conteudos", "/explore/content"),
  ("/explorar/videos", "/explore/videos"),
  ("/unidades-curriculares", "/curricular-units"),
  ("/curriculos", "/roadmaps"),
  ("/mapa-curricular", "/roadmaps"),
  ("/curriculos/1", "/roadmaps/1"),
  ("/curriculos/1/unidades/19411017", "/roadmaps/1/units/19411017"),
  ("/facodi", "/"),
  ("/manifesto", "/sobre"),
  ("/comunidade", "/sobre"),
  ("/parceiros", "/sobre"),
  ("/roadmap", "/sobre#how-it-works"),
  ("/como-contribuir", "/contribuir/recurso"),
  ("/contribuir", "/contribuir/recurso"),
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
  "/courses",
  "/explore",
  "/curricular-units",
  "/contact",
  "/explore/areas",
  "/explore/content",
  "/explore/videos",
  "/roadmaps",
  "/pt/roadmaps",
  "/contribuir/recurso",
):
    response = urllib.request.urlopen(base + route, timeout=15)
    if response.status != 200:
        raise RuntimeError(f"{route} returned HTTP {response.status}")
    body = response.read()
    if route == "/explore":
        for marker in (b"/explore/areas", b"/explore/content", b"/explore/videos", b"/explore/courses"):
          if marker not in body:
            raise RuntimeError(f"Explore landing lost discovery entry point: {marker!r}")
    if route == "/explore/content":
        if b"FACODI Runtime Public Module Item" not in body:
          raise RuntimeError("Explore content catalogue does not expose governed public learning content")
        if b"/explore/courses" in body:
          raise RuntimeError("Explore content catalogue unexpectedly duplicates course navigation")
    if route == "/explore/videos":
        if b"FACODI Runtime Pending Community Video" not in body:
          raise RuntimeError("pending YouTube submission is missing from the public community queue")
        if b"Awaiting review" not in body:
          raise RuntimeError("pending community video lost its pre-review status")
        if runtime_community_token.encode("utf-8") in body:
          raise RuntimeError("private community submission token leaked into the public page")
        if b"FACODI_RUNTIME_PRIVATE_CONTEXT_MUST_NOT_LEAK" in body:
          raise RuntimeError("private submission context leaked into the public page")
        if b"https://www.youtube.com/watch?v=w9gb71ZUJDs" not in body:
          raise RuntimeError("community queue did not canonicalize the YouTube URL")
    if route == "/roadmaps":
        curriculum_body = body
        for marker in (
          b"Engenharia de Sistemas e Tecnologias Inform",
          b"Design e Tecnologias Multim",
          b"Design de Comunica",
        ):
          if marker not in body:
            raise RuntimeError(
              f"public roadmap page does not expose validated UAlg reference: {marker!r}"
            )
        if b"Curriculum Map" in body:
          raise RuntimeError("public roadmap navigation retains the legacy curriculum label")
        if b'href="/submissions/new?' not in body:
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

for contextual_route, expected_markers in (
  (
    "/submissions/new?type=resource&source=runtime_resource_cta&section=runtime&source_page_url=/roadmaps",
    (
      b'name="submission_type" value="resource"',
      b'name="source_cta" value="runtime_resource_cta"',
      b'name="source_section" value="runtime"',
      b'name="source_page_url" value="/roadmaps"',
      b'href="/roadmaps"',
      b"Back to where I was",
      b"Context pre-filled",
      b'data-facodi-submission-type-switcher="1"',
      b'name="facodi_company_website"',
      b"Required for contact requests and whenever you ask FACODI to follow up.",
    ),
  ),
  (
    "/submissions/new?type=contact&source=runtime_contact_cta&section=runtime&topic=partnership",
    (
      b'name="submission_type" value="contact"',
      b'name="source_cta" value="runtime_contact_cta"',
      b'name="source_section" value="runtime"',
      b'value="partnership" selected',
    ),
  ),
):
  contextual = urllib.request.urlopen(base + contextual_route, timeout=15)
  contextual_body = contextual.read()
  if contextual.status != 200:
    raise RuntimeError(f"{contextual_route} returned HTTP {contextual.status}")
  for marker in expected_markers:
    if marker not in contextual_body:
      raise RuntimeError(
        f"contextual intake lost pre-filled marker {marker!r}: {contextual_route}"
      )
  print(f"PASS contextual intake {contextual_route}")

catalogue_roadmaps = urllib.request.urlopen(
  base + "/facodi/home/catalogue-fragment?type=roadmaps", timeout=15
)
catalogue_roadmaps_body = catalogue_roadmaps.read()
if catalogue_roadmaps.status != 200:
  raise RuntimeError("homepage Roadmaps catalogue fragment is unavailable")
for marker in (
  b"Engenharia de Sistemas e Tecnologias Inform",
  b"Design e Tecnologias Multim",
  b"Design de Comunica",
):
  if marker not in catalogue_roadmaps_body:
    raise RuntimeError(
      f"homepage Roadmaps selector is missing validated UAlg reference: {marker!r}"
    )
print("PASS homepage Roadmaps catalogue fragment")

for localized_submission_route in (
  "/pt/submissions/new",
  "/en/submissions/new",
  "/es/submissions/new",
  "/fr/submissions/new",
):
  localized_submission = urllib.request.urlopen(
    base + localized_submission_route, timeout=15
  )
  localized_body = localized_submission.read()
  if localized_submission.status != 200:
    raise RuntimeError(
      f"{localized_submission_route} returned HTTP {localized_submission.status}"
    )
  if b'data-facodi-submission-form="1"' not in localized_body:
    raise RuntimeError(
      f"{localized_submission_route} lost the unified contextual intake"
    )
  print(f"PASS localized contextual intake {localized_submission_route}")

detail_match = re.search(rb'href="(/roadmaps/[0-9]+)"', curriculum_body)
if not detail_match:
  raise RuntimeError("public roadmap index does not link to a roadmap detail page")

detail_route = runtime_roadmap_route
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
    f'/submissions/new?type=resource&unit_id={runtime_gap_unit_id}'
    f'&source=unit_resource_cta&section=resources'
)
unit_html = html.unescape(unit_body.decode("utf-8"))
if expected_contribution_href not in unit_html:
    raise RuntimeError("curricular-unit page does not preserve context in its contribution CTA")
print(f"PASS {unit_route}")

contextual_submission_route = (
    f"/submissions/new?type=resource&unit_id={runtime_gap_unit_id}"
    f"&source=unit_resource_cta&section=resources"
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
if b"Contribute to FACODI" not in course_body:
  raise RuntimeError("public course does not expose the guided contribution CTA label")
if b'href="/submissions/new?' not in course_body:
  raise RuntimeError("public course contribution CTA does not enter the unified intake")
if b"source=course_resource_cta" not in course_body or b"course_id=" not in course_body:
  raise RuntimeError("public course contribution CTA does not preserve course context")
print(f"PASS {runtime_course_route}")

module = urllib.request.urlopen(base + runtime_module_route, timeout=15)
module_body = module.read()
if module.status != 200:
  raise RuntimeError(f"{runtime_module_route} returned HTTP {module.status}")
if b"FACODI Runtime Public Module Item" not in module_body:
  raise RuntimeError("public module does not render its published learning item")
print(f"PASS {runtime_module_route}")
PY

if [[ "${FACODI_BROWSER_ACCEPTANCE:-0}" == "1" ]]; then
  : "${FACODI_BROWSER_CHROME_BIN:?FACODI_BROWSER_CHROME_BIN is required}"
  : "${FACODI_BROWSER_SCREENSHOT_DIR:?FACODI_BROWSER_SCREENSHOT_DIR is required}"
  FACODI_BROWSER_BASE_URL="http://127.0.0.1:8069" \
  FACODI_BROWSER_COURSE_ROUTE="$runtime_course_route" \
  FACODI_BROWSER_ROADMAP_ROUTE="$runtime_roadmap_route" \
  FACODI_BROWSER_UNIT_ROUTE="$runtime_unit_route" \
  FACODI_BROWSER_MODULE_ROUTE="$runtime_module_route" \
  FACODI_BROWSER_VIDEO_ROUTE="$runtime_video_route" \
  FACODI_BROWSER_CHROME_BIN="$FACODI_BROWSER_CHROME_BIN" \
  FACODI_BROWSER_SCREENSHOT_DIR="$FACODI_BROWSER_SCREENSHOT_DIR" \
    node tests/test_campus_paper_browser.mjs
fi

bash tests/test_d2_editorial_runtime.sh "$project"

echo "PASS: disposable Coolify runtime"
