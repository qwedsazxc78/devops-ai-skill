#!/usr/bin/env bash
# detect_mode.sh — decide between bootstrap / new-env / upgrade modes.
#
# Inspects the consumer repo's `common.traefik/` directory to determine
# which install mode applies. No live cluster queries.
#
# Usage:
#   detect_mode.sh --repo-root <path> --target-env <env>
#
# Output (stdout, JSON):
#   {
#     "mode": "bootstrap" | "new-env" | "upgrade",
#     "moduleExists": true,
#     "baseExists": true,
#     "targetEnvExists": false,
#     "existingOverlays": ["dev", "stg", "prd"],
#     "currentChartVersion": "39.0.8"
#   }
#
# Exit codes:
#   0   detection succeeded
#   2   missing required arg or yq unavailable
set -euo pipefail

REPO_ROOT=""
TARGET_ENV=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)  REPO_ROOT="$2"; shift 2 ;;
    --target-env) TARGET_ENV="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$REPO_ROOT" ]] && { echo "--repo-root required" >&2; exit 2; }
[[ -z "$TARGET_ENV" ]] && { echo "--target-env required" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "yq not on PATH" >&2; exit 2; }

MODULE="$REPO_ROOT/common.traefik"
BASE="$MODULE/base"
TARGET_OVERLAY="$MODULE/overlays/$TARGET_ENV"

MODULE_EXISTS=false
BASE_EXISTS=false
TARGET_ENV_EXISTS=false
EXISTING=()
CURRENT_VERSION="null"

if [[ -d "$MODULE" ]]; then
  MODULE_EXISTS=true
  [[ -d "$BASE" ]] && BASE_EXISTS=true
  [[ -d "$TARGET_OVERLAY" ]] && TARGET_ENV_EXISTS=true
  if [[ -d "$MODULE/overlays" ]]; then
    while IFS= read -r -d '' d; do
      EXISTING+=("$(basename "$d")")
    done < <(find "$MODULE/overlays" -mindepth 1 -maxdepth 1 -type d -print0)
  fi
  # Pull current chart version. The Traefik convention in eye-of-horus-gitops
  # puts helmCharts only in each overlay (so per-env valuesInline can override
  # chart toggles); base intentionally omits it. So check overlays first and
  # fall back to base only if no overlay declares the chart.
  V="null"
  for sample in "$TARGET_OVERLAY/kustomization.yaml" \
                "$MODULE/overlays/dev/kustomization.yaml" \
                "$BASE/kustomization.yaml"; do
    [[ -f "$sample" ]] || continue
    found=$(yq -r '.helmCharts[0].version // "null"' "$sample" 2>/dev/null || echo "null")
    if [[ "$found" != "null" && -n "$found" ]]; then
      V="$found"
      break
    fi
  done
  CURRENT_VERSION="$V"
fi

if [[ "$MODULE_EXISTS" == "false" ]]; then
  MODE="bootstrap"
elif [[ "$TARGET_ENV_EXISTS" == "false" ]]; then
  MODE="new-env"
else
  MODE="upgrade"
fi

EXISTING_JSON='[]'
if (( ${#EXISTING[@]} > 0 )); then
  EXISTING_JSON=$(printf '%s\n' "${EXISTING[@]}" | jq -R . | jq -s .)
fi

jq -n \
  --arg mode "$MODE" \
  --argjson module_exists "$MODULE_EXISTS" \
  --argjson base_exists "$BASE_EXISTS" \
  --argjson target_env_exists "$TARGET_ENV_EXISTS" \
  --argjson existing "$EXISTING_JSON" \
  --arg version "$CURRENT_VERSION" \
  '{
    mode: $mode,
    moduleExists: $module_exists,
    baseExists: $base_exists,
    targetEnvExists: $target_env_exists,
    existingOverlays: $existing,
    currentChartVersion: (if $version == "null" then null else $version end)
  }'
