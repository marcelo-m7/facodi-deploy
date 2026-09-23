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
  addons/monodoo/monodoo_theme/__manifest__.py \
  addons/monodoo/monodoo_appsbar/__manifest__.py \
  addons/monynha-odoo/theme_monynha/__manifest__.py \
  addons/monynha-odoo/monynha_content/__manifest__.py \
  addons/monynha-odoo/monynha_lead_generator/__manifest__.py \
  vendor/odoo-design-themes/theme_common/__manifest__.py; do
  test -f "$manifest" || { echo "missing Odoo manifest: $manifest" >&2; exit 1; }
done

for path in \
  supabase/facodi-processing-plane/README.md \
  supabase/facodi-processing-plane/supabase/config.toml \
  supabase/facodi-processing-plane/docs/adr/ADR-001-processing-plane-boundary.md \
  supabase/facodi-processing-plane/docs/live-function-inventory.md \
  supabase/facodi-processing-plane/snapshots/live-open2/functions/v2_process_video_pipeline.json \
  supabase/facodi-processing-plane/snapshots/live-open2/functions/v2_sync_object_to_odoo.json \
  supabase/facodi-processing-plane/snapshots/live-open2/functions/v2_push_odoo_learning_object.json \
  supabase/facodi-processing-plane/supabase/functions/v2_process_video_pipeline/index.ts \
  supabase/facodi-processing-plane/supabase/functions/v2_sync_object_to_odoo/index.ts \
  supabase/facodi-processing-plane/supabase/functions/v2_push_odoo_learning_object/index.ts; do
  test -f "$path" || { echo "missing processing-plane source: $path" >&2; exit 1; }
done

# The gitlinks recorded by the superproject are the authoritative integration
# pins. Avoid duplicating mutable SHAs in this shell gate; the repository
# contract below verifies every checked-out submodule against its exact gitlink.
python3 -m unittest tests/test_repository_contract.py tests/test_migration_contract.py -v
bash -n docker/entrypoint.sh scripts/*.sh tests/test_coolify_runtime.sh
bash tests/test_entrypoint.sh
