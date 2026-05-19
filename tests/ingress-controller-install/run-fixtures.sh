#!/usr/bin/env bash
# Fixture runner for the (v2.0.0 GitOps-flavored) ingress-controller-install skill.
#
# v2.0.0 dropped envsubst-on-values-template testing because the values file is
# now embedded in HelmChartInflationGenerator blocks inside kustomization.yaml.
# The new tests exercise scripts/detect_mode.sh against fixture repos staged
# to look like the three input states (empty / has-overlay / needs-new-env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DETECT="$ROOT_DIR/skills/ingress-controller-install/scripts/detect_mode.sh"

PASS=0
FAIL=0

assert_mode() {
  local name="$1" fixture="$2" target_env="$3" expected_mode="$4" expected_version="$5"
  local fdir="$SCRIPT_DIR/fixtures/$fixture"
  local out actual_mode actual_version
  out=$(bash "$DETECT" --repo-root "$fdir" --target-env "$target_env" 2>/dev/null || true)
  actual_mode=$(echo "$out" | jq -r '.mode // "ERROR"')
  actual_version=$(echo "$out" | jq -r '.currentChartVersion // "null"')

  if [[ "$actual_mode" == "$expected_mode" && "$actual_version" == "$expected_version" ]]; then
    echo "  [PASS] $name (mode=$actual_mode, version=$actual_version)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    echo "    expected: mode=$expected_mode, version=$expected_version"
    echo "    actual:   mode=$actual_mode, version=$actual_version"
    echo "    raw: $out"
    FAIL=$((FAIL+1))
  fi
}

echo "ingress-controller-install fixtures (v2.0.0 GitOps mode detection)"
echo "------------------------------------------------------------------"

echo "[1] bootstrap-empty-repo (no common.traefik/ at all)"
assert_mode "fresh repo → bootstrap mode" \
  "bootstrap-empty-repo" "dev" "bootstrap" "null"

echo "[2] upgrade-existing (target env already has overlay)"
assert_mode "existing dev overlay → upgrade mode" \
  "upgrade-existing" "dev" "upgrade" "39.0.8"

echo "[3] new-env-needed (module exists, target env does not)"
assert_mode "module without new-env overlay → new-env mode" \
  "new-env-needed" "stg" "new-env" "39.0.8"

echo ""
echo "ingress-controller-install: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
