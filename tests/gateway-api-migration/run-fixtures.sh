#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

  # Check 1: input/ exists
  if [ -d "$fixture/input" ]; then
    pass "$name has input/"
  else
    fail "$name missing input/"
  fi

  # Check for expectError marker (error-path fixtures have no expected/)
  expect_error=false
  if [ -f "$fixture/input/fixture.meta.yaml" ]; then
    if command -v yq >/dev/null 2>&1 && \
       yq eval '.expectError // false' "$fixture/input/fixture.meta.yaml" | grep -q true; then
      expect_error=true
      pass "$name is an expectError fixture (skipping expected/ check)"
    fi
  fi

  # Skip the "expected/ exists" check if this is an expectError fixture
  if [ "$expect_error" = false ]; then
    if [ -d "$fixture/expected" ]; then
      pass "$name has expected/"
    else
      fail "$name missing expected/"
    fi
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
echo "--- classify_ingress unit tests ---"

test_classify_traefik_source() {
  local f="$ROOT_DIR/tests/gateway-api-migration/fixtures/traefik-source-minimal/input/common.service/overlays/dev/argocd-traefik-ingress.yaml"
  local out
  out=$(python3 "$ROOT_DIR/skills/gateway-api-migration/scripts/classify_ingress.py" "$f")
  if echo "$out" | jq -e '.sourceClass == "traefik"' >/dev/null; then
    pass "classify_ingress: sourceClass=traefik"
  else
    fail "classify_ingress: missing sourceClass=traefik in $out"
  fi
}

test_classify_traefik_source

echo ""
echo "--- validate_generated unit tests ---"

test_check12_fails_traefik_source_missing_extensionref() {
  local tmpdir; tmpdir=$(mktemp -d)
  local source_yaml="$tmpdir/source.yaml"
  local service_yaml="$tmpdir/service.yaml"

  cat > "$source_yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: traefik-cors@kubernetescrd
spec:
  ingressClassName: traefik
  rules:
  - host: argocd.dev.awoo.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
YAML

  cat > "$service_yaml" <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  hostnames:
  - argocd.dev.awoo.org
  rules:
  - backendRefs:
    - name: argocd-server
      port: 80
YAML

  local result
  result=$(python3 - "$source_yaml" "$service_yaml" <<'PYEOF'
import json, sys
sys.path.insert(0, "skills/gateway-api-migration/scripts")
from validate_generated import check_middleware_coverage
from pathlib import Path
source_built, service_build = Path(sys.argv[1]), Path(sys.argv[2])
r = check_middleware_coverage(source_built, service_build, service_build, "traefik", source_class="traefik")
print(json.dumps(r))
PYEOF
  )
  local status
  status=$(echo "$result" | jq -r '.status')
  if [[ "$status" == "fail" ]]; then
    pass "check 12 fails on traefik source missing extensionRef"
  else
    fail "check 12: expected fail, got $status"
  fi
  rm -rf "$tmpdir"
}

test_check13_warns_traefik_source_with_tls_redirect() {
  local tmpdir; tmpdir=$(mktemp -d)
  local service_yaml="$tmpdir/service.yaml"

  cat > "$service_yaml" <<'YAML'
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tls-redirect
  namespace: argocd
spec:
  rules:
  - filters:
    - type: RequestRedirect
YAML

  local result
  result=$(python3 - "$service_yaml" <<'PYEOF'
import json, sys
sys.path.insert(0, "skills/gateway-api-migration/scripts")
from validate_generated import check_no_redundant_tls_redirect
from pathlib import Path
service_build = Path(sys.argv[1])
r = check_no_redundant_tls_redirect(service_build, source_class="traefik")
print(json.dumps(r))
PYEOF
  )
  local status
  status=$(echo "$result" | jq -r '.status')
  if [[ "$status" == "warn" ]]; then
    pass "check 13 warns on traefik source with tls-redirect emitted"
  else
    fail "check 13: expected warn, got $status"
  fi
  rm -rf "$tmpdir"
}

test_check12_fails_traefik_source_missing_extensionref
test_check13_warns_traefik_source_with_tls_redirect

echo ""
echo "=========================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "=========================="

[ "$FAIL" -eq 0 ]
