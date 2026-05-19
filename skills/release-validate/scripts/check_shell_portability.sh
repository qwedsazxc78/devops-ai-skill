#!/usr/bin/env bash
# check_shell_portability.sh — static portability checks for every *.sh under
# skills/ and scripts/.
#
# Why this exists: macOS ships bash 3.2 by default. Some bash 4+ idioms
# (`declare -A`, `mapfile`/`readarray`) silently break. GNU `sed -i` /
# `readlink -f` flags differ from BSD. This script catches those before
# release.
#
# Checks per .sh file:
#   1. Portable shebang: `#!/usr/bin/env bash` (not `#!/bin/bash` or `#!/bin/sh`)
#   2. No `declare -A` (bash 3.2 incompatible)
#   3. No `mapfile` or `readarray` (bash 4+)
#   4. No GNU-only `sed -i` without backup suffix (BSD requires `sed -i ''`)
#   5. No `readlink -f` (BSD lacks -f; use `cd` + `pwd` pattern instead)
#   6. Optional: shellcheck if available (WARN-only)
#
# Usage:
#   check_shell_portability.sh <repo-root>
#
# Output (stdout, JSON):
#   {
#     "scanned": 24,
#     "issues": [
#       {"file": "...", "line": 57, "rule": "bash3.2-declare-A",
#        "severity": "ERROR", "match": "declare -A MODULES"}
#     ],
#     "verdict": "OK" | "FAIL" | "WARN"
#   }
#
# Exit codes:
#   0   all clean (or only WARNs)
#   1   at least one ERROR
#   2   tooling missing or no shell files found
set -uo pipefail

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(find skills scripts -name '*.sh' -not -path '*/node_modules/*' 2>/dev/null | sort)

if (( ${#FILES[@]} == 0 )); then
  echo '{"scanned": 0, "issues": [], "verdict": "NONE"}'
  exit 2
fi

ISSUES_TMP=$(mktemp)
trap 'rm -f "$ISSUES_TMP"' EXIT

emit_issue() {
  local file="$1" line="$2" rule="$3" severity="$4" match="$5"
  jq -n \
    --arg file "$file" \
    --argjson line "$line" \
    --arg rule "$rule" \
    --arg severity "$severity" \
    --arg match "$match" \
    '{file: $file, line: $line, rule: $rule, severity: $severity, match: $match}' \
    >> "$ISSUES_TMP"
}

for f in "${FILES[@]}"; do
  # Rule 1 — portable shebang
  first=$(head -1 "$f")
  if [[ "$first" != "#!/usr/bin/env bash" ]]; then
    emit_issue "$f" 1 "non-portable-shebang" "WARN" "$first"
  fi

  # Rule 2 — declare -A (bash 3.2 incompatible)
  while IFS=: read -r line content; do
    emit_issue "$f" "$line" "bash3.2-declare-A" "ERROR" "$content"
  done < <(grep -nE '^\s*declare\s+-[a-zA-Z]*A' "$f" || true)

  # Rule 3 — mapfile / readarray (bash 4+)
  while IFS=: read -r line content; do
    emit_issue "$f" "$line" "bash4-mapfile-readarray" "ERROR" "$content"
  done < <(grep -nE '^\s*(mapfile|readarray)\b' "$f" || true)

  # Rule 4 — sed -i without backup suffix
  # GNU: `sed -i 's/a/b/' file`  works
  # BSD: `sed -i '' 's/a/b/' file` required
  # Portable: `sed -i.bak 's/a/b/' file && rm file.bak`
  while IFS=: read -r line content; do
    # Skip comment lines (the checker itself documents these patterns)
    echo "$content" | grep -qE '^\s*#' && continue
    if echo "$content" | grep -qE 'sed[[:space:]]+-i([[:space:]]+[^.'\'']|$)'; then
      emit_issue "$f" "$line" "sed-i-bsd-gnu-divergence" "WARN" "$content"
    fi
  done < <(grep -nE 'sed[[:space:]]+-i' "$f" || true)

  # Rule 5 — readlink -f (BSD doesn't have it)
  while IFS=: read -r line content; do
    # Skip comment lines
    echo "$content" | grep -qE '^\s*#' && continue
    emit_issue "$f" "$line" "readlink-f-bsd-incompatible" "WARN" "$content"
  done < <(grep -nE 'readlink[[:space:]]+-f' "$f" || true)
done

# Optional: shellcheck (WARN-only)
SHELLCHECK_NOTE=""
if command -v shellcheck >/dev/null 2>&1; then
  for f in "${FILES[@]}"; do
    while IFS= read -r issue; do
      SHELLCHECK_NOTE="$SHELLCHECK_NOTE\n$issue"
    done < <(shellcheck -f gcc "$f" 2>/dev/null | head -5 || true)
  done
fi

ISSUES_JSON='[]'
if [[ -s "$ISSUES_TMP" ]]; then
  ISSUES_JSON=$(jq -s '.' "$ISSUES_TMP")
fi

ERROR_COUNT=$(echo "$ISSUES_JSON" | jq '[.[] | select(.severity == "ERROR")] | length')
WARN_COUNT=$(echo "$ISSUES_JSON" | jq '[.[] | select(.severity == "WARN")] | length')

if (( ERROR_COUNT > 0 )); then
  VERDICT="FAIL"
elif (( WARN_COUNT > 0 )); then
  VERDICT="WARN"
else
  VERDICT="OK"
fi

jq -n \
  --argjson scanned "${#FILES[@]}" \
  --argjson issues "$ISSUES_JSON" \
  --arg verdict "$VERDICT" \
  --argjson errors "$ERROR_COUNT" \
  --argjson warnings "$WARN_COUNT" \
  '{scanned: $scanned, errors: $errors, warnings: $warnings, issues: $issues, verdict: $verdict}'

(( ERROR_COUNT > 0 )) && exit 1 || exit 0
