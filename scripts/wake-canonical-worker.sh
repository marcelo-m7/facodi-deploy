#!/usr/bin/env bash
set -euo pipefail

if [[ "${FACODI_CANONICAL_WORKER_ENABLED:-false}" != "true" ]]; then
  printf '%s\n' 'Canonical worker wake disabled.'
  exit 0
fi

if [[ "${SUPABASE_URL:-}" != "https://bhfywztfyidvrlarebmg.supabase.co" ||
      ! "${SUPABASE_SECRET_KEY:-}" =~ ^sb_secret_[A-Za-z0-9_-]+$ ]]; then
  printf '%s\n' 'Canonical worker target/key configuration rejected.' >&2
  exit 2
fi

status=$(printf 'header = "apikey: %s"\n' "$SUPABASE_SECRET_KEY" |
  curl --disable --config - --silent --show-error --noproxy '*' \
    --proto '=https' --max-redirs 0 --connect-timeout 10 --max-time 100 \
    --max-filesize 65536 --request POST --header 'Content-Type: application/json' \
    --data '{}' --output /dev/null --write-out '%{http_code}' \
    --url 'https://bhfywztfyidvrlarebmg.supabase.co/functions/v1/v4_canonical_analysis/work')

if [[ "$status" != "200" ]]; then
  printf '%s\n' 'Canonical worker wake failed.' >&2
  exit 1
fi
printf '%s\n' 'Canonical worker wake accepted.'