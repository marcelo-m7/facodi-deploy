#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

project="${1:?Pass the existing disposable Compose project name}"
compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file .env.ci
  -f deploy/coolify/docker-compose.yml
  -f tests/docker-compose.ci.yml
)

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmpdir"
}
trap cleanup EXIT

wait_for_odoo() {
  local container_id state
  for _ in {1..90}; do
    container_id="$("${compose[@]}" ps -q odoo)"
    if [[ -n "$container_id" ]]; then
      state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
      [[ "$state" == "healthy" ]] && return 0
      [[ "$state" == "unhealthy" || "$state" == "exited" || "$state" == "dead" ]] && return 1
    fi
    sleep 2
  done
  return 1
}

odoo_id="$("${compose[@]}" ps -q odoo)"
db_id="$("${compose[@]}" ps -q db)"
[[ -n "$odoo_id" && -n "$db_id" ]] || {
  echo "Paired backup/restore proof requires running db and odoo services" >&2
  exit 1
}

odoo_volume="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/odoo"}}{{.Name}}{{end}}{{end}}' "$odoo_id")"
odoo_image="$(docker inspect -f '{{.Config.Image}}' "$odoo_id")"
[[ -n "$odoo_volume" && -n "$odoo_image" ]] || {
  echo "Could not resolve Odoo image/volume for backup proof" >&2
  exit 1
}

echo "[backup-restore] seed representative persistent records"
"${compose[@]}" exec -T odoo bash -lc \
  'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"' <<'PY'
import base64

course = env["slide.channel"].search(
    [("name", "=", "FACODI Runtime Curriculum Course")],
    limit=1,
)
if not course:
    raise RuntimeError("Runtime curriculum course is missing before backup proof")

slide = env["slide.slide"].search(
    [
        ("channel_id", "=", course.id),
        ("name", "=", "FACODI Runtime Public Module Item"),
    ],
    limit=1,
)
if not slide:
    raise RuntimeError("Runtime public module item is missing before backup proof")

partner = env["res.partner"].create(
    {
        "name": "FACODI Backup Restore Learner",
        "email": "backup-restore-ci@invalid.facodi.test",
    }
)

progress_vals = {
    "slide_id": slide.id,
    "partner_id": partner.id,
}
if "completed" in env["slide.slide.partner"]._fields:
    progress_vals["completed"] = True
progress = env["slide.slide.partner"].create(progress_vals)

attachment = env["ir.attachment"].create(
    {
        "name": "facodi-backup-restore-sentinel.txt",
        "datas": base64.b64encode(b"FACODI_BACKUP_RESTORE_SENTINEL"),
        "mimetype": "text/plain",
        "res_model": "slide.channel",
        "res_id": course.id,
    }
)
if not attachment.store_fname:
    raise RuntimeError("Backup/restore sentinel attachment was not stored in filestore")

curriculum = env["facodi.learning.curriculum.reference"].search(
    [
        ("provider", "=", "ualg"),
        ("external_id", "=", "ualg-1941-2026-27"),
    ],
    limit=1,
)
if not curriculum or curriculum.state != "validated" or not curriculum.website_published:
    raise RuntimeError("Reviewed LESTI curriculum history is missing before backup proof")

page = env["website.page"].search(
    [("url", "in", ["/about", "/"])],
    order="id",
    limit=1,
)
if not page:
    raise RuntimeError("Representative Website page is missing before backup proof")

env["ir.config_parameter"].sudo().set_param(
    "facodi_ci.backup_restore.course_name",
    course.name,
)
env["ir.config_parameter"].sudo().set_param(
    "facodi_ci.backup_restore.page_id",
    str(page.id),
)
env["ir.config_parameter"].sudo().set_param(
    "facodi_ci.backup_restore.progress_id",
    str(progress.id),
)
env["ir.config_parameter"].sudo().set_param(
    "facodi_ci.backup_restore.partner_id",
    str(partner.id),
)
env["ir.config_parameter"].sudo().set_param(
    "facodi_ci.backup_restore.attachment_id",
    str(attachment.id),
)
env.cr.commit()
PY

"${compose[@]}" exec -T odoo sh -lc \
  'printf "%s\n" FACODI_BACKUP_RESTORE_VOLUME_SENTINEL > /var/lib/odoo/facodi-ci-paired-backup-sentinel'

echo "[backup-restore] quiesce Odoo and capture matched PostgreSQL + odoo-data pair"
"${compose[@]}" stop odoo >/dev/null

"${compose[@]}" exec -T db pg_dump -U odoo -d facodi -Fc > "$tmpdir/facodi.dump"
[[ -s "$tmpdir/facodi.dump" ]] || {
  echo "PostgreSQL backup is empty" >&2
  exit 1
}

docker run --rm \
  --entrypoint sh \
  -v "$odoo_volume:/var/lib/odoo:ro" \
  "$odoo_image" \
  -c 'tar -C /var/lib/odoo -czf - .' > "$tmpdir/odoo-data.tgz"
