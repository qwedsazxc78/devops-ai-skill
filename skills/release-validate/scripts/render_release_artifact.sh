#!/usr/bin/env bash
# render_release_artifact.sh — aggregate release-validate phases into a
# single Markdown artifact suitable for `gh release create --notes-file`.
#
# Inputs (env vars):
#   VERSION              — current VERSION file content (e.g. "1.15.0")
#   FIXTURES_JSON        — output of run_all_fixtures.sh (Phase 4)
#   PORTABILITY_JSON     — output of check_shell_portability.sh (Phase 5)
#   REPO_STYLE_JSON      — output of check_repo_style_coverage.sh (Phase 6, optional)
#   AI_TOOL_PARITY_JSON  — output of check_ai_tool_parity.sh (Phase 7, optional)
#   OUTPUT               — absolute path to write the .md file
#
# Phase 6 and 7 inputs are optional for backwards-compat with v1.14.0
# callers; when absent, only Phases 4 + 5 are rendered.
#
# Output:
#   $OUTPUT — Markdown release artifact
#   stdout — a one-line verdict summary
#
# Exit codes:
#   0   artifact written, overall verdict PASS or WARN
#   1   any phase verdict FAIL → release blocked
set -euo pipefail

: "${VERSION:?VERSION required}"
: "${FIXTURES_JSON:?FIXTURES_JSON required (path)}"
: "${PORTABILITY_JSON:?PORTABILITY_JSON required (path)}"
: "${OUTPUT:?OUTPUT required}"

command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

# Parse aggregated phase outputs
FIX_VERDICT=$(jq -r '.verdict' "$FIXTURES_JSON")
FIX_TOTAL_PASS=$(jq -r '.totalPass' "$FIXTURES_JSON")
FIX_TOTAL_FAIL=$(jq -r '.totalFail' "$FIXTURES_JSON")
FIX_SUITES=$(jq -r '.totalSuites' "$FIXTURES_JSON")

PORT_VERDICT=$(jq -r '.verdict' "$PORTABILITY_JSON")
PORT_SCANNED=$(jq -r '.scanned' "$PORTABILITY_JSON")
PORT_ERRORS=$(jq -r '.errors' "$PORTABILITY_JSON")
PORT_WARNINGS=$(jq -r '.warnings' "$PORTABILITY_JSON")

# Optional Phase 6
RS_VERDICT="SKIPPED"
RS_SCANNED=0
RS_MISSING=0
RS_PCT=0
if [[ -n "${REPO_STYLE_JSON:-}" && -f "$REPO_STYLE_JSON" ]]; then
  RS_VERDICT=$(jq -r '.verdict' "$REPO_STYLE_JSON")
  RS_SCANNED=$(jq -r '.scanned' "$REPO_STYLE_JSON")
  RS_MISSING=$(jq -r '.missing | length' "$REPO_STYLE_JSON")
  RS_PCT=$(jq -r '.coveragePct' "$REPO_STYLE_JSON")
fi

# Optional Phase 7
PARITY_VERDICT="SKIPPED"
PARITY_CMD_COUNT=0
PARITY_GAP_COUNT=0
if [[ -n "${AI_TOOL_PARITY_JSON:-}" && -f "$AI_TOOL_PARITY_JSON" ]]; then
  PARITY_VERDICT=$(jq -r '.verdict' "$AI_TOOL_PARITY_JSON")
  PARITY_CMD_COUNT=$(jq -r '.commands | length' "$AI_TOOL_PARITY_JSON")
  PARITY_GAP_COUNT=$(jq -r '[.commands[].gaps[]] | length' "$AI_TOOL_PARITY_JSON")
fi

# Compose overall verdict. FAIL > WARN > OK > SKIPPED.
OVERALL="PASS"
for v in "$PORT_VERDICT" "$FIX_VERDICT" "$RS_VERDICT" "$PARITY_VERDICT"; do
  case "$v" in
    FAIL) OVERALL="FAIL" ;;
    WARN) [[ "$OVERALL" != "FAIL" ]] && OVERALL="WARN" ;;
  esac
done

