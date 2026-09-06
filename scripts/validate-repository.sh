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

test "$(git -C addons/facodi-ai rev-parse HEAD)" = "f4c6bbc5cdffd5e4db8b022f43258e363bd7a25b"
test "$(git -C addons/facodi-learning rev-parse HEAD)" = "1ff81c0585728037dfb24b3310d5905ce38c6fc7"
test "$(git -C addons/facodi-theme rev-parse HEAD)" = "9b7903d32a423cb71f9b324d26817bfbc0f9272e"
test "$(git -C addons/monodoo rev-parse HEAD)" = "f96b63696a9ebabb7fcc8c2ef4a17767de0af821"
test "$(git -C addons/monynha-odoo rev-parse HEAD)" = "bc956459e61a82966c0027c14a5833b9df1738a8"
test "$(git -C vendor/odoo-design-themes rev-parse HEAD)" = "a1818df4ade65406c0cacae8b1ea676e6f70095f"

python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh
bash tests/test_entrypoint.sh
