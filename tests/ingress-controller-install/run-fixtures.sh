#!/usr/bin/env bash
# Fixture runner for ingress-controller-install.
#
# The detect/validate scripts require a live kubectl context, so they are
# not unit-tested here. Instead we exercise:
#   1. values-template.yaml renders cleanly under the documented substitutions
#   2. The rendered YAML is valid (yq parses it) and contains the expected
#      coexistence-critical keys (isDefaultClass: false, ingressClass match,
#      providers.kubernetesIngress.ingressClass match)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$ROOT_DIR/skills/ingress-controller-install/references/values-template.yaml"

PASS=0
FAIL=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

render_template() {
  local env="$1" namespace="$2" class="$3" lb="$4" gw="$5" out="$6"
  ENV="$env" NAMESPACE="$namespace" INGRESS_CLASS_NAME="$class" \
    LB_IP="$lb" GATEWAY_API_ENABLED="$gw" \
    envsubst < "$TEMPLATE" > "$out"
}

test_renders_cleanly() {
  local name="$1"
  local out="$TMP/dev-rendered.yaml"
  render_template "dev" "traefik" "traefik" "10.0.0.42" "false" "$out"
  if yq . "$out" > /dev/null 2>&1; then
    echo "  [PASS] $name"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name — rendered YAML is not parseable"
    sed 's/^/    /' "$out" | head -20
    FAIL=$((FAIL+1))
  fi
}

test_coexistence_invariants() {
  local name="$1"
  local out="$TMP/coexistence.yaml"
  render_template "prd" "traefik" "traefik" "10.0.0.99" "false" "$out"

  local is_default ing_class providers_class
  is_default=$(yq '.ingressClass.isDefaultClass' "$out")
  ing_class=$(yq '.ingressClass.name' "$out")
  providers_class=$(yq '.providers.kubernetesIngress.ingressClass' "$out")

  if [[ "$is_default" == "false" && "$ing_class" == "traefik" && "$providers_class" == "traefik" ]]; then
    echo "  [PASS] $name (isDefaultClass=false, classes match)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"
    echo "    isDefaultClass=$is_default (expected false)"
    echo "    ingressClass.name=$ing_class (expected traefik)"
    echo "    providers.kubernetesIngress.ingressClass=$providers_class (expected traefik)"
    FAIL=$((FAIL+1))
  fi
}

test_gateway_api_toggle() {
  local name="$1"
  local out="$TMP/gw-enabled.yaml"
  render_template "stg" "traefik" "traefik" "10.0.0.50" "true" "$out"
  local gw_enabled
  gw_enabled=$(yq '.providers.kubernetesGateway.enabled' "$out")
  if [[ "$gw_enabled" == "true" ]]; then
    echo "  [PASS] $name"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $name — providers.kubernetesGateway.enabled=$gw_enabled (expected true)"
    FAIL=$((FAIL+1))
  fi
}

echo "ingress-controller-install fixtures"
echo "-----------------------------------"

echo "[1] values-template renders cleanly under all 5 substitutions"
test_renders_cleanly "rendered values.yaml is parseable YAML"

echo "[2] coexistence invariants (isDefaultClass: false, class names match)"
test_coexistence_invariants "coexistence-critical keys correct"

echo "[3] gateway-api toggle"
test_gateway_api_toggle "providers.kubernetesGateway.enabled honors GATEWAY_API_ENABLED=true"

echo ""
echo "ingress-controller-install: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