# Build the per-suite table
SUITE_ROWS=$(jq -r '.suites[] | "| \(.name) | \(.pass) | \(.fail) | \(.verdict) |"' "$FIXTURES_JSON")
PORT_ISSUE_ROWS=$(jq -r '.issues[]? | "| \(.file):\(.line) | \(.severity) | \(.rule) |"' "$PORTABILITY_JSON" || echo "| _none_ | | |")

mkdir -p "$(dirname "$OUTPUT")"

cat > "$OUTPUT" <<EOF
# Release Check — v${VERSION}

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Overall verdict**: **${OVERALL}**

## Summary

| Phase | Verdict | Detail |
|---|---|---|
| 4. Fixture suites    | ${FIX_VERDICT}    | ${FIX_TOTAL_PASS} PASS / ${FIX_TOTAL_FAIL} FAIL across ${FIX_SUITES} suites |
| 5. Shell portability | ${PORT_VERDICT}   | ${PORT_SCANNED} scripts scanned, ${PORT_ERRORS} errors, ${PORT_WARNINGS} warnings |
| 6. Repo-style coverage | ${RS_VERDICT} | ${RS_SCANNED} required entries, ${RS_MISSING} missing (${RS_PCT}% coverage) |
| 7. AI-tool parity    | ${PARITY_VERDICT} | ${PARITY_CMD_COUNT} commands scanned, ${PARITY_GAP_COUNT} registration gaps |

## Phase 4 — Skill fixture suites

| Suite | PASS | FAIL | Verdict |
|---|---|---|---|
${SUITE_ROWS}

## Phase 5 — Shell portability static checks

Scanned: ${PORT_SCANNED} \`.sh\` files under \`skills/\` and \`scripts/\`.

Rules:
1. Portable shebang (\`#!/usr/bin/env bash\`)
2. No \`declare -A\` (bash 3.2 incompatible)
3. No \`mapfile\`/\`readarray\` (bash 4+)
4. No \`sed -i\` without backup suffix (BSD vs GNU divergence)
5. No \`readlink\` with the \`-f\` flag (BSD lacks it; use \`cd && pwd\` instead)

| Location | Severity | Rule |
|---|---|---|
${PORT_ISSUE_ROWS}

## Phase 6 — Repo-style coverage

Matrix: \`skills/release-validate/references/repo-style-matrix.md\`

| Metric | Value |
|---|---|
| Required entries scanned | ${RS_SCANNED} |
| Missing fixtures | ${RS_MISSING} |
| Coverage | ${RS_PCT}% |
| Verdict | ${RS_VERDICT} |

WARN-only — gaps surface as follow-up work, not release blockers.

## Phase 7 — Cross-AI-tool parity

| Metric | Value |
|---|---|
| Commands scanned | ${PARITY_CMD_COUNT} |
| Registration gaps | ${PARITY_GAP_COUNT} |
| Verdict | ${PARITY_VERDICT} |

A FAIL verdict here blocks the release: every Zeus command must be
registered across all 4 AI-tool surfaces (Claude / Codex via CLAUDE.md /
AGENTS.md / GEMINI.md / docs/PROJECT.md + Gemini TOML mirror).

## How to interpret

- **PASS** — release is green; safe to \`pnpm release\`.
- **WARN** — release is acceptable but has portability or coverage gaps. Review the issue list; consider fixing in a follow-up.
- **FAIL** — at least one fixture suite errored or a shell script has a hard-incompatibility. Do NOT release.

## Next steps

\`\`\`bash
# If verdict is PASS or WARN:
pnpm release   # triggers GitHub Actions release.yml

# If verdict is FAIL:
# fix the failing suite / portability issue, then re-run:
bash skills/release-validate/scripts/run_all_fixtures.sh
bash skills/release-validate/scripts/check_shell_portability.sh .
\`\`\`

---

_Generated by \`release-validate\` skill v1.15.0. This artifact is suitable
for the \`gh release create --notes-file\` body, or as the npm publish
README excerpt._
EOF

# Print a one-line summary suitable for CI logs
echo "release-validate v${VERSION}: ${OVERALL} (fixtures=${FIX_VERDICT}, portability=${PORT_VERDICT}, repoStyle=${RS_VERDICT}, parity=${PARITY_VERDICT})"

[[ "$OVERALL" == "FAIL" ]] && exit 1 || exit 0
