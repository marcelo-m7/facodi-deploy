#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/wait-for-psql.py" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$tmp/psql" <<'SH'
#!/usr/bin/env bash
printf 't\n'
SH
cat >"$tmp/odoo" <<'SH'
#!/usr/bin/env bash
printf 'PORT=%s PGPORT=%s args=%s\n' "$PORT" "$PGPORT" "$*"
SH
chmod +x "$tmp/wait-for-psql.py" "$tmp/psql" "$tmp/odoo"

PATH="$tmp:$PATH" \
PORT=8080 \
DB_HOST=/cloudsql/marcelo-497411:europe-southwest1:facodi-staging-pg \
DB_PORT=5432 \
DB_USER=odoo \
DB_PASSWORD=test-password \
ODOO_DB=facodi_staging \
ODOO_ADMIN_PASSWD=test-admin \
FACODI_MODULES=facodi_learning,website_facodi \
bash "$root/docker/entrypoint.sh" serve >"$tmp/output"

grep -q 'PORT=8080 PGPORT=5432' "$tmp/output"
grep -q -- '--http-port=8080' "$tmp/output"
! grep -q -- '--db_port=8080' "$tmp/output"
