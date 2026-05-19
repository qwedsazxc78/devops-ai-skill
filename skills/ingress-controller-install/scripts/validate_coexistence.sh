#!/usr/bin/env bash
# validate_coexistence.sh — assert Traefik install plan does not collide with
# the existing ingress-nginx controller.
#
# Three checks:
#   1. classCollision  — chosen ingressClassName not already registered
#                        (allow if it's an existing traefik class on UPGRADE)
#   2. ipCollision     — chosen LB IP not bound to any LoadBalancer Service
#                        in the ingress-nginx namespace or annotated
#                        kubernetes.io/ingress.class: nginx
#   3. portCollision   — target namespace either does not exist or has no
#                        Service of type LoadBalancer already exposing 80/443
#
# Usage:
#   validate_coexistence.sh --ingress-class <name> --lb-ip <ip> --namespace <ns> [--upgrade]
#
# Output (stdout, JSON):
#   {"classCollision": false, "ipCollision": false, "portCollision": false,
#    "details": {"existingClasses": [...], "conflictingIp": "...", "conflictingService": "..."}}
#
# Exit codes:
#   0   no collisions (all three false)
#   1   at least one collision
#   2   tooling missing or kubectl unreachable
set -euo pipefail

INGRESS_CLASS=""
LB_IP=""
NAMESPACE=""
UPGRADE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ingress-class) INGRESS_CLASS="$2"; shift 2 ;;
    --lb-ip)         LB_IP="$2"; shift 2 ;;
    --namespace)     NAMESPACE="$2"; shift 2 ;;
    --upgrade)       UPGRADE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in INGRESS_CLASS LB_IP NAMESPACE; do
  [[ -z "${!v}" ]] && { echo "$v required" >&2; exit 2; }
done

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not on PATH" >&2; exit 2; }
command -v jq      >/dev/null 2>&1 || { echo "jq not on PATH"      >&2; exit 2; }

# --- 1. classCollision ---
EXISTING_CLASSES=$(kubectl get ingressclass -o json 2>/dev/null \
  | jq '[.items[].metadata.name]')
CLASS_PRESENT=$(echo "$EXISTING_CLASSES" | jq --arg c "$INGRESS_CLASS" 'index($c) != null')
CLASS_COLLISION=$CLASS_PRESENT
if (( UPGRADE )) && [[ "$INGRESS_CLASS" == "traefik" && "$CLASS_PRESENT" == "true" ]]; then
  CLASS_COLLISION=false  # upgrading the existing traefik class is fine
fi

# --- 2. ipCollision ---
# Find Services with status.loadBalancer.ingress[].ip matching LB_IP, scoped
# to namespace=ingress-nginx OR annotated kubernetes.io/ingress.class=nginx
ALL_LB_SVCS=$(kubectl get svc -A -o json 2>/dev/null \
  | jq --arg ip "$LB_IP" '[.items[]
      | select(.spec.type == "LoadBalancer")
      | select(.status.loadBalancer.ingress // [] | any(.ip == $ip))]')
CONFLICTING_SVC=$(echo "$ALL_LB_SVCS" | jq -r '[.[]
  | select(.metadata.namespace == "ingress-nginx"
        or (.metadata.annotations["kubernetes.io/ingress.class"] // "") == "nginx")
  | "\(.metadata.namespace)/\(.metadata.name)"] | first // ""')
if [[ -n "$CONFLICTING_SVC" ]]; then
  IP_COLLISION=true
else
  IP_COLLISION=false
fi

# --- 3. portCollision ---
NS_EXISTS=$(kubectl get ns "$NAMESPACE" -o json 2>/dev/null | jq -r 'if . then "true" else "false" end')
if [[ "$NS_EXISTS" != "true" ]]; then
  PORT_COLLISION=false
else
  PORT_HITS=$(kubectl get svc -n "$NAMESPACE" -o json 2>/dev/null \
    | jq --arg cls "$INGRESS_CLASS" '[.items[]
        | select(.spec.type == "LoadBalancer")
        | select((.metadata.labels["app.kubernetes.io/instance"] // "") != $cls
              and (.metadata.labels["app.kubernetes.io/name"] // "") != $cls)
        | select((.spec.ports // []) | any(.port == 80 or .port == 443))]')
  if [[ "$(echo "$PORT_HITS" | jq 'length')" -gt 0 ]]; then
    PORT_COLLISION=true
  else
    PORT_COLLISION=false
  fi
fi

jq -n \
  --argjson cls "$CLASS_COLLISION" \
  --argjson ip "$IP_COLLISION" \
  --argjson port "$PORT_COLLISION" \
  --argjson existing "$EXISTING_CLASSES" \
  --arg conflictSvc "$CONFLICTING_SVC" \
  '{
    classCollision: $cls,
    ipCollision: $ip,
    portCollision: $port,
    details: {
      existingClasses: $existing,
      conflictingIp: (if $ip then $conflictSvc else null end),
      conflictingService: (if $port then "port-80/443-in-target-ns" else null end)
    }
  }'

if [[ "$CLASS_COLLISION" == "true" || "$IP_COLLISION" == "true" || "$PORT_COLLISION" == "true" ]]; then
  exit 1
fi
exit 0
