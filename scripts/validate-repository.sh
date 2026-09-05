#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

test -f .gitmodules
for manifest in \
  addons/facodi-learning/facodi_learning/__manifest__.py \
  addons/facodi-theme/theme_facodi/__manifest__.py \
  addons/monynha-odoo/theme_monynha/__manifest__.py \
  addons/monynha-odoo/monynha_lead_generator/__manifest__.py \
  vendor/odoo-design-themes/theme_common/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

test "$(git -C addons/facodi-learning rev-parse HEAD)" = "c0d66e3d5ee412dddf89e4a9ad64ec2ab6fd9e18"
test "$(git -C addons/facodi-theme rev-parse HEAD)" = "be35673a5649f5e6f7b01777905d0899e3daaf7b"
test "$(git -C addons/monynha-odoo rev-parse HEAD)" = "96c03e92a54ca9ca4e4f32a1307fd9bba36949ce"
test "$(git -C vendor/odoo-design-themes rev-parse HEAD)" = "a1818df4ade65406c0cacae8b1ea676e6f70095f"

python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh
bash tests/test_entrypoint.sh
