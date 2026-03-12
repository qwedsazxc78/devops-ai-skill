#!/usr/bin/env bash
# =============================================================================
# Setup Antigravity — Create skill and workflow symlinks for Antigravity
# =============================================================================
# Usage:
#   bash scripts/setup/setup-antigravity.sh
#   bash node_modules/devops-ai-skill/scripts/setup/setup-antigravity.sh
#
# Creates .agents/skills/ symlinks pointing to shared skills/ directory.
# Creates .agents/workflows/ symlinks pointing to prompts/ directory.
# Safe: skips existing symlinks.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$ROOT_DIR/skills"
AGENTS_SKILLS_DIR="$ROOT_DIR/.agents/skills"
AGENTS_WORKFLOWS_DIR="$ROOT_DIR/.agents/workflows"

echo "Setting up Google Antigravity..."

# --- Verify rules file ---
if [ -f "$ROOT_DIR/.agents/rules/devops.md" ]; then
    echo "  [ok] .agents/rules/devops.md found"
else
    echo "  [warn] .agents/rules/devops.md not found"
fi

# --- Verify agent-as-skill wrappers ---
for agent in horus zeus; do
    if [ -f "$ROOT_DIR/.agents/skills/$agent/SKILL.md" ]; then
        echo "  [ok] .agents/skills/$agent/SKILL.md found"
    else
        echo "  [warn] .agents/skills/$agent/SKILL.md not found"
    fi
done

# --- Create skill symlinks ---
mkdir -p "$AGENTS_SKILLS_DIR"

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$AGENTS_SKILLS_DIR/$skill_name"

    if [ -L "$target" ]; then
        echo "  [skip] $skill_name (symlink exists)"
    elif [ -d "$target" ]; then
        echo "  [skip] $skill_name (directory exists)"
    else
        ln -s "../../skills/$skill_name" "$target"
        echo "  [link] $skill_name → skills/$skill_name"
    fi
done

# --- Create workflow symlinks ---
mkdir -p "$AGENTS_WORKFLOWS_DIR"

# Helper: create a workflow symlink
link_workflow() {
    local name="$1"
    local src="$2"
    local target="$AGENTS_WORKFLOWS_DIR/${name}.md"
    if [ -L "$target" ] || [ -f "$target" ]; then
        echo "  [skip] workflow $name (exists)"
    else
        ln -s "$src" "$target"
        echo "  [link] workflow $name"
    fi
}

# Horus workflows
link_workflow "horus-full"       "../../prompts/horus/full-pipeline.md"
link_workflow "horus-upgrade"    "../../prompts/horus/upgrade.md"
link_workflow "horus-security"   "../../prompts/horus/security.md"
link_workflow "horus-validate"   "../../prompts/horus/validate.md"
link_workflow "horus-new-module" "../../prompts/horus/new-module.md"
link_workflow "horus-cicd"       "../../prompts/horus/cicd.md"
link_workflow "horus-health"     "../../prompts/horus/health.md"

# Zeus workflows
link_workflow "zeus-full"         "../../prompts/zeus/full-pipeline.md"
link_workflow "zeus-pre-merge"    "../../prompts/zeus/pre-merge.md"
link_workflow "zeus-health-check" "../../prompts/zeus/health-check.md"
link_workflow "zeus-review"       "../../prompts/zeus/review.md"
link_workflow "zeus-onboard"      "../../prompts/zeus/onboard.md"
link_workflow "zeus-diagram"      "../../prompts/zeus/diagram.md"
link_workflow "zeus-status"       "../../prompts/zeus/status.md"

# Shared workflows
link_workflow "shared-repo-detect"    "../../prompts/shared/repo-detect.md"
link_workflow "shared-report-format"  "../../prompts/shared/report-format.md"
link_workflow "shared-tool-check"     "../../prompts/shared/tool-check.md"

echo ""
echo "Antigravity setup complete!"
echo "Skills linked: $(find "$AGENTS_SKILLS_DIR" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')"
echo "Workflows linked: $(find "$AGENTS_WORKFLOWS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
echo ""
echo "Open this directory in Antigravity to use the skill pack."
echo "Skills and workflows will be auto-discovered from .agents/"
