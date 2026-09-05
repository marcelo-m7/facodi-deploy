#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${DB_PORT:=5432}"
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${ODOO_DB:?ODOO_DB is required}"
: "${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD is required}"
: "${FACODI_MODULES:=facodi_learning,website_facodi}"

export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$DB_USER"
export PGPASSWORD="$DB_PASSWORD"
export PGDATABASE="$ODOO_DB"

wait-for-psql.py --timeout=60

common=("--database=${ODOO_DB}" "--admin-passwd=${ODOO_ADMIN_PASSWD}")

case "${1:-serve}" in
  serve)
    exec odoo \
      "${common[@]}" \
      "--http-port=${PORT}" \
      --proxy-mode \
      --workers=0 \
      --max-cron-threads=1
    ;;
  migrate)
    if psql -Atqc "select to_regclass('public.ir_module_module') is not null" | grep -qx t; then
      exec odoo "${common[@]}" --stop-after-init "--update=${FACODI_MODULES}"
    else
      exec odoo "${common[@]}" --stop-after-init "--init=base,${FACODI_MODULES}"
    fi
    ;;
  *)
    echo "usage: $0 {serve|migrate}" >&2
    exit 64
    ;;
esac