[[ -s "$tmpdir/odoo-data.tgz" ]] || {
  echo "odoo-data backup is empty" >&2
  exit 1
}

echo "[backup-restore] restart and deliberately mutate both persistence layers"
"${compose[@]}" up -d odoo
wait_for_odoo || {
  echo "Odoo did not recover after backup capture" >&2
  exit 1
}

"${compose[@]}" exec -T odoo bash -lc \
  'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"' <<'PY'
course = env["slide.channel"].search(
    [("name", "=", "FACODI Runtime Curriculum Course")],
    limit=1,
)
if not course:
    raise RuntimeError("Backup proof course vanished before mutation")

attachment_id = int(
    env["ir.config_parameter"].sudo().get_param(
        "facodi_ci.backup_restore.attachment_id"
    )
)
progress_id = int(
    env["ir.config_parameter"].sudo().get_param(
        "facodi_ci.backup_restore.progress_id"
    )
)

env["ir.attachment"].browse(attachment_id).unlink()
env["slide.slide.partner"].browse(progress_id).unlink()
course.write({"name": "FACODI MUTATED AFTER BACKUP"})
env.cr.commit()
PY
"${compose[@]}" exec -T odoo rm -f /var/lib/odoo/facodi-ci-paired-backup-sentinel

echo "[backup-restore] restore the matched pair into the disposable runtime"
"${compose[@]}" stop odoo >/dev/null
"${compose[@]}" exec -T db dropdb -U odoo --if-exists facodi
"${compose[@]}" exec -T db createdb -U odoo facodi
cat "$tmpdir/facodi.dump" | "${compose[@]}" exec -T db \
  pg_restore -U odoo -d facodi --no-owner --no-privileges

docker run --rm \
  --entrypoint sh \
  -v "$odoo_volume:/var/lib/odoo" \
  "$odoo_image" \
  -c 'find /var/lib/odoo -mindepth 1 -maxdepth 1 -exec rm -rf {} +'
cat "$tmpdir/odoo-data.tgz" | docker run --rm -i \
  --entrypoint sh \
  -v "$odoo_volume:/var/lib/odoo" \
  "$odoo_image" \
  -c 'tar -C /var/lib/odoo -xzf -'

# A restored database/filestore pair must still pass the canonical idempotent
# migration gate before serving traffic.
"${compose[@]}" run --rm migrate
"${compose[@]}" up -d odoo
wait_for_odoo || {
  echo "Odoo did not become healthy after paired restore" >&2
  exit 1
}

echo "[backup-restore] verify Website, course, progress, curriculum history and attachment"
"${compose[@]}" exec -T odoo bash -lc \
  'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"' <<'PY'
import base64

params = env["ir.config_parameter"].sudo()
course_name = params.get_param("facodi_ci.backup_restore.course_name")
page_id = int(params.get_param("facodi_ci.backup_restore.page_id"))
progress_id = int(params.get_param("facodi_ci.backup_restore.progress_id"))
attachment_id = int(params.get_param("facodi_ci.backup_restore.attachment_id"))

course = env["slide.channel"].search([("name", "=", course_name)], limit=1)
if not course:
    raise RuntimeError("Course state was not restored")

page = env["website.page"].browse(page_id).exists()
if not page:
    raise RuntimeError("Website page state was not restored")

progress = env["slide.slide.partner"].browse(progress_id).exists()
if not progress:
    raise RuntimeError("Learner progress state was not restored")
if "completed" in progress._fields and not progress.completed:
    raise RuntimeError("Learner completion state was not restored")

attachment = env["ir.attachment"].browse(attachment_id).exists()
if not attachment:
    raise RuntimeError("Attachment row was not restored")
if base64.b64decode(attachment.datas or b"") != b"FACODI_BACKUP_RESTORE_SENTINEL":
    raise RuntimeError("Attachment filestore payload was not restored")

curriculum = env["facodi.learning.curriculum.reference"].search(
    [
        ("provider", "=", "ualg"),
        ("external_id", "=", "ualg-1941-2026-27"),
    ],
    limit=1,
)
if not curriculum or curriculum.state != "validated" or not curriculum.website_published:
    raise RuntimeError("Curriculum review history was not restored")

print("PASS paired restore preserved Website page")
print("PASS paired restore preserved course and learner progress")
print("PASS paired restore preserved curriculum review history")
print("PASS paired restore preserved attachment database row and filestore payload")
PY

volume_sentinel="$("${compose[@]}" exec -T odoo cat /var/lib/odoo/facodi-ci-paired-backup-sentinel)"
[[ "$volume_sentinel" == "FACODI_BACKUP_RESTORE_VOLUME_SENTINEL" ]] || {
  echo "odoo-data volume sentinel was not restored" >&2
  exit 1
}

echo "PASS matched PostgreSQL + odoo-data backup/restore round-trip"
