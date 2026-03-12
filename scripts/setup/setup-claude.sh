#!/usr/bin/env bash
# =============================================================================
# Setup Claude Code — Create skill symlinks for Claude Code
# =============================================================================
# Usage:
#   bash scripts/setup/setup-claude.sh
#   bash node_modules/devops-ai-skill/scripts/setup/setup-claude.sh
#
# Creates .claude/skills/ symlinks pointing to shared skills/ directory.
# Safe: skips existing symlinks.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$ROOT_DIR/skills"
CLAUDE_SKILLS_DIR="$ROOT_DIR/.claude/skills"

echo "Setting up Claude Code skills..."

# Create skills directory if needed
mkdir -p "$CLAUDE_SKILLS_DIR"

# Create symlinks for each skill
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$CLAUDE_SKILLS_DIR/$skill_name"

    if [ -L "$target" ]; then
        echo "  [skip] $skill_name (symlink exists)"
    elif [ -d "$target" ]; then
        echo "  [skip] $skill_name (directory exists)"
    else
        # Use relative symlinks for portability
        ln -s "../../skills/$skill_name" "$target"
        echo "  [link] $skill_name → skills/$skill_name"
    fi
done

echo ""
echo "Claude Code setup complete!"
echo "Skills linked: $(ls -1 "$CLAUDE_SKILLS_DIR" | wc -l | tr -d ' ')"
echo ""
echo "To use: claude --plugin-dir $ROOT_DIR"
