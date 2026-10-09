#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
api_source="${FACODI_API_SOURCE:-}"
if [[ -z "$api_source" || ! -f "$api_source/__manifest__.py" ]]; then
  echo "Set FACODI_API_SOURCE to the isolated facodi_api addon directory" >&2
  exit 2
fi
api_source="$(realpath "$api_source")"
api_repository="$(git -C "$api_source" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Refusing API source without a Git repository" >&2
  exit 2
}
if [[ "$api_source" != "$api_repository/facodi_api" ]] ||
   ! git -C "$api_repository" ls-files --error-unmatch facodi_api/__manifest__.py >/dev/null 2>&1; then
  echo "Refusing API source outside the tracked facodi_api addon" >&2
  exit 2
fi
printf 'API source commit: %s\n' "$(git -C "$api_repository" rev-parse HEAD)"
if [[ -n "$(git -C "$api_repository" status --porcelain -- facodi_api)" ]]; then
  echo "Refusing modified API source: use a clean commit for release acceptance" >&2
  exit 2
fi
if [[ "${1:-}" == --check-source ]]; then
  exit 0
fi

export FACODI_PROJECT_SOURCE="$api_repository/facodi_project"
if ! git -C "$api_repository" cat-file -e HEAD:facodi_project/__manifest__.py 2>/dev/null ||
   [[ -n "$(git -C "$api_repository" status --porcelain -- facodi_project)" ]]; then
  echo "Refusing untracked or modified Project source: require the same clean API owner commit" >&2
  exit 2
fi
if [[ "${1:-}" == --check-project-source ]]; then
  exit 0
fi

cd "$root"
export FACODI_LEARNING_SOURCE="$root/addons/facodi-learning/facodi_learning"
learning_repository="$root/addons/facodi-learning"
if ! git -C "$learning_repository" ls-files --error-unmatch facodi_learning/__manifest__.py >/dev/null 2>&1 ||
   [[ -n "$(git -C "$learning_repository" status --porcelain -- facodi_learning)" ]]; then
  echo "Refusing untracked or modified Learning source" >&2
  exit 2
fi
printf 'Learning source commit: %s\n' "$(git -C "$learning_repository" rev-parse HEAD)"
legacy_source="/tmp/facodi-api-e2e-legacy-$$"
mkdir -p "$legacy_source"
# The exact installed-module baseline reviewed in this delivery, never a mutable branch.
git -C "$root/addons/facodi-api" fetch --depth=1 origin d7c7579d214edbcb2e6d46a27e1f3001d266c275
git -C "$root/addons/facodi-api" archive d7c7579d214edbcb2e6d46a27e1f3001d266c275 facodi_api | tar -x -C "$legacy_source"
export FACODI_LEGACY_SOURCE="$legacy_source/facodi_api"

project="facodi-api-e2e-$(date -u +%Y%m%d%H%M%S)-$$"
export FACODI_API_SOURCE="$api_source"
export FACODI_E2E_DOCKERFILE="$root/tests/Dockerfile.api-e2e"
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
  rm -rf "$legacy_source"
  return "$status"
}
trap cleanup EXIT

