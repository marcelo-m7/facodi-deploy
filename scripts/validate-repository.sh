#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

test -f .gitmodules
for manifest in addons/facodi-learning/facodi_learning/__manifest__.py addons/facodi-theme/website_facodi/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

python3 -m unittest tests/test_repository_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh
bash tests/test_entrypoint.sh
