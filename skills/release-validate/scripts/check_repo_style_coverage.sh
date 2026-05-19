#!/usr/bin/env bash
# check_repo_style_coverage.sh — verify fixture coverage across repo styles.
#
# Reads a matrix (skill, style → required|optional) and inventories
# tests/<skill>/fixtures/ directories. Reports gaps for required entries.
#
# Two invocation modes:
#   Production: --repo-root <path> (reads
#               skills/release-validate/references/repo-style-matrix.md)
#   Test: --matrix-skills "..." --matrix-styles "..." --matrix-required "..."
#         (lets fixture tests inject a synthetic matrix)
#
# Output (stdout, JSON):
#   {
#     "scanned": N,
#     "matrix": [{skill, style, requirement}],
#     "missing": ["skill:style", ...],     # required entries without fixtures
#     "coveragePct": NN,
#     "verdict": "OK" | "WARN"
#   }
#
# Exit codes:
#   0   verdict OK (full coverage) or WARN (gaps found — advisory only, not blocking)
#   2   tooling / args missing
set -uo pipefail

REPO_ROOT=""
MATRIX_SKILLS=""
MATRIX_STYLES=""
MATRIX_REQUIRED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)       REPO_ROOT="$2";       shift 2 ;;
    --matrix-skills)   MATRIX_SKILLS="$2";   shift 2 ;;
    --matrix-styles)   MATRIX_STYLES="$2";   shift 2 ;;
    --matrix-required) MATRIX_REQUIRED="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$REPO_ROOT" ]] && { echo "--repo-root required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

# If --matrix-* not supplied, parse the production matrix file.
if [[ -z "$MATRIX_SKILLS" ]]; then
  MATRIX_FILE="$REPO_ROOT/skills/release-validate/references/repo-style-matrix.md"
  if [[ ! -f "$MATRIX_FILE" ]]; then
    # No matrix file: emit empty result, verdict OK (no coverage required).
    jq -n '{scanned: 0, matrix: [], missing: [], coveragePct: 100, verdict: "OK"}'
    exit 0
  fi
  # Read the "Coverage requirements" table:
  #   | skill | kustomize-argocd | helm-only | mixed |
  # First parse the header row to get the styles in order.
  HEADER=$(grep -m1 -E '^\| Skill \|' "$MATRIX_FILE" || true)
  MATRIX_STYLES=$(echo "$HEADER" | awk -F'|' '{for(i=3;i<NF;i++){gsub(/^ +| +$/,"",$i); printf "%s ",$i}}' | sed 's/ *$//')
  # Then each data row.
  REQUIRED_LIST=()
  SKILL_LIST=()
  while IFS= read -r row; do
    [[ "$row" == *"---"* ]] && continue
    skill=$(echo "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    [[ -z "$skill" ]] && continue
    SKILL_LIST+=("$skill")
    col=3
    for style in $MATRIX_STYLES; do
      val=$(echo "$row" | awk -F'|' -v c=$col '{gsub(/^ +| +$/,"",$c); print $c}')
      [[ "$val" == "required" ]] && REQUIRED_LIST+=("$skill:$style")
      col=$((col+1))
    done
  done < <(awk '/^\| Skill \|/{flag=1;next} /^## /{flag=0} flag' "$MATRIX_FILE")
  MATRIX_SKILLS="${SKILL_LIST[*]+"${SKILL_LIST[*]}"}"
  MATRIX_REQUIRED="${REQUIRED_LIST[*]+"$(IFS=,; echo "${REQUIRED_LIST[*]}")"}"
fi

# Build the matrix array for output
MATRIX_JSON='[]'
for skill in $MATRIX_SKILLS; do
  for style in $MATRIX_STYLES; do
    pair="$skill:$style"
    if [[ ",$MATRIX_REQUIRED," == *",$pair,"* ]]; then
      req="required"
    else
      req="optional"
    fi
    entry=$(jq -n --arg s "$skill" --arg st "$style" --arg r "$req" \
      '{skill: $s, style: $st, requirement: $r}')
    MATRIX_JSON=$(echo "$MATRIX_JSON" | jq --argjson e "$entry" '. += [$e]')
  done
done

# Inventory: a (skill, style) pair has a fixture if any directory under
# tests/<skill>/fixtures/ contains the style name as a substring, OR if
# tests/<skill>/fixtures/ contains ANY fixture (the convention is that
# pre-v1.15.0 fixtures count as kustomize-argocd).
MISSING=()
SCANNED=0
for skill in $MATRIX_SKILLS; do
  fixtures_dir="$REPO_ROOT/tests/$skill/fixtures"
  for style in $MATRIX_STYLES; do
    pair="$skill:$style"
    [[ ",$MATRIX_REQUIRED," != *",$pair,"* ]] && continue
    SCANNED=$((SCANNED+1))
    present=false
    if [[ -d "$fixtures_dir" ]]; then
      if [[ "$style" == "kustomize-argocd" ]]; then
        # Convention: any pre-v1.15.0 fixture counts as kustomize-argocd
        if [[ -n "$(ls -A "$fixtures_dir" 2>/dev/null)" ]]; then
          present=true
        fi
      else
        # Explicit style match
        if find "$fixtures_dir" -mindepth 1 -maxdepth 1 -type d -name "*$style*" 2>/dev/null | grep -q .; then
          present=true
        fi
      fi
    fi
    [[ "$present" == "false" ]] && MISSING+=("$pair")
  done
done

MISSING_JSON='[]'
if (( ${#MISSING[@]} > 0 )); then
  MISSING_JSON=$(printf '%s\n' "${MISSING[@]}" | jq -R . | jq -s .)
fi

COVERAGE_PCT=100
if (( SCANNED > 0 )); then
  COVERAGE_PCT=$(( (SCANNED - ${#MISSING[@]}) * 100 / SCANNED ))
fi

VERDICT="OK"
(( ${#MISSING[@]} > 0 )) && VERDICT="WARN"

jq -n \
  --argjson scanned "$SCANNED" \
  --argjson matrix "$MATRIX_JSON" \
  --argjson missing "$MISSING_JSON" \
  --argjson pct "$COVERAGE_PCT" \
  --arg verdict "$VERDICT" \
  '{scanned: $scanned, matrix: $matrix, missing: $missing, coveragePct: $pct, verdict: $verdict}'

exit 0
