#!/usr/bin/env bash
set -euo pipefail

env_name="${1:?usage: scripts/configure-database-user.sh staging|production}"
case "$env_name" in
  staging|production) ;;
  *) echo "environment must be staging or production" >&2; exit 64 ;;
esac

project="${GCP_PROJECT_ID:-marcelo-497411}"
instance="facodi-${env_name}-pg"
secret="facodi-${env_name}-db-password"
password="$(gcloud secrets versions access latest --project "$project" --secret "$secret")"

cleanup() {
  unset password
}
trap cleanup EXIT

if gcloud sql users list --project "$project" --instance "$instance" --format='value(name)' | grep -qx odoo; then
  gcloud sql users set-password odoo --project "$project" --instance "$instance" --password "$password"
else
  gcloud sql users create odoo --project "$project" --instance "$instance" --password "$password"
fi
