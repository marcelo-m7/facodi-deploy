#!/usr/bin/env bash
set -euo pipefail

: "${PORT:=8080}"
: "${DB_PORT:=5432}"
: "${DB_HOST:?DB_HOST is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${ODOO_DB:?ODOO_DB is required}"
: "${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD is required}"
: "${FACODI_MODULES:=facodi_learning,theme_facodi,facodi_ai,facodi_ai_website,monodoo_backend}"
: "${ODOO_CONFIG_TEMPLATE:=/etc/odoo/odoo.conf}"
: "${ODOO_WORKERS:=2}"
: "${ODOO_MAX_CRON_THREADS:=1}"
: "${ODOO_GEVENT_PORT:=8072}"

case "$ODOO_ADMIN_PASSWD" in
  *$'\n'*|*$'\r'*)
    echo "ODOO_ADMIN_PASSWD must be a single-line value" >&2
    exit 64
    ;;
esac

if ! [[ "$ODOO_WORKERS" =~ ^[0-9]+$ ]]; then
  echo "ODOO_WORKERS must be a non-negative integer" >&2
  exit 64
fi
if ! [[ "$ODOO_MAX_CRON_THREADS" =~ ^[0-9]+$ ]]; then
  echo "ODOO_MAX_CRON_THREADS must be a non-negative integer" >&2
  exit 64
fi
if ! [[ "$ODOO_GEVENT_PORT" =~ ^[0-9]+$ ]]; then
  echo "ODOO_GEVENT_PORT must be a non-negative integer" >&2
  exit 64
fi

umask 077
odoo_config="$(mktemp)"
cp "$ODOO_CONFIG_TEMPLATE" "$odoo_config"
printf '\nadmin_passwd = %s\n' "$ODOO_ADMIN_PASSWD" >>"$odoo_config"

export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$DB_USER"
export PGPASSWORD="$DB_PASSWORD"
export PGDATABASE="$ODOO_DB"

wait-for-psql.py --timeout=60

common=("server" "--config=${odoo_config}" "--database=${ODOO_DB}")

case "${1:-serve}" in
  serve)
    exec odoo \
      "${common[@]}" \
      "--http-port=${PORT}" \
      "--gevent-port=${ODOO_GEVENT_PORT}" \
      "--db-filter=^${ODOO_DB}$" \
      --no-database-list \
      --proxy-mode \
      "--workers=${ODOO_WORKERS}" \
      "--max-cron-threads=${ODOO_MAX_CRON_THREADS}"
    ;;
  migrate)
    exec python3 /usr/local/lib/facodi/migrate.py \
      --config "$odoo_config" \
      --database "$ODOO_DB" \
      --modules "$FACODI_MODULES"
    ;;
  *)
    echo "usage: $0 {serve|migrate}" >&2
    exit 64
    ;;
esac
