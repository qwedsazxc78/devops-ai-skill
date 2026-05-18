#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0

test_happy_path_produces_outputs() {
  local fdir="$SCRIPT_DIR/fixtures/chain-happy-path"
  local tmpdir; tmpdir=$(mktemp -d)
  "$fdir/mocks/nginx-to-traefik" "$tmpdir" >/dev/null
  local state="$tmpdir/docs/reports/nginx-to-traefik/dev-b1-2026-05-14T10-00-00Z/state.yaml"
  if yq -e '.outputs.traefikIngresses | length == 2' "$state" >/dev/null; then
    echo "  [PASS] chain happy path: A produced 2 traefik outputs"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] chain happy path: A outputs unexpected"
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_phase_a_halt_exits_nonzero() {
  local fdir="$SCRIPT_DIR/fixtures/chain-phase-a-halt"
  set +e
  "$fdir/mocks/nginx-to-traefik" >/dev/null 2>&1
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "  [PASS] phase A halt: subroutine exited non-zero (rc=$rc)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] phase A halt: subroutine exited 0"
    FAIL=$((FAIL+1))
  fi
}

test_happy_path_produces_outputs
test_phase_a_halt_exits_nonzero

echo ""
echo "Total: $((PASS+FAIL)), Passed: $PASS, Failed: $FAIL"
[[ "$FAIL" == "0" ]]
