#!/usr/bin/env bash
set -euo pipefail

# Setup Google Gemini CLI
# Generates gemini-extension.json from shared skills/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Setting up Google Gemini CLI..."

# Verify GEMINI.md exists
if [ -f "$ROOT_DIR/GEMINI.md" ]; then
    echo "  [ok] GEMINI.md found"
else
    echo "  [warn] GEMINI.md not found at project root"
fi

# Verify agent definitions
for agent in horus zeus; do
    if [ -f "$ROOT_DIR/.gemini/agents/$agent.md" ]; then
        echo "  [ok] .gemini/agents/$agent.md found"
    else
        echo "  [warn] .gemini/agents/$agent.md not found"
    fi
done

# Verify extension
if [ -f "$ROOT_DIR/.gemini/extensions/devops/gemini-extension.json" ]; then
    echo "  [ok] gemini-extension.json found"
else
    echo "  [warn] gemini-extension.json not found"
fi

echo ""
echo "Gemini CLI setup complete!"
echo ""
echo "Start Gemini CLI in this directory to use the skill pack."
echo "GEMINI.md will be auto-loaded as the instruction file."
