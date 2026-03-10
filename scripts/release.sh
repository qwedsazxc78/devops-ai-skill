#!/usr/bin/env bash
# =============================================================================
# Release — Commit version bump, create tag, and push
# =============================================================================
# Usage:
#   bash scripts/release.sh          # Use version from VERSION file
#   pnpm release                      # Same via pnpm script
#
# Prerequisites:
#   1. Run 'pnpm version:bump <version>' first
#   2. Ensure all changes are committed or staged
# =============================================================================

set -euo pipefail

VERSION=$(cat VERSION | tr -d '[:space:]')
TAG="v$VERSION"

echo "Release: $TAG"
echo "=========================================="

# Check if tag already exists
if git rev-parse "$TAG" &>/dev/null; then
  echo "ERROR: Tag $TAG already exists."
  echo "If you want to re-release, delete it first:"
  echo "  git tag -d $TAG && git push origin :refs/tags/$TAG"
  exit 1
fi

# Check for uncommitted changes
if [[ -n "$(git status --porcelain)" ]]; then
  echo ""
  echo "Staging and committing version bump..."
  git add VERSION package.json .claude-plugin/ .gemini/extensions/
  git commit -m "chore(release): bump version to $VERSION"
  echo "  ✓ Committed"
fi

# Create tag
git tag -a "$TAG" -m "Release $TAG"
echo "  ✓ Tag $TAG created"

# Push commit and tag
echo ""
echo "Pushing to origin..."
git push origin main
git push origin "$TAG"
echo "  ✓ Pushed"

echo ""
echo "=========================================="
echo "Release $TAG pushed!"
echo ""
echo "GitHub Actions will automatically:"
echo "  1. Create GitHub Release"
echo "  2. Publish to npm (devops-ai-skill)"
echo ""
echo "Monitor: https://github.com/qwedsazxc78/devops-ai-skill/actions"
