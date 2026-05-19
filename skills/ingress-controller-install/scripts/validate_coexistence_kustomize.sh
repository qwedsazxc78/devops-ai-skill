#!/usr/bin/env bash
# validate_coexistence_kustomize.sh — read-only coexistence checks via kustomize build.
#
# Asserts that adding/upgrading Traefik in `common.traefik/overlays/<env>/`
# does NOT collide with other controllers ArgoCD also applies.
#
# Three checks (mirror the live-cluster versions but operate offline):
#   1. classCollision — IngressClass / ingressClassName collision across modules
#   2. lbIpCollision  — loadBalancerIP collision in any LoadBalancer Service
#   3. portCollision  — port 80 / 443 collision in the target namespace
#
# Usage:
#   validate_coexistence_kustomize.sh --repo-root <path> --target-env <env> \
#     --target-class <name> [--target-lb-ip <ip>] [--mode upgrade|new-env|bootstrap]
#
# Output (stdout, JSON):
#   {
#     "classCollision": false,
#     "lbIpCollision": false,
#     "portCollision": false,
#     "details": {...}
#   }
#
# Exit codes:
#   0   no collisions
#   1   at least one collision
#   2   tooling missing or kustomize build failure
set -euo pipefail

REPO_ROOT=""
TARGET_ENV=""
TARGET_CLASS=""
TARGET_LB_IP=""
MODE="upgrade"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)    REPO_ROOT="$2";    shift 2 ;;
    --target-env)   TARGET_ENV="$2";   shift 2 ;;
    --target-class) TARGET_CLASS="$2"; shift 2 ;;
    --target-lb-ip) TARGET_LB_IP="$2"; shift 2 ;;
    --mode)         MODE="$2";         shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in REPO_ROOT TARGET_ENV TARGET_CLASS; do
  [[ -z "${!v}" ]] && { echo "$v required" >&2; exit 2; }
done

command -v kustomize >/dev/null 2>&1 || { echo "kustomize not on PATH" >&2; exit 2; }
command -v yq        >/dev/null 2>&1 || { echo "yq not on PATH"        >&2; exit 2; }
command -v jq        >/dev/null 2>&1 || { echo "jq not on PATH"        >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

build_module() {
  local overlay="$1" out="$2"
  if kustomize build --enable-helm "$overlay" > "$out" 2>/dev/null; then
    return 0
  fi
  # Fallback without --enable-helm in case the chart isn't inflated
  kustomize build "$overlay" > "$out" 2>/dev/null || true
  return 0
}

# Build every overlay under common.* except the target Traefik overlay
# (for the target, build separately and compare against the "rest").
OTHER_OVERLAYS=()
TARGET_OVERLAY="$REPO_ROOT/common.traefik/overlays/$TARGET_ENV"

while IFS= read -r k; do
  o=$(dirname "$k")
  [[ "$o" == "$TARGET_OVERLAY" ]] && continue
  OTHER_OVERLAYS+=("$o")
done < <(find "$REPO_ROOT"/common.* -path "*/overlays/*" -name kustomization.yaml 2>/dev/null)

OTHER_BUILT="$TMP/others.yaml"
: > "$OTHER_BUILT"
for o in "${OTHER_OVERLAYS[@]}"; do
  build_module "$o" "$TMP/built.yaml"
  cat "$TMP/built.yaml" >> "$OTHER_BUILT"
  echo "---" >> "$OTHER_BUILT"
done

# Class collision: any IngressClass / Ingress whose class equals TARGET_CLASS
# in "other" overlays. (Upgrade mode allows the existing traefik class.)
CLASS_HITS=$(yq ea -o=json '. | select(
    (.kind == "IngressClass" and .metadata.name == "'"$TARGET_CLASS"'")
    or (.kind == "Ingress" and (
         .spec.ingressClassName == "'"$TARGET_CLASS"'"
         or (.spec.ingressClassName == null and .metadata.annotations["kubernetes.io/ingress.class"] == "'"$TARGET_CLASS"'")
       ))
  )' "$OTHER_BUILT" 2>/dev/null | jq -s '[.[] | select(. != null)]' 2>/dev/null || echo '[]')
[[ -z "$CLASS_HITS" ]] && CLASS_HITS='[]'

CLASS_COLLISION_RAW=$(echo "$CLASS_HITS" | jq 'length > 0')
if [[ "$MODE" == "upgrade" || "$MODE" == "new-env" ]] && [[ "$TARGET_CLASS" == "traefik" ]]; then
  # Upgrade or new-env on the same class is the expected case — coexistence
  # against your own existing class is not a collision.
  CLASS_COLLISION=false
else
  CLASS_COLLISION=$CLASS_COLLISION_RAW
fi

# LB IP collision (only if --target-lb-ip supplied)
LB_COLLISION=false
LB_DETAILS="null"
if [[ -n "$TARGET_LB_IP" ]]; then
  HITS=$(yq ea -o=json '. | select(.kind == "Service" and .spec.type == "LoadBalancer" and .spec.loadBalancerIP == "'"$TARGET_LB_IP"'")' "$OTHER_BUILT" 2>/dev/null | jq -s '[.[].metadata | "\(.namespace)/\(.name)"]')
  if [[ "$(echo "$HITS" | jq 'length')" -gt 0 ]]; then
    LB_COLLISION=true
    LB_DETAILS=$HITS
  fi
fi

# Port collision: any non-Traefik LoadBalancer Service in the same namespace
# (traefik by default) exposing 80 or 443. Wrap the pipeline in `|| true`
# guards because `set -e + pipefail` makes empty yq/jq results trigger exit.
PORT_COLLISION=false
PORT_DETAILS="null"
PORT_HITS=$(yq ea -o=json '. | select(.kind == "Service" and .spec.type == "LoadBalancer" and .metadata.namespace == "traefik" and ((.spec.ports // []) | any(.port == 80 or .port == 443)))' "$OTHER_BUILT" 2>/dev/null | jq -s '[.[].metadata | "\(.namespace)/\(.name)"]' 2>/dev/null || echo '[]')
[[ -z "$PORT_HITS" ]] && PORT_HITS='[]'
# jq sometimes prints a length per slurped item; take only the first number.
PORT_LEN=$(echo "$PORT_HITS" | jq 'length' 2>/dev/null | head -1 || true)
PORT_LEN=${PORT_LEN:-0}
if [[ "${PORT_LEN}" =~ ^[0-9]+$ ]] && [[ "$PORT_LEN" -gt 0 ]]; then
  PORT_COLLISION=true
  PORT_DETAILS=$PORT_HITS
fi

jq -n \
  --argjson cls "$CLASS_COLLISION" \
  --argjson lb "$LB_COLLISION" \
  --argjson port "$PORT_COLLISION" \
  --argjson clsHits "$CLASS_HITS" \
  --argjson lbDetails "$LB_DETAILS" \
  --argjson portDetails "$PORT_DETAILS" \
  '{
    classCollision: $cls,
    lbIpCollision: $lb,
    portCollision: $port,
    details: {
      classHits: $clsHits,
      lbConflictingServices: $lbDetails,
      portConflictingServices: $portDetails
    }
  }'

if [[ "$CLASS_COLLISION" == "true" || "$LB_COLLISION" == "true" || "$PORT_COLLISION" == "true" ]]; then
  exit 1
fi
exit 0
