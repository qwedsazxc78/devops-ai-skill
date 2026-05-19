#!/usr/bin/env bash
# discover_nginx_module.sh — find the Kustomize module hosting the
# ingress-nginx Helm chart, plus its ArgoCD Application manifests.
#
# Strategy:
#   1. Grep every `kustomization.yaml` for a helmCharts entry naming
#      ingress-nginx.
#   2. The enclosing directory is a module path (base/ or overlays/<env>/).
#      Normalize to the module root (parent of base/ and overlays/).
#   3. Look for sibling argocd/*.yaml manifests under the module.
#
# Usage:
#   discover_nginx_module.sh --repo-root <path>
#
# Output (stdout, JSON):
#   {
#     "modules": [
#       {
#         "path": "common.ingress-nginx",
#         "argocdAppManifests": ["common.ingress-nginx/argocd/dev.yaml", ...],
#         "namespace": "ingress-nginx",
#         "chartVersion": "4.10.0"
#       }
#     ],
#     "verdict": "OK" | "NONE" | "AMBIGUOUS"
#   }
#
# Exit codes:
#   0   exactly one module found (OK)
#   1   zero or multiple modules found (NONE / AMBIGUOUS)
#   2   tooling missing
set -euo pipefail

REPO_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$REPO_ROOT" ]] && { echo "--repo-root required" >&2; exit 2; }

command -v yq >/dev/null 2>&1 || { echo "yq not on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

# Find every kustomization.yaml that declares the ingress-nginx chart.
HITS=()
while IFS= read -r k; do
  [[ "$k" == *"/archive/"* ]] && continue
  if yq -r '.helmCharts[]?.name' "$k" 2>/dev/null | grep -qx 'ingress-nginx'; then
    HITS+=("$k")
  fi
done < <(find "$REPO_ROOT" -name 'kustomization.yaml' -not -path '*/.git/*' 2>/dev/null)

# Guard for empty HITS (bash 3.2 + set -u trips on "${HITS[@]}" when empty).
if (( ${#HITS[@]} == 0 )); then
  jq -n '{modules: [], verdict: "NONE"}'
  exit 1
fi

# Normalize each hit to a module root. A module root is the directory
# whose immediate children include `base` or `overlays`. Walk up.
# (Bash 3.2 has no associative arrays — collect to a tempfile + sort -u.)
MODULES_TMP=$(mktemp)
trap 'rm -f "$MODULES_TMP"' EXIT
for k in "${HITS[@]}"; do
  d=$(dirname "$k")
  for _ in 1 2 3; do
    if [[ -d "$d/base" || -d "$d/overlays" ]]; then
      break
    fi
    d=$(dirname "$d")
  done
  rel="${d#$REPO_ROOT/}"
  echo "$rel" >> "$MODULES_TMP"
done
MODULE_KEYS=()
while IFS= read -r m; do
  MODULE_KEYS+=("$m")
done < <(sort -u "$MODULES_TMP")

build_module_json() {
  local rel="$1"
  local namespace="" chart_version=""
  local apps=()

  # Pull namespace + chart version from any overlay
  if [[ -d "$REPO_ROOT/$rel/overlays" ]]; then
    while IFS= read -r overlay_kust; do
      ns=$(yq -r '.namespace // ""' "$overlay_kust" 2>/dev/null || echo "")
      [[ -n "$ns" && -z "$namespace" ]] && namespace="$ns"
      cv=$(yq -r '.helmCharts[0].version // ""' "$overlay_kust" 2>/dev/null || echo "")
      [[ -n "$cv" && -z "$chart_version" ]] && chart_version="$cv"
    done < <(find "$REPO_ROOT/$rel/overlays" -name kustomization.yaml 2>/dev/null)
  fi
  # Fall back to base if overlay didn't yield
  if [[ -z "$namespace" && -f "$REPO_ROOT/$rel/base/kustomization.yaml" ]]; then
    namespace=$(yq -r '.namespace // ""' "$REPO_ROOT/$rel/base/kustomization.yaml" 2>/dev/null || echo "")
  fi
  [[ -z "$chart_version" && -f "$REPO_ROOT/$rel/base/kustomization.yaml" ]] && \
    chart_version=$(yq -r '.helmCharts[0].version // ""' "$REPO_ROOT/$rel/base/kustomization.yaml" 2>/dev/null || echo "")

  # ArgoCD app manifests under the module
  if [[ -d "$REPO_ROOT/$rel/argocd" ]]; then
    while IFS= read -r m; do
      apps+=("${m#$REPO_ROOT/}")
    done < <(find "$REPO_ROOT/$rel/argocd" -maxdepth 1 -name '*.yaml' 2>/dev/null)
  fi

  local apps_json='[]'
  if (( ${#apps[@]} > 0 )); then
    apps_json=$(printf '%s\n' "${apps[@]}" | jq -R . | jq -s .)
  fi

  jq -n \
    --arg path "$rel" \
    --arg ns "$namespace" \
    --arg cv "$chart_version" \
    --argjson apps "$apps_json" \
    '{
      path: $path,
      namespace: (if $ns == "" then null else $ns end),
      chartVersion: (if $cv == "" then null else $cv end),
      argocdAppManifests: $apps
    }'
}

MODULES_JSON='[]'
if (( ${#MODULE_KEYS[@]} > 0 )); then
  MODULES_JSON=$(for m in "${MODULE_KEYS[@]}"; do build_module_json "$m"; done | jq -s .)
fi

if (( ${#MODULE_KEYS[@]} == 0 )); then
  VERDICT="NONE"
elif (( ${#MODULE_KEYS[@]} == 1 )); then
  VERDICT="OK"
else
  VERDICT="AMBIGUOUS"
fi

jq -n \
  --argjson modules "$MODULES_JSON" \
  --arg verdict "$VERDICT" \
  '{modules: $modules, verdict: $verdict}'

[[ "$VERDICT" == "OK" ]] && exit 0
exit 1
