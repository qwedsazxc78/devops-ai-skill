#!/usr/bin/env bash
set -euo pipefail

# Setup OpenAI Codex CLI skill symlinks
# Creates .codex/skills/ symlinks pointing to shared skills/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="$ROOT_DIR/skills"
CODEX_SKILLS_DIR="$ROOT_DIR/.codex/skills"

echo "Setting up OpenAI Codex CLI skills..."

# Create skills directory if needed
mkdir -p "$CODEX_SKILLS_DIR"

# Create symlinks for each skill
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$CODEX_SKILLS_DIR/$skill_name"

    if [ -L "$target" ]; then
        echo "  [skip] $skill_name (symlink exists)"
    elif [ -d "$target" ]; then
        echo "  [skip] $skill_name (directory exists)"
    else
        ln -s "../../skills/$skill_name" "$target"
        echo "  [link] $skill_name → skills/$skill_name"
    fi
done

# Copy AGENTS.md to project root if not already there
if [ ! -f "$ROOT_DIR/AGENTS.md" ]; then
    echo "  [warn] AGENTS.md not found at project root"
fi

echo ""
echo "Codex CLI setup complete!"
echo "Skills linked: $(ls -1 "$CODEX_SKILLS_DIR" | wc -l | tr -d ' ')"
echo ""
echo "Start Codex in this directory to use the skills."
