#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:-${FACODI_IMAGE:-}}"

if [[ -z "$image_ref" ]]; then
  echo "FACODI image reference is required" >&2
  exit 2
fi

if [[ "$image_ref" =~ ^ghcr\.io/[a-z0-9._/-]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "PASS immutable FACODI release image: $image_ref"
  exit 0
fi

echo "Production/staging FACODI_IMAGE must be an immutable GHCR digest reference." >&2
echo "Expected: ghcr.io/<owner>/facodi-odoo@sha256:<64-hex-digest>" >&2
exit 1
