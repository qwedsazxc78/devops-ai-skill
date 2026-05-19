#!/usr/bin/env bash
# Fixture runner for the ingress-migration-advisor skill.
# Mirrors the pattern in tests/nginx-to-traefik/run-fixtures.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$ROOT_DIR/skills/ingress-migration-advisor"
SCORE="$SKILL_DIR/scripts/score_services.py"

PASS=0
FAIL=0

# Shared temp area for actual outputs
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

#------------------------------------------------------------------------------
# Test helpers
#------------------------------------------------------------------------------

assert_scores_equal() {
  local name="$1" fixture="$2"
  local input_inv="$SCRIPT_DIR/fixtures/$fixture/input/inv.json"
  local input_map="$SCRIPT_DIR/fixtures/$fixture/input/tier-map.yaml"
  local expected="$SCRIPT_DIR/fixtures/$fixture/expected/scores.json"
  local actual="$TMP/$fixture-scores.json"

  python3 "$SCORE" --inventory "$input_inv" --tier-map "$input_map" > "$actual"

  if diff -u <(jq -S . "$expected") <(jq -S . "$actual") > "$TMP/$fixture-scores.diff" 2>&1; then
    echo "  [PASS] $name"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    sed 's/^/    /' "$TMP/$fixture-scores.diff"
    FAIL=$((FAIL+1))
  fi
}

assert_decisions_equal() {
  local name="$1" fixture="$2"
  local input_inv="$SCRIPT_DIR/fixtures/$fixture/input/inv.json"
  local input_map="$SCRIPT_DIR/fixtures/$fixture/input/tier-map.yaml"
  local expected="$SCRIPT_DIR/fixtures/$fixture/expected/decisions.json"
  local scores="$TMP/$fixture-scores.json"
  local actual="$TMP/$fixture-decisions.json"

  python3 "$SCORE" --inventory "$input_inv" --tier-map "$input_map" > "$scores"
  python3 "$SCORE" --decide --inventory "$input_inv" --scores "$scores" \
    | jq '{decisions}' > "$actual"

  if diff -u <(jq -S . "$expected") <(jq -S . "$actual") > "$TMP/$fixture-decisions.diff" 2>&1; then
    echo "  [PASS] $name"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    sed 's/^/    /' "$TMP/$fixture-decisions.diff"
    FAIL=$((FAIL+1))
  fi
}

#------------------------------------------------------------------------------
# Test cases
#------------------------------------------------------------------------------

echo "ingress-migration-advisor fixtures"
echo "----------------------------------"

echo "[1] critical-tier-veto (scoring)"
assert_scores_equal \
  "critical service is vetoed regardless of score" \
  "critical-tier-veto"

echo "[2] source-class-traefik-shortcut (decisions)"
assert_decisions_equal \
  "traefik-source service shortcuts to direct-gateway" \
  "source-class-traefik-shortcut"

echo "[3] score-band-direct-gateway (decisions)"
assert_decisions_equal \
  "low-score nginx services land in direct-gateway band" \
  "score-band-direct-gateway"

echo "[4] foreign-class-defer (decisions)"
assert_decisions_equal \
  "foreign-class services are vetoed to defer" \
  "foreign-class-defer"

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------

echo ""
echo "ingress-migration-advisor: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
