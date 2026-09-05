#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

test -f .gitmodules
for manifest in \
  addons/facodi-ai/facodi_ai/__manifest__.py \
  addons/facodi-ai/facodi_ai_website/__manifest__.py \
  addons/facodi-learning/facodi_learning/__manifest__.py \
  addons/facodi-theme/theme_facodi/__manifest__.py \
  addons/monodoo/monodoo_core/__manifest__.py \
  addons/monodoo/monodoo_home/__manifest__.py \
  addons/monynha-odoo/theme_monynha/__manifest__.py \
  addons/monynha-odoo/monynha_content/__manifest__.py \
  addons/monynha-odoo/monynha_lead_generator/__manifest__.py \
  vendor/odoo-design-themes/theme_common/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

# The gitlinks recorded by the superproject are the authoritative integration
# pins. Avoid duplicating mutable SHAs in this shell gate; the repository
# contract below verifies every checked-out submodule against its exact gitlink.
python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh
bash tests/test_entrypoint.sh
