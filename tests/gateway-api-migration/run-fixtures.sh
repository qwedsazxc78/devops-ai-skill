#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

for fixture in "$FIXTURES_DIR"/*/; do
  # Skip if glob didn't match any real directories (empty fixtures/)
  [ -d "$fixture" ] || continue
  name="$(basename "$fixture")"
  echo ""
  echo "Fixture: $name"

  # Check 1: both input/ and expected/ exist
  if [ -d "$fixture/input" ]; then
    pass "$name has input/"
  else
    fail "$name missing input/"
  fi

  if [ -d "$fixture/expected" ]; then
    pass "$name has expected/"
  else
    fail "$name missing expected/"
  fi

  # Check 2: all YAML files parse
  while IFS= read -r -d '' yaml; do
    if command -v yq >/dev/null 2>&1; then
      if yq eval '.' "$yaml" >/dev/null 2>&1; then
        pass "$(basename "$yaml") valid YAML"
      else
        fail "$(basename "$yaml") invalid YAML"
      fi
    fi
  done < <(find "$fixture" -name '*.yaml' -print0)

  # Check 3: expected Gateway (when present) has correct gatewayClassName
  gateway_file="$fixture/expected/common.gateway/base/gateway.yaml"
  if [ -f "$gateway_file" ]; then
    if yq eval '.spec.gatewayClassName == "gke-l7-global-external-managed"' "$gateway_file" | grep -q true; then
      pass "$name gateway.yaml has correct gatewayClassName"
    else
      fail "$name gateway.yaml gatewayClassName mismatch"
    fi
  fi
done

echo ""
echo "=========================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "=========================="

[ "$FAIL" -eq 0 ]
