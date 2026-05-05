#!/usr/bin/env bash
# H1: SessionStart -- detect IaC vs GitOps repo and inject context for Claude.
# Maps to skill: repo-detect
# Mode: advisory (additionalContext only; never blocks)
#
# Reference repos:
#   - IaC template:    https://github.com/qwedsazxc78/iac-template-ai-skill
#   - GitOps template: https://github.com/qwedsazxc78/gitops-template-ai-skill
#   - Skill pack:      https://github.com/qwedsazxc78/devops-ai-skill

set -uo pipefail

cwd="${CLAUDE_PROJECT_DIR:-$PWD}"

has_terraform=false
has_kustomize=false
has_helm=false
has_argocd=false

if find "$cwd" -maxdepth 3 -type f -name "*.tf" \
    -not -path "*/node_modules/*" -not -path "*/.terraform/*" \
    -print -quit 2>/dev/null | grep -q .; then
  has_terraform=true
fi

if find "$cwd" -maxdepth 4 -type f -name "kustomization.yaml" \
    -not -path "*/node_modules/*" \
    -print -quit 2>/dev/null | grep -q .; then
  has_kustomize=true
fi

if find "$cwd" -maxdepth 3 -type f -name "Chart.yaml" \
    -not -path "*/node_modules/*" \
    -print -quit 2>/dev/null | grep -q .; then
  has_helm=true
fi

if find "$cwd" -maxdepth 5 -type f \( -name "Application.yaml" -o -name "application.yaml" -o -name "ApplicationSet.yaml" \) \
    -print -quit 2>/dev/null | grep -q .; then
  has_argocd=true
fi

# Build context. Stay silent if no DevOps signals -- avoid noise in unrelated projects.
ctx=""

if $has_terraform || $has_helm; then
  ctx+="DevOps signals: Terraform/Helm (IaC) detected.\n"
  ctx+="  -> Suggest agent: /devops:horus  (commands: *validate, *security, *upgrade)\n"
fi

if $has_kustomize || $has_argocd; then
  ctx+="DevOps signals: Kustomize/ArgoCD (GitOps) detected.\n"
  ctx+="  -> Suggest agent: /devops:zeus  (commands: *validate, *gateway-migrate)\n"
fi

if [ -z "$ctx" ]; then
  exit 0
fi

ctx+="\nReference repos (workshop demo branches: demo-conditioned/2026-ithome-devopsday):\n"
ctx+="  - IaC template:    https://github.com/qwedsazxc78/iac-template-ai-skill\n"
ctx+="  - GitOps template: https://github.com/qwedsazxc78/gitops-template-ai-skill\n"
ctx+="  - Skill pack:      https://github.com/qwedsazxc78/devops-ai-skill\n"

# Emit JSON via python3 (ships on macOS; standard on Linux dev images)
CTX="$ctx" python3 - <<'PY'
import json, os
ctx = os.environ.get("CTX", "")
# Convert literal "\n" sequences from bash string concat to real newlines
ctx = ctx.replace("\\n", "\n")
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": ctx,
    }
}))
PY
