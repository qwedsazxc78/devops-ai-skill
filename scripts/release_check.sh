#!/usr/bin/env bash
# =============================================================================
# release_check.sh — top-level orchestrator that runs every release-validate
# phase and renders the release artifact.
# =============================================================================
# Used by:
#   - Operators (pre-release manual check): bash scripts/release_check.sh
#   - CI (.github/workflows/release.yml)
#
# Exit codes:
#   0   overall verdict PASS or WARN
#   1   overall verdict FAIL → release should not proceed
#   2   tooling / setup missing
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION=$(cat VERSION | tr -d '[:space:]')
REPORT_DIR="docs/reports/release-validate/$VERSION"
mkdir -p "$REPORT_DIR"

SCRIPTS=skills/release-validate/scripts
[[ -d "$SCRIPTS" ]] || { echo "release-validate scripts not found at $SCRIPTS" >&2; exit 2; }

echo "release_check: running 4 phases for v$VERSION"

echo "  [4/4] Phase 4 — skill fixture suites"
bash "$SCRIPTS/run_all_fixtures.sh" "$ROOT_DIR" > "$REPORT_DIR/fixtures.json" || FIX_RC=$?

echo "  [4/4] Phase 5 — shell portability"
bash "$SCRIPTS/check_shell_portability.sh" "$ROOT_DIR" > "$REPORT_DIR/portability.json" || PORT_RC=$?

echo "  [4/4] Phase 6 — repo-style coverage"
bash "$SCRIPTS/check_repo_style_coverage.sh" --repo-root "$ROOT_DIR" > "$REPORT_DIR/repo-style.json"

echo "  [4/4] Phase 7 — AI-tool parity"
bash "$SCRIPTS/check_ai_tool_parity.sh" --repo-root "$ROOT_DIR" --all > "$REPORT_DIR/ai-parity.json" || PARITY_RC=$?

echo "  [render] aggregating into $REPORT_DIR/RELEASE-CHECK.md"
VERSION="$VERSION" \
  FIXTURES_JSON="$REPORT_DIR/fixtures.json" \
  PORTABILITY_JSON="$REPORT_DIR/portability.json" \
  REPO_STYLE_JSON="$REPORT_DIR/repo-style.json" \
  AI_TOOL_PARITY_JSON="$REPORT_DIR/ai-parity.json" \
  OUTPUT="$REPORT_DIR/RELEASE-CHECK.md" \
  bash "$SCRIPTS/render_release_artifact.sh"
