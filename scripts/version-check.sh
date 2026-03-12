#!/usr/bin/env bash
# =============================================================================
# Version Check — Compare local version against GitHub release
# =============================================================================
# Usage:
#   bash scripts/version-check.sh
#   pnpm version:check
#
# Compares local VERSION file against the latest GitHub release tag.
# Useful for checking if a new version has been published.
#
# Exit codes:
#   0 = check completed (regardless of match)
#   1 = VERSION file not found or network error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
REPO="qwedsazxc78/devops-ai-skill"

# Read local version
if [ -f "$VERSION_FILE" ]; then
    LOCAL_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
else
    echo "ERROR: VERSION file not found at $VERSION_FILE"
    exit 1
fi

echo "DevOps AI Skill Pack — Version Check"
echo "====================================="
echo "Local version:  v$LOCAL_VERSION"

# Check remote version (GitHub API)
if command -v curl &>/dev/null; then
    REMOTE_VERSION=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || echo "")

    if [ -z "$REMOTE_VERSION" ]; then
        # Fallback: check git tags
        if command -v git &>/dev/null && git remote get-url origin &>/dev/null; then
            REMOTE_VERSION=$(git ls-remote --tags origin "v*" 2>/dev/null | tail -1 | sed -E 's/.*refs\/tags\/v?//' || echo "")
        fi
    fi

    if [ -n "$REMOTE_VERSION" ]; then
        echo "Remote version: v$REMOTE_VERSION"
        echo ""

        if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
            echo "Status: UP TO DATE"
        else
            echo "Status: UPDATE AVAILABLE"
            echo ""
            echo "To update:"
            echo "  git pull origin main"
            echo ""
            echo "Or pin to specific version:"
            echo "  git checkout v$REMOTE_VERSION"
        fi
    else
        echo "Remote version: (unable to check)"
        echo ""
        echo "Status: UNKNOWN (offline or repo not published yet)"
    fi
else
    echo "Remote version: (curl not available)"
    echo ""
    echo "Status: UNKNOWN"
fi
