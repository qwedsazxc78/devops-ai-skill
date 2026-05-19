#!/usr/bin/env bash
# Fixture runner for the traefik-controller-decommission skill.
# Each fixture is a mini Kustomize repo that the verify_no_nginx_class.sh
# script scans in --repo mode. We assert verdict + repo hits per fixture.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VERIFY="$ROOT_DIR/skills/traefik-controller-decommission/scripts/verify_no_nginx_class.sh"
DISCOVER="$ROOT_DIR/skills/traefik-controller-decommission/scripts/discover_nginx_module.sh"

PASS=0
FAIL=0

assert_verdict() {
  local name="$1" fixture="$2" expected_verdict="$3" expected_hits="$4"
  local actual_verdict actual_hits
  pushd "$SCRIPT_DIR/fixtures/$fixture" >/dev/null
  local out
  out=$(bash "$VERIFY" --repo 2>/dev/null || true)
  popd >/dev/null
  actual_verdict=$(echo "$out" | jq -r '.verdict')
  actual_hits=$(echo "$out" | jq -r '.repo | length')

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_hits" == "$expected_hits" ]]; then
    echo "  [PASS] $name (verdict=$actual_verdict, hits=$actual_hits)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    echo "    expected: verdict=$expected_verdict, hits=$expected_hits"
    echo "    actual:   verdict=$actual_verdict, hits=$actual_hits"
    echo "    raw: $out"
    FAIL=$((FAIL+1))
  fi
}

echo "traefik-controller-decommission fixtures"
echo "----------------------------------------"

echo "[1] repo-clean (all Ingresses on traefik)"
assert_verdict "verdict PASS, 0 hits" "repo-clean" "PASS" "0"

echo "[2] repo-blocked-spec (Ingress has spec.ingressClassName: nginx)"
assert_verdict "verdict BLOCKED, 1 hit" "repo-blocked-spec" "BLOCKED" "1"

echo "[3] repo-blocked-annotation (Ingress relies on legacy kubernetes.io/ingress.class annotation)"
assert_verdict "verdict BLOCKED, 1 hit (precedence-aware)" "repo-blocked-annotation" "BLOCKED" "1"

#------------------------------------------------------------------------------
# v2.0.0 GitOps discovery tests
#------------------------------------------------------------------------------

assert_discovery() {
  local name="$1" fixture="$2" expected_verdict="$3" expected_path="$4"
  local fdir="$SCRIPT_DIR/fixtures/$fixture"
  local out actual_verdict actual_path
  out=$(bash "$DISCOVER" --repo-root "$fdir" 2>/dev/null || true)
  actual_verdict=$(echo "$out" | jq -r '.verdict // "ERROR"')
  actual_path=$(echo "$out" | jq -r '.modules[0].path // "null"')

  if [[ "$actual_verdict" == "$expected_verdict" && "$actual_path" == "$expected_path" ]]; then
    echo "  [PASS] $name (verdict=$actual_verdict, path=$actual_path)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    echo "    expected: verdict=$expected_verdict, path=$expected_path"
    echo "    actual:   verdict=$actual_verdict, path=$actual_path"
    echo "    raw: $out"
    FAIL=$((FAIL+1))
  fi
}

echo "[4] discover-single-module (one common.ingress-nginx/ exists)"
assert_discovery "discovery: OK with single module" \
  "discover-single-module" "OK" "common.ingress-nginx"

echo "[5] repo-clean (no ingress-nginx Helm chart anywhere)"
assert_discovery "discovery: NONE when no module present" \
  "repo-clean" "NONE" "null"

echo ""
echo "traefik-controller-decommission: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
