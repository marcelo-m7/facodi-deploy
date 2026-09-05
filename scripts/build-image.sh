#!/usr/bin/env bash
set -euo pipefail
image="${1:?usage: scripts/build-image.sh IMAGE_URI [--push]}"
push="${2:-}"
docker build -f docker/Dockerfile -t "$image" .
if [[ "$push" == "--push" ]]; then
  docker push "$image"
elif [[ -n "$push" ]]; then
  echo "unknown option: $push" >&2
  exit 64
fi
