#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
image_uri="${2:?usage: scripts/deploy-runtime.sh staging|production IMAGE_URI}"
case "$env_name" in
  staging|production) ;;
  *) echo "environment must be staging or production" >&2; exit 64 ;;
esac

project="${GCP_PROJECT_ID:-marcelo-497411}"
region="${GCP_REGION:-europe-southwest1}"
job="facodi-${env_name}-migrate"
service="facodi-${env_name}"

gcloud run jobs update "$job" \
  --project "$project" \
  --region "$region" \
  --image "$image_uri" \
  --quiet

gcloud run jobs execute "$job" \
  --project "$project" \
  --region "$region" \
  --wait \
  --quiet

gcloud run services update "$service" \
  --project "$project" \
  --region "$region" \
  --image "$image_uri" \
  --quiet

exec "$(dirname "$0")/verify-runtime.sh" "$env_name" "$image_uri"
