#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: scripts/verify-runtime.sh staging|production IMAGE_URI}"
expected_image="${2:?usage: scripts/verify-runtime.sh staging|production IMAGE_URI}"
case "$env_name" in
  staging|production) ;;
  *) echo "environment must be staging or production" >&2; exit 64 ;;
esac

project="${GCP_PROJECT_ID:-marcelo-497411}"
region="${GCP_REGION:-europe-southwest1}"
service="facodi-${env_name}"
expected_sa="facodi-${env_name}-runtime@${project}.iam.gserviceaccount.com"
expected_db="${project}:${region}:facodi-${env_name}-pg"
expected_bucket="${project}-facodi-${env_name}-filestore"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

gcloud run services describe "$service" \
  --project "$project" \
  --region "$region" \
  --format=json >"$tmp"

python3 - "$tmp" "$expected_image" "$expected_sa" "$expected_db" "$expected_bucket" <<'PY'
import json
import sys

path, expected_image, expected_sa, expected_db, expected_bucket = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    doc = json.load(handle)


def walk(value):
    if isinstance(value, dict):
        yield value
        for item in value.values():
            yield from walk(item)
    elif isinstance(value, list):
        for item in value:
            yield from walk(item)

serialized = json.dumps(doc, sort_keys=True)
for expected, label in (
    (expected_image, "immutable image"),
    (expected_sa, "runtime service account"),
    (expected_db, "Cloud SQL connection"),
    (expected_bucket, "filestore bucket"),
):
    if expected not in serialized:
        raise SystemExit(f"missing {label}: {expected}")

conditions = [
    item for item in walk(doc)
    if isinstance(item, dict) and str(item.get("type", "")).lower() == "ready"
]
if not conditions:
    raise SystemExit("Cloud Run Ready condition not found")
if not any(
    str(item.get("status", "")).lower() == "true"
    or str(item.get("state", "")).upper() == "CONDITION_SUCCEEDED"
    for item in conditions
):
    raise SystemExit("Cloud Run service is not Ready")

max_values = []
for item in walk(doc):
    if not isinstance(item, dict):
        continue
    for key, value in item.items():
        normalized = key.replace("_", "").lower()
        if normalized in {"maxinstancecount", "maxscale"}:
            max_values.append(str(value))
if not max_values:
    raise SystemExit("Cloud Run max instance policy not found")
if any(value != "1" for value in max_values):
    raise SystemExit(f"Cloud Run max instance policy is not 1: {max_values}")
PY

uri="$(gcloud run services describe "$service" --project "$project" --region "$region" --format='value(status.url)')"
if [[ -z "$uri" ]]; then
  uri="$(gcloud run services describe "$service" --project "$project" --region "$region" --format='value(uri)')"
fi
[[ -n "$uri" ]] || { echo "Cloud Run service URL not found" >&2; exit 1; }

token="$(gcloud auth print-identity-token --audiences="$uri")"
curl -fsS --retry 12 --retry-delay 5 --retry-all-errors \
  -H "Authorization: Bearer $token" \
  "$uri/web/login" >/dev/null

echo "FACODI ${env_name} runtime verified: ${expected_image}"
