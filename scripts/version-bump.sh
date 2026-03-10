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

# 6. CHANGELOG.md — scaffold new entry if not present
if ! grep -q "## \[$NEW_VERSION\]" CHANGELOG.md; then
  TODAY=$(date +%Y-%m-%d)
  REPO_URL="https://github.com/qwedsazxc78/devops-ai-skill"

  # Insert new entry before the first existing version heading (awk for portability)
  awk -v ver="$NEW_VERSION" -v date="$TODAY" '
    /^## \[/ && !inserted {
      print "## [" ver "] - " date
      print ""
      print "### Added"
      print ""
      print "- (describe changes here)"
      print ""
      inserted=1
    }
    { print }
  ' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

  # Update comparison links at bottom
  # Insert new version compare link before existing links, keep old links intact
  if grep -q "^\[${OLD_VERSION}\]: " CHANGELOG.md; then
    sed -i.bak "/^\[${OLD_VERSION}\]: /i\\
[${NEW_VERSION}]: ${REPO_URL}/compare/v${OLD_VERSION}...v${NEW_VERSION}
" CHANGELOG.md && rm -f CHANGELOG.md.bak
  else
    # First release has no links yet — append both
    echo "[${NEW_VERSION}]: ${REPO_URL}/compare/v${OLD_VERSION}...v${NEW_VERSION}" >> CHANGELOG.md
    echo "[${OLD_VERSION}]: ${REPO_URL}/releases/tag/v${OLD_VERSION}" >> CHANGELOG.md
  fi
  echo "  ✓ CHANGELOG.md (scaffolded entry for $NEW_VERSION)"
else
  echo "  ✓ CHANGELOG.md (entry already exists)"
fi

echo ""
echo "Done! All files updated to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Edit CHANGELOG.md — fill in the changes for $NEW_VERSION"
echo "  2. Run 'pnpm release' to commit, tag, and push"
