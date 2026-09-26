#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

project="${1:?compose project name is required}"
compose=(
  docker compose
  --project-name "$project"
  --project-directory "$root"
  --env-file .env.ci
  -f deploy/coolify/docker-compose.yml
  -f tests/docker-compose.ci.yml
)

d2_state="$("${compose[@]}" exec -T odoo bash -lc   'odoo shell --db_host="$DB_HOST" --db_port="$DB_PORT" --db_user="$DB_USER" --db_password="$DB_PASSWORD" -d "$ODOO_DB"'   < tests/ci_seed_d2_editorial_runtime.py 2>&1)"

echo "$d2_state"
d2_about_route="$(sed -n 's/^FACODI_D2_ABOUT=//p' <<<"$d2_state")"
d2_contribution_route="$(sed -n 's/^FACODI_D2_CONTRIBUTION=//p' <<<"$d2_state")"
d2_policy_route="$(sed -n 's/^FACODI_D2_POLICY=//p' <<<"$d2_state")"
d2_rich_post_route="$(sed -n 's/^FACODI_D2_RICH_POST=//p' <<<"$d2_state")"
d2_sparse_post_route="$(sed -n 's/^FACODI_D2_SPARSE_POST=//p' <<<"$d2_state")"

for required_route in   "$d2_about_route"   "$d2_contribution_route"   "$d2_policy_route"   "$d2_rich_post_route"   "$d2_sparse_post_route"; do
  if [[ -z "$required_route" ]]; then
    echo "D2 disposable editorial fixture route is missing" >&2
    exit 1
  fi
done

"${compose[@]}" exec -T   -e "D2_ABOUT_ROUTE=$d2_about_route"   -e "D2_CONTRIBUTION_ROUTE=$d2_contribution_route"   -e "D2_POLICY_ROUTE=$d2_policy_route"   -e "D2_RICH_POST_ROUTE=$d2_rich_post_route"   -e "D2_SPARSE_POST_ROUTE=$d2_sparse_post_route"   odoo python3 - <<'PY'
import os
import urllib.request

base = "http://127.0.0.1:8069"
checks = {
    os.environ["D2_ABOUT_ROUTE"]: [
        b"facodi-project-story",
        b"facodi-principles-ledger",
        b"facodi-process-timeline",
    ],
    os.environ["D2_CONTRIBUTION_ROUTE"]: [
        b"facodi-contribution-board",
        b"facodi-process-timeline",
    ],
    os.environ["D2_POLICY_ROUTE"]: [
        b"facodi-policy-document",
        b"FACODI_D2_POLICY_LONG_CODE_TOKEN",
    ],
    "/blog": [
        b"facodi-blog-index",
        b"facodi-bulletin-hero",
        b"facodi-bulletin-card",
    ],
    os.environ["D2_RICH_POST_ROUTE"]: [
        b"facodi-blog-article",
        b"facodi-blog-prose",
        b"A real D2 deployment subtitle",
    ],
    os.environ["D2_SPARSE_POST_ROUTE"]: [
        b"facodi-blog-article",
        b"facodi-blog-prose",
        b"Sparse deployment article body.",
    ],
    "/contactus": [
        b"facodi-contact-page",
        b"facodi-contact-form-sheet",
        b"facodi-contact-context",
        b'id="contactus_form"',
        b'action="/website/form/"',
    ],
}
for route, markers in checks.items():
    response = urllib.request.urlopen(base + route, timeout=15)
    body = response.read()
    if response.status != 200:
        raise RuntimeError(f"{route} returned HTTP {response.status}")
    for marker in markers:
        if marker not in body:
            raise RuntimeError(f"{route} missing D2 marker {marker!r}")
    print(f"PASS D2 HTTP {route}")
PY

if [[ "${FACODI_BROWSER_ACCEPTANCE:-0}" == "1" ]]; then
  : "${FACODI_BROWSER_CHROME_BIN:?FACODI_BROWSER_CHROME_BIN is required}"
  : "${FACODI_D2_BROWSER_SCREENSHOT_DIR:?FACODI_D2_BROWSER_SCREENSHOT_DIR is required}"
  FACODI_BROWSER_BASE_URL="http://127.0.0.1:8069"   FACODI_D2_ABOUT_ROUTE="$d2_about_route"   FACODI_D2_CONTRIBUTION_ROUTE="$d2_contribution_route"   FACODI_D2_POLICY_ROUTE="$d2_policy_route"   FACODI_D2_RICH_POST_ROUTE="$d2_rich_post_route"   FACODI_D2_SPARSE_POST_ROUTE="$d2_sparse_post_route"   FACODI_BROWSER_CHROME_BIN="$FACODI_BROWSER_CHROME_BIN"   FACODI_D2_BROWSER_SCREENSHOT_DIR="$FACODI_D2_BROWSER_SCREENSHOT_DIR"     node tests/test_d2_editorial_browser.mjs
fi

echo "PASS: D2 disposable editorial runtime"
