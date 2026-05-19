#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
P6="$ROOT_DIR/skills/release-validate/scripts/check_repo_style_coverage.sh"

PASS=0
FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "release-validate fixtures (v1.15.0)"
echo "----------------------------------"

echo "[1] phase6-complete (matrix declares kustomize-argocd, fixture present)"
out=$(bash "$P6" \
  --repo-root "$SCRIPT_DIR/fixtures/phase6-complete" \
  --matrix-skills "dummy-skill" \
  --matrix-styles "kustomize-argocd" \
  --matrix-required "dummy-skill:kustomize-argocd" 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
if [[ "$verdict" == "OK" ]]; then
  echo "  [PASS] verdict=OK (no missing styles)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected verdict=OK, got $verdict"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo "[2] phase6-missing-style (matrix declares helm-only required, fixture absent)"
out=$(bash "$P6" \
  --repo-root "$SCRIPT_DIR/fixtures/phase6-missing-style" \
  --matrix-skills "dummy-skill" \
  --matrix-styles "kustomize-argocd helm-only" \
  --matrix-required "dummy-skill:kustomize-argocd,dummy-skill:helm-only" 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
missing=$(echo "$out" | jq -r '.missing[0] // "none"')
missing_count=$(echo "$out" | jq -r '.missing | length')
if [[ "$verdict" == "WARN" && "$missing" == "dummy-skill:helm-only" && "$missing_count" == "1" ]]; then
  echo "  [PASS] verdict=WARN, missing=dummy-skill:helm-only, missing_count=1"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected WARN + helm-only missing (count=1); got verdict=$verdict missing=$missing count=$missing_count"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

P7="$ROOT_DIR/skills/release-validate/scripts/check_ai_tool_parity.sh"

echo "[3] phase7-all-platforms (one command, registered everywhere)"
out=$(bash "$P7" \
  --repo-root "$SCRIPT_DIR/fixtures/phase7-all-platforms" \
  --command example-cmd 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
if [[ "$verdict" == "OK" ]]; then
  echo "  [PASS] verdict=OK (registered on all 4 platforms)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected OK, got $verdict"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo "[4] phase7-missing-claude (CLAUDE.md row absent)"
out=$(bash "$P7" \
  --repo-root "$SCRIPT_DIR/fixtures/phase7-missing-claude" \
  --command example-cmd 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
gaps=$(echo "$out" | jq -r '[.commands[].gaps[].platform] | first // "none"')
if [[ "$verdict" == "FAIL" && "$gaps" == "claude" ]]; then
  echo "  [PASS] verdict=FAIL, gap=claude"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected FAIL+claude gap; got verdict=$verdict gap=$gaps"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo "[5] phase7-name-mismatch (basename 'long-name' resolves to registered '*short')"
out=$(bash "$P7" \
  --repo-root "$SCRIPT_DIR/fixtures/phase7-name-mismatch" \
  --command long-name 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
registered=$(echo "$out" | jq -r '.commands[0].registeredAs')
if [[ "$verdict" == "OK" && "$registered" == "short" ]]; then
  echo "  [PASS] verdict=OK, registeredAs=short (basename resolved correctly)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected OK+registeredAs=short; got verdict=$verdict registeredAs=$registered"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo ""
echo "release-validate: $PASS passed, $FAIL failed"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