"${compose[@]}" config --quiet
"${compose[@]}" build odoo
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
  --no-http
  --workers=0
  --max-cron-threads=0
  --http-interface=0.0.0.0
)
run_native_tests() {
  local native_log
  native_log="$(mktemp "${TMPDIR:-/tmp}/facodi-native-tests-XXXXXX.log")"
  if ! "${compose[@]}" run --rm -T odoo "${odoo_args[@]}" "$@" --test-enable --stop-after-init 2>&1 | tee "$native_log"; then
    echo "Native Odoo process failed; log: $native_log" >&2
    return 1
  fi
  if ! grep -Eq 'odoo.tests.result: 0 failed, 0 error\(s\) of [1-9][0-9]* tests' "$native_log"; then
    echo "Native Odoo tests failed or did not execute; log: $native_log" >&2
    return 1
  fi
  rm -f "$native_log"
}
project_database="facodi_project_e2e"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --database="$project_database" --init=project --stop-after-init
"${compose[@]}" run --rm -T odoo odoo shell "${odoo_args[@]}" --database="$project_database" <<'PY'
from pathlib import Path
exec(Path('/mnt/extra-addons/facodi_project/tests/test_preservation.py').read_text())
capture_history(env)
PY
run_native_tests --database="$project_database" --init=facodi_project --test-tags=/facodi_project
"${compose[@]}" run --rm -T odoo odoo shell "${odoo_args[@]}" --database="$project_database" <<'PY'
from odoo.addons.facodi_project.tests.test_concurrency import run_concurrency
run_concurrency(env)
PY
echo "PASS standalone Project install and identity/access/concurrency tests"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --database="$project_database" --update=facodi_project --stop-after-init
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --database="$project_database" --update=facodi_project --stop-after-init
"${compose[@]}" run --rm -T odoo odoo shell "${odoo_args[@]}" --database="$project_database" <<'PY'
from odoo.addons.facodi_project.tests.test_preservation import verify_history
verify_history(env)
PY
echo "PASS repeated standalone Project upgrade"
run_native_tests --init=facodi_api --test-tags=/facodi_api
echo "PASS clean install and native ORM security tests"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --update=facodi_api --stop-after-init
echo "PASS first upgrade"
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --update=facodi_api --stop-after-init
echo "PASS repeated upgrade"

# Prove a real old-addon -> new-addon upgrade on a separate disposable database.
legacy_database="facodi_api_upgrade_e2e"
legacy_args=(--addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/legacy-addons --database="$legacy_database" --without-demo=true --workers=0 --max-cron-threads=0)
"${compose[@]}" run --rm -T odoo "${legacy_args[@]}" --init=facodi_api --stop-after-init
"${compose[@]}" run --rm -T --entrypoint odoo odoo shell --no-http "${legacy_args[@]}" --db_host=db --db_user="$FACODI_E2E_DB_USER" --db_password="$FACODI_E2E_DB_PASSWORD" <<'LEGACY'
run = env["facodi.pipeline.run"].create({"name": "Historical run", "source_type": "manual", "raw_content": "Preserve original legacy content", "status": "published", "idempotency_key": "legacy-record", "metadata_json": '{"legacy_evidence": true}'})
env.cr.commit()
LEGACY
"${compose[@]}" run --rm -T odoo "${odoo_args[@]}" --database="$legacy_database" --update=facodi_api --stop-after-init
"${compose[@]}" run --rm -T --entrypoint odoo odoo shell --no-http "${odoo_args[@]}" --database="$legacy_database" --db_host=db --db_user="$FACODI_E2E_DB_USER" --db_password="$FACODI_E2E_DB_PASSWORD" <<'UPGRADE'
run = env["facodi.pipeline.run"].search([("idempotency_key", "=", "legacy-record")])
assert run.legacy_quarantined and run.legacy_status == "published"
assert run.status == "cancelled" and not run.published_slide_id
assert run.raw_content == "Preserve original legacy content"
assert run.metadata_json == '{"legacy_evidence": true}'
assert not env.ref("facodi_api.ir_cron_facodi_pipeline_process").active
assert env["ir.config_parameter"].get_param("facodi_api.pipeline_enabled", "false") == "false"
assert not env.ref("facodi_api.access_facodi_pipeline_run", raise_if_not_found=False)
print("PASS installed legacy database upgrade preserves evidence and quarantines unverified publication")
UPGRADE

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

learning_manifest="$FACODI_LEARNING_SOURCE/__manifest__.py"
if python3 - "$learning_manifest" <<'PY'
import ast
import sys
from pathlib import Path

