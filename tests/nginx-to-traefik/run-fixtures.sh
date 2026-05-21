#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INVENTORY="$ROOT_DIR/skills/nginx-to-traefik/scripts/inventory_nginx_ingresses.py"

PASS=0; FAIL=0

test_inventory_basic() {
  local fixture="$SCRIPT_DIR/fixtures/basic-three-services/input/common.service/overlays/dev"
  local actual
  actual=$(python3 "$INVENTORY" --overlay-dir "$fixture")
  local count
  count=$(echo "$actual" | jq '[.[] | select(.ingressClass == "nginx")] | length')
  if [[ "$count" == "2" ]]; then
    echo "  [PASS] inventory: 2 nginx ingresses (temporal skipped)"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] inventory: expected 2 nginx ingresses, got $count"
    FAIL=$((FAIL+1))
  fi
}

test_generate_basic() {
  local fixture_in="$SCRIPT_DIR/fixtures/basic-three-services/input/common.service/overlays/dev/argocd-nginx-ingress.yaml"
  local fixture_exp="$SCRIPT_DIR/fixtures/basic-three-services/expected/common.service/overlays/dev/argocd-traefik-ingress.yaml"
  local tmpdir; tmpdir=$(mktemp -d)
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/generate_traefik_ingress.py" \
    --input "$fixture_in" --output "$tmpdir/argocd-traefik-ingress.yaml"
  if diff -u <(yq -P . "$fixture_exp") <(yq -P . "$tmpdir/argocd-traefik-ingress.yaml") >/dev/null; then
    echo "  [PASS] generate argocd: matches expected"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] generate argocd: differs from expected"
    diff -u <(yq -P . "$fixture_exp") <(yq -P . "$tmpdir/argocd-traefik-ingress.yaml") || true
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_update_kustomization_idempotent() {
  local tmpdir; tmpdir=$(mktemp -d)
  cp -r "$SCRIPT_DIR/fixtures/basic-three-services/input/common.service" "$tmpdir/"
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/update_kustomization.py" \
    --overlay-dir "$tmpdir/common.service/overlays/dev" \
    --replace "argocd-nginx-ingress.yaml=argocd-traefik-ingress.yaml" \
    --replace "grafana-nginx-ingress.yaml=grafana-traefik-ingress.yaml"
  local after_first
  after_first=$(cat "$tmpdir/common.service/overlays/dev/kustomization.yaml")
  python3 "$ROOT_DIR/skills/nginx-to-traefik/scripts/update_kustomization.py" \
    --overlay-dir "$tmpdir/common.service/overlays/dev" \
    --replace "argocd-nginx-ingress.yaml=argocd-traefik-ingress.yaml" \
    --replace "grafana-nginx-ingress.yaml=grafana-traefik-ingress.yaml"
  local after_second
  after_second=$(cat "$tmpdir/common.service/overlays/dev/kustomization.yaml")
  if [[ "$after_first" == "$after_second" ]]; then
    echo "  [PASS] update_kustomization: idempotent"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] update_kustomization: second run produced different output"
    diff <(echo "$after_first") <(echo "$after_second") || true
    FAIL=$((FAIL+1))
  fi
  rm -rf "$tmpdir"
}

test_cross_consistency_detects_stale_dns() {
  local fdir="$SCRIPT_DIR/fixtures/cross-consistency-stale-dns/input"
  set +e
  local out
  out=$("$ROOT_DIR/skills/nginx-to-traefik/scripts/validate_cross_consistency.sh" \
    --env dev --batch b1 \
    --dns-script "$fdir/scripts/dns-create-traefik.sh" \
    --verify-script "$fdir/scripts/verify-traefik-dev.sh" \
    --ingress-dir "$fdir/common.service/overlays/dev" \
    --app-ingress "$fdir/common.traefik/overlays/dev/app.ingress.yaml" 2>&1)
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]] && [[ "$out" == *"stale.dev.example.com"* ]]; then
    echo "  [PASS] cross-consistency: stale host detected"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] cross-consistency: rc=$rc out=$out"
    FAIL=$((FAIL+1))
  fi
}

test_inventory_basic
test_generate_basic
test_update_kustomization_idempotent
test_cross_consistency_detects_stale_dns

echo ""
echo "Total: $((PASS+FAIL)), Passed: $PASS, Failed: $FAIL"
[[ "$FAIL" == "0" ]]
