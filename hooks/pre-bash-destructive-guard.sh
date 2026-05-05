#!/usr/bin/env bash
# H4: PreToolUse on Bash -- ask user before destructive DevOps commands.
# Maps to skill philosophy: terraform-security (responsibility seam)
# Mode: gate (permissionDecision=ask; never auto-denies)
#
# Patterns gated:
#   - terraform apply
#   - terraform destroy
#   - helm uninstall
#   - kubectl delete
#   - argocd app delete
#
# Reference: https://github.com/qwedsazxc78/devops-ai-skill

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

[ -z "$cmd" ] && exit 0

# Match destructive patterns. Word-boundary-aware: must follow start-of-string,
# whitespace, ; , && , || , or | -- avoids false positives on substrings.
matched=""
declare -a patterns=(
  "terraform apply"
  "terraform destroy"
  "helm uninstall"
  "kubectl delete"
  "argocd app delete"
)

for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -qE "(^|[[:space:]]|;|&&|\|\||\|)$p([[:space:]]|$)"; then
    matched="$p"
    break
  fi
done

[ -z "$matched" ] && exit 0

# Per-pattern dry-run suggestion
case "$matched" in
  "terraform apply")
    suggest="Consider: 'terraform plan -out=tfplan' first, then 'terraform apply tfplan'."
    ;;
  "terraform destroy")
    suggest="Consider: 'terraform plan -destroy' first to preview the blast radius."
    ;;
  "helm uninstall")
    suggest="Consider: 'helm list -n <ns>' to confirm target, or 'helm history <release>' for rollback context."
    ;;
  "kubectl delete")
    suggest="Consider: 'kubectl get <resource>' first, or '--dry-run=client -o yaml' to preview."
    ;;
  "argocd app delete")
    suggest="Consider: 'argocd app get <app>' + 'argocd app diff <app>' first; check sync policy."
    ;;
  *)
    suggest=""
    ;;
esac

REASON="Destructive DevOps command detected: '$matched'. $suggest" \
python3 - <<'PY'
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "ask",
        "permissionDecisionReason": os.environ.get("REASON", "")
    }
}))
PY
