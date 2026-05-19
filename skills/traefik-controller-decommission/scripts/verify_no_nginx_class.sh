#!/usr/bin/env bash
# verify_no_nginx_class.sh — verify zero active nginx Ingresses across cluster + repo.
#
# Modes:
#   --cluster   live cluster scan via kubectl
#   --repo      repo scan via kustomize build across every overlay
#   (both)      default — run both and emit combined JSON
#
# Output (stdout, JSON):
#   { "cluster": [...], "repo": [...], "verdict": "PASS"|"BLOCKED"|"DEGRADED" }
#
# Exit codes:
#   0   no active nginx ingresses found (verdict PASS)
#   1   at least one active nginx ingress found (verdict BLOCKED)
#   2   tooling unavailable (kubectl/kustomize missing) — verdict DEGRADED
set -euo pipefail

MODE_CLUSTER=1
MODE_REPO=1
case "${1:-}" in
  --cluster) MODE_REPO=0 ;;
  --repo)    MODE_CLUSTER=0 ;;
  ""|--all)  ;;
  *) echo "usage: $0 [--cluster|--repo|--all]" >&2; exit 2 ;;
esac

CLUSTER_JSON='[]'
REPO_JSON='[]'
DEGRADED=0

# --- Cluster scan ---
if (( MODE_CLUSTER )); then
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "[verify_no_nginx_class] kubectl unavailable; cluster scan skipped" >&2
    DEGRADED=1
  else
    if CLUSTER_RAW=$(kubectl get ingress -A -o json 2>/dev/null); then
      # Same precedence rule as the repo scan: spec wins, annotation is fallback.
      CLUSTER_JSON=$(echo "$CLUSTER_RAW" | jq '[.items[]
        | select(.spec.ingressClassName == "nginx"
               or (.spec.ingressClassName == null
                   and (.metadata.annotations["kubernetes.io/ingress.class"] // "") == "nginx"))
        | "\(.metadata.namespace)/\(.metadata.name)"]')
    else
      echo "[verify_no_nginx_class] kubectl get ingress failed; cluster scan degraded" >&2
      DEGRADED=1
    fi
  fi
fi

# --- Repo scan ---
if (( MODE_REPO )); then
  if ! command -v kustomize >/dev/null 2>&1; then
    echo "[verify_no_nginx_class] kustomize unavailable; repo scan skipped" >&2
    DEGRADED=1
  elif ! command -v yq >/dev/null 2>&1; then
    echo "[verify_no_nginx_class] yq unavailable; repo scan skipped" >&2
    DEGRADED=1
  else
    OVERLAYS=()
    while IFS= read -r k; do
      [[ "$k" == *"/archive/"* ]] && continue
      OVERLAYS+=("$(dirname "$k")")
    done < <(find . -name 'kustomization.yaml' -not -path '*/.git/*' 2>/dev/null)

    REPO_HITS=()
    for overlay in "${OVERLAYS[@]}"; do
      [[ "$overlay" == *"/overlays/"* ]] || continue
      built=$(kustomize build "$overlay" 2>/dev/null || true)
      [[ -z "$built" ]] && continue
      # An Ingress is nginx-class if:
      #   (a) spec.ingressClassName == "nginx", OR
      #   (b) spec.ingressClassName is null AND the legacy annotation
      #       kubernetes.io/ingress.class == "nginx"
      # This mirrors Kubernetes' precedence (spec wins, annotation is fallback).
      nginx_count=$(echo "$built" \
        | yq ea '. | select(.kind == "Ingress") | select(
            .spec.ingressClassName == "nginx"
            or (.spec.ingressClassName == null and .metadata.annotations["kubernetes.io/ingress.class"] == "nginx")
          ) | .metadata.name' - 2>/dev/null \
        | grep -c . || true)
      if (( nginx_count > 0 )); then
        REPO_HITS+=("$overlay")
      fi
    done

    if (( ${#REPO_HITS[@]} > 0 )); then
      REPO_JSON=$(printf '%s\n' "${REPO_HITS[@]}" | jq -R . | jq -s .)
    fi
  fi
fi

CLUSTER_COUNT=$(echo "$CLUSTER_JSON" | jq 'length')
REPO_COUNT=$(echo "$REPO_JSON" | jq 'length')

if (( CLUSTER_COUNT == 0 && REPO_COUNT == 0 )); then
  VERDICT=$([[ $DEGRADED -eq 1 ]] && echo "DEGRADED" || echo "PASS")
else
  VERDICT="BLOCKED"
fi

jq -n \
  --argjson cluster "$CLUSTER_JSON" \
  --argjson repo "$REPO_JSON" \
  --arg verdict "$VERDICT" \
  '{cluster: $cluster, repo: $repo, verdict: $verdict}'

case "$VERDICT" in
  PASS)     exit 0 ;;
  BLOCKED)  exit 1 ;;
  DEGRADED) exit 2 ;;
esac
