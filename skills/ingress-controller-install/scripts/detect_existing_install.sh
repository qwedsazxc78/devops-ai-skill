#!/usr/bin/env bash
# detect_existing_install.sh — detect whether Traefik is already installed.
#
# Probes:
#   1. helm list -A -f '^traefik$' -o json
#   2. kubectl get ingressclass -o json (enumerate registered classes)
#
# Output (stdout, JSON):
#   {
#     "existingInstall": <bool>,
#     "currentVersion": "<chart-version or null>",
#     "currentNamespace": "<namespace or null>",
#     "existingClasses": ["nginx", ...]
#   }
#
# Exit codes:
#   0  ok (regardless of whether install was found)
#   2  tooling missing (helm or kubectl)
set -euo pipefail

if ! command -v helm >/dev/null 2>&1; then
  echo "[detect_existing_install] helm not found on PATH" >&2
  exit 2
fi
if ! command -v kubectl >/dev/null 2>&1; then
  echo "[detect_existing_install] kubectl not found on PATH" >&2
  exit 2
fi

HELM_OUT=$(helm list -A -f '^traefik$' -o json 2>/dev/null || echo '[]')
if [[ "$(echo "$HELM_OUT" | jq 'length')" -gt 0 ]]; then
  EXISTING=true
  VERSION=$(echo "$HELM_OUT" | jq -r '.[0].chart // null | sub("^traefik-"; "")')
  NAMESPACE=$(echo "$HELM_OUT" | jq -r '.[0].namespace // null')
else
  EXISTING=false
  VERSION=null
  NAMESPACE=null
fi

CLASS_OUT=$(kubectl get ingressclass -o json 2>/dev/null || echo '{"items":[]}')
CLASSES=$(echo "$CLASS_OUT" | jq '[.items[].metadata.name]')

jq -n \
  --argjson existing "$EXISTING" \
  --arg version "$VERSION" \
  --arg namespace "$NAMESPACE" \
  --argjson classes "$CLASSES" \
  '{
    existingInstall: $existing,
    currentVersion: (if $version == "null" then null else $version end),
    currentNamespace: (if $namespace == "null" then null else $namespace end),
    existingClasses: $classes
  }'
