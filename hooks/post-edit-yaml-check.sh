#!/usr/bin/env bash
# H2: PostToolUse on Edit|Write -- quick YAML lint after edits in Kustomize-shaped repos.
# Maps to skill: yaml-fix-suggestions
# Mode: advisory (stderr only; never blocks)
#
# Reference: https://github.com/qwedsazxc78/devops-ai-skill/tree/main/skills/yaml-fix-suggestions

set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$file" ] && exit 0

# Only YAML files
case "$file" in
  *.yaml|*.yml) ;;
  *) exit 0 ;;
esac

# Skip noise paths
case "$file" in
  *.claude/*|*.bmad-*|*node_modules*|*.git/*|*.terraform/*) exit 0 ;;
esac

# Heuristic: only fire inside Kustomize-shaped trees (kustomization.yaml within 2 levels up)
dir=$(dirname "$file")
found_kust=false
for try in "$dir" "$dir/.." "$dir/../.."; do
  if [ -f "$try/kustomization.yaml" ] || [ -f "$try/kustomization.yml" ]; then
    found_kust=true
    break
  fi
done
$found_kust || exit 0

# Only proceed if file actually exists (Edit may have failed)
[ -f "$file" ] || exit 0

if command -v yamllint >/dev/null 2>&1; then
  if ! out=$(yamllint --no-warnings "$file" 2>&1); then
    {
      echo "[yaml-fix-suggestions hook] $file:"
      printf '%s\n' "$out" | head -20
      echo "Run: /devops:zeus -> *validate  (full check)"
      echo "Or:  yamllint $file"
    } >&2
  fi
else
  # Fallback: basic checks (no external deps)
  warned=false
  if grep -nP '\t' "$file" >/dev/null 2>&1 || grep -n $'\t' "$file" >/dev/null 2>&1; then
    echo "[yaml-fix-suggestions hook] $file: contains tabs (use 2-space indent)" >&2
    warned=true
  fi
  if grep -nE '[[:space:]]+$' "$file" >/dev/null 2>&1; then
    echo "[yaml-fix-suggestions hook] $file: trailing whitespace" >&2
    warned=true
  fi
  if $warned; then
    echo "[yaml-fix-suggestions hook] Tip: install 'yamllint' for full check." >&2
  fi
fi

exit 0