manifest = ast.literal_eval(Path(sys.argv[1]).read_text())
sys.exit(0 if 'facodi_api' in manifest.get('depends', []) else 1)
PY
then
  learning_test_tags=facodi_api_consumers
  if [[ "${FACODI_LEARNING_FULL_TESTS:-0}" == "1" ]]; then
    learning_test_tags=/facodi_learning
  fi
  run_native_tests --database=facodi_learning_e2e --init=facodi_learning --test-tags="$learning_test_tags"
  echo "PASS native Learning consumer delegation, receipts and reviewed publication"
  "${compose[@]}" run --rm -T odoo odoo shell "${odoo_args[@]}" --database=facodi_learning_e2e <<'CANONICAL'
import json
from uuid import uuid4
from unittest.mock import patch
from odoo import Command

params = env['ir.config_parameter'].sudo()
params.set_param('facodi_api.pipeline_enabled', 'true')
params.set_param('facodi_api.enrichment_provider', 'baseline')
params.set_param('facodi_api.canonical_intake_enabled', 'true')
params.set_param('facodi_learning.analysis_provider', 'odoo_python')
actor = env['res.users'].create({
    'name': 'Canonical native acceptance actor', 'login': 'canonical-native-acceptance',
    'group_ids': [Command.set([env.ref('facodi_api.group_pipeline_reviewer').id])],
})
params.set_param('facodi_learning.pipeline_user_id', str(actor.id))
website = env['website'].search([('company_id', '=', env.company.id)], limit=1)
workspace = env['project.project'].create({
    'name': 'Permanent canonical acceptance workspace', 'facodi_managed': True,
    'company_id': env.company.id, 'privacy_visibility': 'employees',
})
params.set_param('facodi_api.canonical_workspace.%s' % website.id, str(workspace.id))
course = env['slide.channel'].with_user(actor).create({
    'name': 'Private canonical acceptance course', 'user_id': actor.id,
    'website_id': website.id, 'website_published': False, 'visibility': 'members', 'enroll': 'invite',
})
slide = env['slide.slide'].with_user(actor).create({
    'name': 'Native canonical acceptance evidence', 'channel_id': course.id,
    'slide_category': 'article', 'html_content': '<p>Native educational evidence remains unpublished until review.</p>',
    'is_published': False, 'website_published': False,
})
projects_before = env['project.project'].search_count([])
tasks_before = env['project.task'].search_count([])
job = slide.with_user(actor).action_facodi_request_analysis()
run = job.pipeline_run_id.with_user(actor)
assert run.execution_plane == 'supabase' and run.project_id == workspace
assert env['project.project'].search_count([]) == projects_before
assert env['project.task'].search_count([]) == tasks_before + 1
assert not run.task_id.child_ids
run.task_id.write({'name': 'Human editorial decision', 'description': 'Preserve authored work'})
catalog = json.loads(run.canonical_payload_json)['catalog_snapshot']
enriched_id = str(uuid4())
receipt = {
    'job_id': str(uuid4()), 'task_ref': run.task_id.facodi_ref, 'company_id': run.company_id.id,
    'cohort': 'p2', 'revision': 5, 'status': 'needs_review', 'attempt': 2,
    'result': {'document_data': {'text_content': run.raw_content, 'language': run.language},
               'enriched_data': {'id': enriched_id, 'summary': run.raw_content, 'keywords': [], 'concepts': [],
                                 'provider_name': 'baseline-deterministic', 'model_name': 'regex-frequency-v2-evidence'},
               'mapping_data': {'id': str(uuid4()), 'enriched_document_id': enriched_id,
                                'snapshot_id': catalog['snapshot_id'], 'snapshot_hash': catalog['snapshot_hash'],
                                'ranking_algorithm_version': 'deterministic-v2', 'candidates': [],
                                'unmatched_concepts': [], 'schema_version': '2.0.0'},
               'chunks': []},
}
failed = dict(receipt, revision=2, status='failed', attempt=1, result={'error_code': 'PROVIDER_FAILED'})
assert run._apply_canonical_receipt(failed)
assert job.state == 'failed' and len(job.attempt_ids) == 1
failed_attempt = job.attempt_ids
accepted_input = run.canonical_payload_json
retry_revision = run.revision
with patch.object(type(run), '_call_canonical_boundary', side_effect=AssertionError('No precommit network')):
  job.with_user(actor).action_retry()
  assert run.action_retry(expected_revision=retry_revision)
