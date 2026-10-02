#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

test -f .gitmodules
for manifest in \
  addons/facodi-ai/facodi_ai/__manifest__.py \
  addons/facodi-ai/facodi_ai_learning/__manifest__.py \
  addons/facodi-ai/facodi_ai_website/__manifest__.py \
  addons/facodi-learning/facodi_learning/__manifest__.py \
  addons/facodi-theme/theme_facodi/__manifest__.py \
  addons/muk_web_theme-19.0.1.4.9/muk_web_theme/__manifest__.py \
  addons/monodoo/monodoo_core/__manifest__.py \
  addons/monodoo/monodoo_home/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

# The gitlinks recorded by the superproject are the authoritative integration
# pins. Avoid duplicating mutable SHAs in this shell gate; the repository
# contract below verifies every checked-out submodule against its exact gitlink.
python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh tests/test_coolify_runtime.sh
bash tests/test_entrypoint.sh
