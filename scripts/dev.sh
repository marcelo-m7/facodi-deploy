#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$root/.env.dev"
compose=(docker compose --env-file "$env_file" -f "$root/docker-compose.dev.yml")
modules="facodi_learning,theme_facodi,facodi_ai,facodi_ai_website"

if [[ ! -f "$env_file" ]]; then
  echo "missing $env_file; copy .env.dev.example and set local values" >&2
  exit 64
fi

case "${1:-}" in
  up)
    exec "${compose[@]}" up --build
    ;;
  init)
    "${compose[@]}" up -d db
    exec "${compose[@]}" run --rm --no-deps odoo --stop-after-init "--init=${modules}" --without-demo=True
    ;;
  update)
    update_modules="${2:-$modules}"
    "${compose[@]}" up -d db
    exec "${compose[@]}" run --rm --no-deps odoo --stop-after-init "--update=${update_modules}"
    ;;
  shell)
    "${compose[@]}" up -d db
    exec "${compose[@]}" run --rm --no-deps odoo shell
    ;;
  down)
    exec "${compose[@]}" down
    ;;
  *)
    echo "usage: $0 {up|init|update [modules]|shell|down}" >&2
    exit 64
    ;;
esac