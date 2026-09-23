#!/usr/bin/env bash
set -euo pipefail

: "${ODOO_ADMIN_PASSWD:?ODOO_ADMIN_PASSWD is required}"
: "${ODOO_ADDONS_PATH:?ODOO_ADDONS_PATH is required}"
: "${DB_HOST:?DB_HOST is required}"
: "${DB_PORT:?DB_PORT is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${ODOO_DB:?ODOO_DB is required}"
: "${ODOO_DATA_DIR:?ODOO_DATA_DIR is required}"
: "${ODOO_HTTP_PORT:?ODOO_HTTP_PORT is required}"
: "${ODOO_WORKERS:?ODOO_WORKERS is required}"
: "${ODOO_MAX_CRON_THREADS:?ODOO_MAX_CRON_THREADS is required}"
: "${ODOO_DEV_MODE:?ODOO_DEV_MODE is required}"

case "$ODOO_ADMIN_PASSWD" in
  *$'\n'*|*$'\r'*)
    echo "ODOO_ADMIN_PASSWD must be a single-line value" >&2
    exit 64
    ;;
esac

umask 077
odoo_config="$(mktemp)"
printf '%s\n' \
  '[options]' \
  "admin_passwd = $ODOO_ADMIN_PASSWD" \
  "addons_path = $ODOO_ADDONS_PATH" \
  "db_host = $DB_HOST" \
  "db_port = $DB_PORT" \
  "db_user = $DB_USER" \
  "db_password = $DB_PASSWORD" \
  "db_name = $ODOO_DB" \
  "data_dir = $ODOO_DATA_DIR" \
  "http_port = $ODOO_HTTP_PORT" \
  "workers = $ODOO_WORKERS" \
  "max_cron_threads = $ODOO_MAX_CRON_THREADS" \
  "dev_mode = $ODOO_DEV_MODE" >"$odoo_config"

command=server
if [[ "${1:-}" == "shell" ]]; then
  command=shell
  shift
fi

exec /opt/facodi-venv/bin/python3 /opt/odoo/odoo-bin \
  "--addons-path=${ODOO_ADDONS_PATH}" \
  "$command" \
  "--config=${odoo_config}" \
  "$@"