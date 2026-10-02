#!/usr/bin/env bash
set -euo pipefail

: "${COOLIFY_API_URL:?Set COOLIFY_API_URL, e.g. https://coolify.example.com/api/v1}"
: "${COOLIFY_API_TOKEN:?Set COOLIFY_API_TOKEN}"
: "${COOLIFY_APP_UUID:?Set COOLIFY_APP_UUID}"
: "${FACODI_IMAGE:?Set FACODI_IMAGE to an immutable GHCR digest}"
: "${COOLIFY_PROOF_ACK:?Set COOLIFY_PROOF_ACK=NON_PRODUCTION_ONLY}"

if [[ "${COOLIFY_PROOF_ACK}" != "NON_PRODUCTION_ONLY" ]]; then
  echo "Refusing to run: COOLIFY_PROOF_ACK must equal NON_PRODUCTION_ONLY" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bash scripts/validate-release-image.sh "$FACODI_IMAGE"

api="${COOLIFY_API_URL%/}"
auth=(-H "Authorization: Bearer ${COOLIFY_API_TOKEN}" -H "Content-Type: application/json")
out_dir="${COOLIFY_PROOF_DIR:-artifacts/coolify-proof}"
mkdir -p "$out_dir"

echo "[coolify-proof] reading application metadata"
curl --fail --silent --show-error "${auth[@]}"   "$api/applications/$COOLIFY_APP_UUID" > "$out_dir/application-before.json"

fqdn="$(jq -r '.fqdn // .domains // ""' "$out_dir/application-before.json")"
if [[ "$fqdn" == *"facodi.com"* || "$fqdn" == *"www.facodi.com"* ]]; then
  echo "Refusing to run against production-looking FACODI domain: $fqdn" >&2
  exit 3
fi

echo "[coolify-proof] non-production target: ${fqdn:-<no fqdn reported>}"

set_image_env() {
  local image_ref="$1"
  local payload
  payload="$(jq -n --arg key FACODI_IMAGE --arg value "$image_ref"     '{key:$key,value:$value,is_preview:false,is_literal:true}')"

  curl --fail --silent --show-error "${auth[@]}"     "$api/applications/$COOLIFY_APP_UUID/envs" > "$out_dir/envs.json"

  if jq -e '.[] | select(.key == "FACODI_IMAGE")' "$out_dir/envs.json" >/dev/null; then
    curl --fail --silent --show-error -X PATCH "${auth[@]}"       -d "$payload"       "$api/applications/$COOLIFY_APP_UUID/envs" > "$out_dir/env-update.json"
  else
    curl --fail --silent --show-error -X POST "${auth[@]}"       -d "$payload"       "$api/applications/$COOLIFY_APP_UUID/envs" > "$out_dir/env-create.json"
  fi
}

wait_deployment() {
  local deployment_uuid="$1"
  local label="$2"
  local max_checks="${COOLIFY_DEPLOYMENT_MAX_CHECKS:-120}"
  local interval="${COOLIFY_DEPLOYMENT_POLL_SECONDS:-5}"
  local status=""

  for ((i=1; i<=max_checks; i++)); do
    curl --fail --silent --show-error "${auth[@]}"       "$api/deployments/$deployment_uuid" > "$out_dir/${label}-deployment.json"
    status="$(jq -r '.status // ""' "$out_dir/${label}-deployment.json")"
    printf '[coolify-proof] %s deployment %s status=%s (%d/%d)\n'       "$label" "$deployment_uuid" "$status" "$i" "$max_checks"

    case "$status" in
      finished|success|successful)
        jq -r '.logs // ""' "$out_dir/${label}-deployment.json" > "$out_dir/${label}-deployment.log"
        return 0
        ;;
      failed|error|cancelled|cancelled-by-user)
        jq -r '.logs // ""' "$out_dir/${label}-deployment.json" > "$out_dir/${label}-deployment.log"
        echo "Deployment $deployment_uuid failed with status=$status" >&2
        return 1
        ;;
    esac
    sleep "$interval"
  done

  echo "Timed out waiting for deployment $deployment_uuid; last status=$status" >&2
  return 1
}

deploy_current_image() {
  local label="$1"
  local response="$out_dir/${label}-start.json"

  curl --fail --silent --show-error -X POST "${auth[@]}"     "$api/applications/$COOLIFY_APP_UUID/start?force=false&instant_deploy=false"     > "$response"

  local deployment_uuid
  deployment_uuid="$(jq -r '.deployment_uuid // (.deployments[0].deployment_uuid // empty)' "$response")"
  if [[ -z "$deployment_uuid" ]]; then
    echo "Coolify did not return deployment_uuid" >&2
    cat "$response" >&2
    return 1
  fi

  wait_deployment "$deployment_uuid" "$label"
  echo "$deployment_uuid"
}

echo "[coolify-proof] setting candidate digest"
set_image_env "$FACODI_IMAGE"
candidate_uuid="$(deploy_current_image candidate)"
echo "$candidate_uuid" > "$out_dir/candidate-deployment-uuid.txt"

candidate_logs="$out_dir/candidate-deployment.log"
if [[ -s "$candidate_logs" ]]; then
  grep -Ei 'pull|pulling|image|migrate|odoo|recreat|replace|start|stop' "$candidate_logs"     > "$out_dir/candidate-key-events.log" || true
fi

if [[ -n "${COOLIFY_ROLLBACK_IMAGE:-}" ]]; then
  if [[ "${COOLIFY_ROLLBACK_ACK:-}" != "ROLLBACK_NON_PRODUCTION" ]]; then
    echo "Refusing rollback proof without COOLIFY_ROLLBACK_ACK=ROLLBACK_NON_PRODUCTION" >&2
    exit 4
  fi
  bash scripts/validate-release-image.sh "$COOLIFY_ROLLBACK_IMAGE"
  echo "[coolify-proof] setting rollback digest"
  set_image_env "$COOLIFY_ROLLBACK_IMAGE"
  rollback_uuid="$(deploy_current_image rollback)"
  echo "$rollback_uuid" > "$out_dir/rollback-deployment-uuid.txt"
  rollback_logs="$out_dir/rollback-deployment.log"
  if [[ -s "$rollback_logs" ]]; then
    grep -Ei 'pull|pulling|image|migrate|odoo|recreat|replace|start|stop' "$rollback_logs"       > "$out_dir/rollback-key-events.log" || true
  fi
fi

curl --fail --silent --show-error "${auth[@]}"   "$api/applications/$COOLIFY_APP_UUID" > "$out_dir/application-after.json"

echo "[coolify-proof] evidence written to $out_dir"
