#!/usr/bin/env bash
# =============================================================================
# Version Consistency — Verify all config files match VERSION
# =============================================================================
# Usage:
#   bash scripts/version-consistency.sh              # Check only
#   bash scripts/version-consistency.sh --tag v1.0.0 # Also verify tag matches
#
# Exit codes:
#   0 = all consistent
#   1 = mismatch found
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
ERRORS=0

echo "Version Consistency Check"
echo "========================="
echo "VERSION file: $VERSION"
echo ""

# Optional: verify tag matches VERSION
if [[ "${1:-}" == "--tag" && -n "${2:-}" ]]; then
  TAG_VERSION="${2#v}"
  if [[ "$TAG_VERSION" != "$VERSION" ]]; then
    echo "FAIL: Tag $2 ($TAG_VERSION) does not match VERSION file ($VERSION)"
    ERRORS=$((ERRORS + 1))
  else
    echo "  ✓ Tag $2 matches VERSION"
  fi
fi

# Check package.json
PKG_V=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/package.json'))['version'])")
if [[ "$PKG_V" == "$VERSION" ]]; then
  echo "  ✓ package.json: $PKG_V"
else
  echo "  ✗ package.json: $PKG_V (expected $VERSION)"
  ERRORS=$((ERRORS + 1))
fi

# Check plugin.json
PLUGIN_V=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/plugin.json'))['version'])")
if [[ "$PLUGIN_V" == "$VERSION" ]]; then
  echo "  ✓ plugin.json: $PLUGIN_V"
else
  echo "  ✗ plugin.json: $PLUGIN_V (expected $VERSION)"
  ERRORS=$((ERRORS + 1))
fi

# Check marketplace.json
MP_V=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/marketplace.json'))['metadata']['version'])")
if [[ "$MP_V" == "$VERSION" ]]; then
  echo "  ✓ marketplace.json: $MP_V"
else
  echo "  ✗ marketplace.json: $MP_V (expected $VERSION)"
  ERRORS=$((ERRORS + 1))
fi

# Check gemini-extension.json
GEM_V=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.gemini/extensions/devops/gemini-extension.json'))['version'])")
if [[ "$GEM_V" == "$VERSION" ]]; then
  echo "  ✓ gemini-extension.json: $GEM_V"
else
  echo "  ✗ gemini-extension.json: $GEM_V (expected $VERSION)"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "All versions consistent: $VERSION"
  exit 0
else
  echo "FAIL: $ERRORS version mismatch(es) found"
  echo "Run: npm run version:bump $VERSION"
  exit 1
fi
