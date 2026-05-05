#!/usr/bin/env bash
# H3: PostToolUse on Edit|Write -- quick fmt + tflint after .tf/.tfvars edits.
# Maps to skill: terraform-validate
# Mode: advisory (stderr only; never blocks)
#
# Reference: https://github.com/qwedsazxc78/devops-ai-skill/tree/main/skills/terraform-validate
# Practice repo: https://github.com/qwedsazxc78/iac-template-ai-skill

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

case "$file" in
  *.tf|*.tfvars) ;;
  *) exit 0 ;;
esac

case "$file" in
  *.terraform/*|*node_modules*|*.git/*) exit 0 ;;
esac

[ -f "$file" ] || exit 0

# fmt check
if command -v terraform >/dev/null 2>&1; then
  if ! terraform fmt -check -no-color "$file" >/dev/null 2>&1; then
    {
      echo "[terraform-validate hook] $file: fmt drift"
      echo "Fix:  terraform fmt $file"
    } >&2
  fi
else
  echo "[terraform-validate hook] terraform CLI not found -- skipping fmt check" >&2
fi

# tflint (optional)
if command -v tflint >/dev/null 2>&1; then
  dir=$(dirname "$file")
  while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
    if [ -f "$dir/.tflint.hcl" ]; then
      if ! out=$(cd "$dir" && tflint --no-color --filter "$(basename "$file")" 2>&1); then
        {
          echo "[terraform-validate hook] tflint findings:"
          printf '%s\n' "$out" | head -15
          echo "Run: /devops:horus -> *validate  (full check)"
        } >&2
      fi
      break
    fi
    parent=$(dirname "$dir")
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
fi

exit 0
