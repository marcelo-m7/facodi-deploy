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
test "${1:-}" = server
config_path=""
for argument in "$@"; do
	case "$argument" in
		--config=*) config_path="${argument#--config=}" ;;
	esac
done
test -n "$config_path"
grep -Fxq 'admin_passwd = test-admin' "$config_path"
printf 'PORT=%s PGPORT=%s args=%s\n' "$PORT" "$PGPORT" "$*"
SH
cat >"$tmp/python3" <<'SH'
#!/usr/bin/env bash
printf 'python3 %s\n' "$*"
SH
chmod +x "$tmp/wait-for-psql.py" "$tmp/psql" "$tmp/odoo" "$tmp/python3"
printf '[options]\naddons_path = /mnt/extra-addons\n' >"$tmp/odoo.conf"

common_env=(
  PORT=8080
  DB_HOST=/cloudsql/marcelo-497411:europe-southwest1:facodi-staging-pg
  DB_PORT=5432
  DB_USER=odoo
  DB_PASSWORD=test-password
  ODOO_DB=facodi_staging
  ODOO_ADMIN_PASSWD=test-admin
  ODOO_CONFIG_TEMPLATE="$tmp/odoo.conf"
  FACODI_MODULES=facodi_learning,theme_facodi
)

env PATH="$tmp:$PATH" "${common_env[@]}" \
  bash "$root/docker/entrypoint.sh" serve >"$tmp/output"

grep -q 'PORT=8080 PGPORT=5432' "$tmp/output"
grep -q -- '^PORT=.*args=server ' "$tmp/output"
grep -q -- '--http-port=8080' "$tmp/output"
! grep -q -- '--db_port=8080' "$tmp/output"
grep -Fq -- '--db-filter=^facodi_staging$' "$tmp/output"
grep -q -- '--no-database-list' "$tmp/output"

env PATH="$tmp:$PATH" "${common_env[@]}" \
  bash "$root/docker/entrypoint.sh" migrate >"$tmp/migrate-output"

grep -Fq '/usr/local/lib/facodi/migrate.py' "$tmp/migrate-output"
grep -Fq -- '--database facodi_staging' "$tmp/migrate-output"
grep -Fq -- '--modules facodi_learning,theme_facodi' "$tmp/migrate-output"