retry_intent = json.loads(run.canonical_command_json)
assert job.state == 'pending' and run.attempt_count == 1 and len(job.attempt_ids) == 1

def retry_ack(record, payload):
  assert record.id == run.id and payload['action'] == 'retry'
  assert payload['job_id'] == receipt['job_id'] and payload['command_id'] == retry_intent['command_id']
  assert payload['expected_revision'] == 0
  return {'command_id': retry_intent['command_id'], 'command_revision': 1,
      'receipt': dict(failed, revision=3, status='queued', result={})}

with patch.object(type(run), '_call_canonical_boundary', retry_ack):
  assert run._dispatch_canonical_receipts()
assert not run.canonical_command_json and run.canonical_command_revision == 1
assert run.action_retry(expected_revision=retry_revision) and not run.canonical_command_json
assert run.canonical_job_id == receipt['job_id'] and run.canonical_payload_json == accepted_input
assert run._apply_canonical_receipt(receipt)
assert not run._apply_canonical_receipt(receipt)
assert json.loads(run.metadata_json)['mapping_data'] == receipt['result']['mapping_data']
job.with_user(actor).action_process()
assert job.state == 'completed' and job.result_id.summary
assert job.result_id.raw_payload['mapping_data'] == receipt['result']['mapping_data']
assert job.pipeline_receipt_revision == run.revision
assert len(job.attempt_ids) == 2 and len(slide.facodi_analysis_result_ids) == 1
assert failed_attempt.state == 'failed' and failed_attempt.number == 1
assert not slide.is_published and not slide.website_published and not course.website_published
assert run.task_id.name == 'Human editorial decision'
assert run.task_id.description == '<p>Preserve authored work</p>'
assert run.task_id.facodi_external_ref == receipt['job_id']
historical_result = job.result_id
historical_payload = json.dumps(historical_result.raw_payload, sort_keys=True)
cancel_revision = run.revision
with patch.object(type(run), '_call_canonical_boundary', side_effect=AssertionError('No precommit network')):
  assert job.with_user(actor).action_cancel(expected_revision=cancel_revision)
  assert job.with_user(actor).action_cancel(expected_revision=cancel_revision)
intent = json.loads(run.canonical_command_json)
assert job.state == 'cancelled' and run.status == 'cancelled'
assert not run._apply_canonical_receipt(receipt)

def cancellation_ack(record, payload):
  assert record.id == run.id and payload['action'] == 'cancel'
  assert payload['job_id'] == receipt['job_id'] and payload['command_id'] == intent['command_id']
  assert payload['expected_revision'] == 1
  return {'command_id': intent['command_id'], 'command_revision': 2,
      'receipt': dict(receipt, revision=6, status='cancelled',
              result={'error_code': 'CANCELLED_BY_OPERATOR'})}

with patch.object(type(run), '_call_canonical_boundary', cancellation_ack):
  assert run._dispatch_canonical_receipts()
  assert not run._dispatch_canonical_receipts()
assert not run.canonical_command_json and run.canonical_command_revision == 2
assert historical_result.exists() and json.dumps(historical_result.raw_payload, sort_keys=True) == historical_payload
assert len(job.attempt_ids) == 2 and len(slide.facodi_analysis_result_ids) == 1
assert run.task_id.name == 'Human editorial decision'
assert run.task_id.description == '<p>Preserve authored work</p>'
assert run.task_id.facodi_external_ref == receipt['job_id']
assert not slide.is_published and not course.website_published
env.cr.rollback()
print('PASS canonical native Learning projection, terminal replay and unpublished human work')
print('PASS versioned canonical retry, stable job/input/task and immutable failed attempt history')
print('PASS versioned canonical cancellation, immutable editorial history and human task preservation')
CANONICAL
else
  echo "NOT_EXECUTED Learning API consumers: pinned Learning release has no API dependency"
fi

echo "PASS isolated Odoo HTTP health at http://$("${compose[@]}" port odoo 8069)"