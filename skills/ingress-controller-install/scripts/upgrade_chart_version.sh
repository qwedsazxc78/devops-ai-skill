#!/usr/bin/env bash
# upgrade_chart_version.sh — atomic Traefik chart version bump across base + overlays.
#
# Edits .helmCharts[0].version in base/kustomization.yaml and every
# overlays/*/kustomization.yaml under common.traefik/. Idempotent.
#
# Backs up each file to BACKUP_DIR before editing. On any failure
# (kustomize build post-edit, version mismatch), restores all backups.
#
# Usage:
#   upgrade_chart_version.sh --repo-root <path> --target <version> --backup-dir <path>
#
# Output (stdout, JSON):
#   {
#     "filesEdited": [<paths>],
#     "fromVersion": "39.0.8",
#     "toVersion": "40.1.0",
#     "verdict": "OK" | "ROLLED_BACK"
#   }
#
# Exit codes:
#   0   bump applied + builds clean
#   1   build failed post-edit; backups restored
#   2   tooling missing or invalid args
set -euo pipefail

REPO_ROOT=""
TARGET=""
BACKUP_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)  REPO_ROOT="$2";  shift 2 ;;
    --target)     TARGET="$2";     shift 2 ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

for v in REPO_ROOT TARGET BACKUP_DIR; do
  [[ -z "${!v}" ]] && { echo "$v required" >&2; exit 2; }
done

command -v yq >/dev/null 2>&1 || { echo "yq not on PATH" >&2; exit 2; }
command -v kustomize >/dev/null 2>&1 || { echo "kustomize not on PATH" >&2; exit 2; }

mkdir -p "$BACKUP_DIR"

FILES=()
BASE="$REPO_ROOT/common.traefik/base/kustomization.yaml"
[[ -f "$BASE" ]] && FILES+=("$BASE")
while IFS= read -r f; do
  FILES+=("$f")
done < <(find "$REPO_ROOT/common.traefik/overlays" -name kustomization.yaml 2>/dev/null)

(( ${#FILES[@]} == 0 )) && { echo "no kustomization.yaml found under common.traefik/" >&2; exit 2; }

FROM_VERSION=$(yq -r '.helmCharts[0].version // "null"' "$BASE" 2>/dev/null || echo "null")
EDITED=()

# Backup
for f in "${FILES[@]}"; do
  rel="${f#$REPO_ROOT/}"
  backup="$BACKUP_DIR/$(echo "$rel" | tr '/' '_')"
  cp "$f" "$backup"
done

restore_backups() {
  for f in "${FILES[@]}"; do
    rel="${f#$REPO_ROOT/}"
    backup="$BACKUP_DIR/$(echo "$rel" | tr '/' '_')"
    cp "$backup" "$f"
  done
}

# Edit
for f in "${FILES[@]}"; do
  if yq eval '.helmCharts[0].version' "$f" >/dev/null 2>&1; then
    yq eval -i '.helmCharts[0].version = "'"$TARGET"'"' "$f"
    EDITED+=("$f")
  fi
done

# Verify all match
MISMATCH=()
for f in "${EDITED[@]}"; do
  V=$(yq -r '.helmCharts[0].version' "$f")
  [[ "$V" != "$TARGET" ]] && MISMATCH+=("$f")
done

if (( ${#MISMATCH[@]} > 0 )); then
  restore_backups
  jq -n --arg from "$FROM_VERSION" --arg to "$TARGET" --argjson mm "$(printf '%s\n' "${MISMATCH[@]}" | jq -R . | jq -s .)" \
    '{fromVersion: $from, toVersion: $to, mismatched: $mm, verdict: "ROLLED_BACK"}'
  exit 1
fi

# Build sanity-check on every overlay
BUILD_FAILED=()
while IFS= read -r overlay_kust; do
  overlay=$(dirname "$overlay_kust")
  if ! kustomize build --enable-helm "$overlay" >/dev/null 2>&1; then
    BUILD_FAILED+=("$overlay")
  fi
done < <(find "$REPO_ROOT/common.traefik/overlays" -name kustomization.yaml 2>/dev/null)

if (( ${#BUILD_FAILED[@]} > 0 )); then
  restore_backups
  jq -n --arg from "$FROM_VERSION" --arg to "$TARGET" --argjson bf "$(printf '%s\n' "${BUILD_FAILED[@]}" | jq -R . | jq -s .)" \
    '{fromVersion: $from, toVersion: $to, buildFailedOverlays: $bf, verdict: "ROLLED_BACK"}'
  exit 1
fi

EDITED_JSON=$(printf '%s\n' "${EDITED[@]}" | jq -R . | jq -s .)
jq -n \
  --arg from "$FROM_VERSION" \
  --arg to "$TARGET" \
  --argjson files "$EDITED_JSON" \
  '{
    fromVersion: $from,
    toVersion: $to,
    filesEdited: $files,
    verdict: "OK"
  }'
