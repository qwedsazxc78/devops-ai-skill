#!/usr/bin/env bash
# =============================================================================
# Version Bump — Update version across all config files
# =============================================================================
# Usage:
#   bash scripts/version-bump.sh <new-version>
#   bash scripts/version-bump.sh 1.1.0
# =============================================================================

set -euo pipefail

if [[ -z "${1:-}" ]]; then
  echo "Usage: bash scripts/version-bump.sh <new-version>"
  echo "Example: bash scripts/version-bump.sh 1.1.0"
  exit 1
fi

NEW_VERSION="$1"
OLD_VERSION=$(cat VERSION | tr -d '[:space:]')

# Validate semver format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "ERROR: Invalid semver format: $NEW_VERSION"
  echo "Expected: X.Y.Z or X.Y.Z-pre.N"
  exit 1
fi

echo "Bumping version: $OLD_VERSION → $NEW_VERSION"
echo ""

# 1. VERSION file
echo "$NEW_VERSION" > VERSION
echo "  ✓ VERSION"

# 2. package.json
sed -i.bak "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" package.json && rm -f package.json.bak
echo "  ✓ package.json"

# 3. .claude-plugin/plugin.json
sed -i.bak "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" .claude-plugin/plugin.json && rm -f .claude-plugin/plugin.json.bak
echo "  ✓ .claude-plugin/plugin.json"

# 4. .claude-plugin/marketplace.json
sed -i.bak "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" .claude-plugin/marketplace.json && rm -f .claude-plugin/marketplace.json.bak
echo "  ✓ .claude-plugin/marketplace.json"

# 5. .gemini/extensions/devops/gemini-extension.json
sed -i.bak "s/\"version\": \"$OLD_VERSION\"/\"version\": \"$NEW_VERSION\"/" .gemini/extensions/devops/gemini-extension.json && rm -f .gemini/extensions/devops/gemini-extension.json.bak
echo "  ✓ .gemini/extensions/devops/gemini-extension.json"

echo ""
echo "Done! All files updated to $NEW_VERSION"
echo ""
echo "Next: run 'pnpm release' to commit, tag, and push."
