#!/usr/bin/env bash
# =============================================================================
# check_cluster_preflight.sh — Step 0b preflight probe for *gateway-migrate
# =============================================================================
# Runs the cluster-side checks documented in references/preflight-checks.md
# and emits structured JSON to stdout. Halts/warnings are in the JSON;
# exit code signals overall result:
#
#   0 — all required checks passed (may have warnings)
#   2 — at least one required check failed (skill should HALT)
#   3 — prerequisite missing (kubectl / jq / gcloud)
#
# Usage:
#   ./check_cluster_preflight.sh                         # all checks, JSON to stdout
#   ./check_cluster_preflight.sh --namespaces "a b c"   # also probe those namespaces
#   ./check_cluster_preflight.sh --verify-only          # human-readable OK/FAIL lines
#                                                       # (used by runbook Step 0.5)
#   ./check_cluster_preflight.sh --skip-check 4         # skip policy-CRD check
#   ./check_cluster_preflight.sh --offline              # emit stub JSON, exit 0
#
# Prints nothing other than JSON (or OK/FAIL lines in --verify-only mode).
# All informational output goes to stderr so `jq` can consume stdout.
# =============================================================================

set -uo pipefail

VERSION="1.1.0"
NAMESPACES=""
VERIFY_ONLY=false
OFFLINE=false
SKIP_CHECKS=""

# --- Arg parse ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespaces)   NAMESPACES="$2"; shift 2 ;;
    --verify-only)  VERIFY_ONLY=true; shift ;;
    --offline)      OFFLINE=true; shift ;;
    --skip-check)   SKIP_CHECKS="$SKIP_CHECKS $2"; shift 2 ;;
    --help|-h)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 0 ;;
    *) echo "[preflight] unknown arg: $1" >&2; exit 3 ;;
  esac
done

# --- Prerequisites ---
for tool in kubectl jq; do
  if ! command -v "$tool" &>/dev/null; then
    echo "[preflight] prerequisite missing: $tool" >&2
    echo "{\"error\":\"prerequisite missing: $tool\",\"checksPassed\":0,\"checksFailed\":1}"
    exit 3
  fi
done

# --- Offline short-circuit ---
if $OFFLINE; then
  cat <<'JSON'
{
  "checkedOffline": true,
  "context": "unknown",
  "cluster": "unknown",
  "project": "unknown",
  "gatewayApiVersion": "assumed-v1",
  "gatewayClassesAvailable": ["assumed-gke-l7-global-external-managed"],
  "gkeAddonEnabled": null,
  "policyCRDs": {
    "gcpbackendpolicies": null,
    "healthcheckpolicies": null,
    "gcpgatewaypolicies": null
  },
  "namespaces": {},
  "warnings": ["offline mode — no cluster checks performed"],
  "halts": [],
  "checksPassed": 0,
  "checksWarned": 1,
  "checksFailed": 0,
  "timestamp": "OFFLINE"
}
JSON
  exit 0
fi

# --- Helpers ---
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
WARNINGS=()
HALTS=()
PASSED=0
WARNED=0
FAILED=0
RESULTS=()

is_skipped() {
  local id="$1"
  [[ " $SKIP_CHECKS " == *" $id "* ]]
}

record_ok()    { PASSED=$((PASSED+1));   $VERIFY_ONLY && echo "OK $1"; }
record_warn()  { WARNED=$((WARNED+1));   WARNINGS+=("$1"); $VERIFY_ONLY && echo "WARN $1"; }
record_fail()  { FAILED=$((FAILED+1));   HALTS+=("$1");    $VERIFY_ONLY && echo "FAIL $1"; }

# --- Check 1: kubectl context ---
CONTEXT=""
CLUSTER=""
SERVER=""
PROJECT=""
if is_skipped 1; then
  record_warn "context (skipped)"
else
  if CONTEXT=$(kubectl config current-context 2>/dev/null) && [[ -n "$CONTEXT" ]]; then
    if kubectl cluster-info --request-timeout=5s &>/dev/null; then
      CLUSTER=$(kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}' 2>/dev/null || echo "")
      SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
      PROJECT=$(gcloud config get-value project 2>/dev/null || echo "unknown")
      record_ok "context=$CONTEXT"
    else
      record_fail "context kubectl cluster-info unreachable within 5s"
    fi
  else
    record_fail "context no current-context set — run: kubectl config use-context <ctx>"
  fi
fi

# --- Check 2: Gateway API CRDs ---
GATEWAY_API_VERSION="none"
if is_skipped 2; then
  record_warn "crds (skipped)"
elif [[ $FAILED -eq 0 ]]; then
  GW_CRD_VER=$(kubectl get crd gateways.gateway.networking.k8s.io \
    -o jsonpath='{.spec.versions[?(@.storage)].name}' 2>/dev/null || echo "")
  HR_CRD_VER=$(kubectl get crd httproutes.gateway.networking.k8s.io \
    -o jsonpath='{.spec.versions[?(@.storage)].name}' 2>/dev/null || echo "")
  if [[ "$GW_CRD_VER" == "v1" && "$HR_CRD_VER" == "v1" ]]; then
    GATEWAY_API_VERSION="v1"
    record_ok "crds gateway=v1 httproute=v1"
  elif [[ -n "$GW_CRD_VER" && -n "$HR_CRD_VER" ]]; then
    GATEWAY_API_VERSION="$GW_CRD_VER"
    record_warn "crds storage version is $GW_CRD_VER — skill emits v1; upgrade with standard-install.yaml"
  else
    record_fail "crds Gateway API CRDs missing — apply standard-install.yaml v1.1.0+"
  fi
fi

# --- Check 3: GatewayClass ---
GATEWAY_CLASSES=()
GKE_ADDON=null
if is_skipped 3; then
  record_warn "gatewayclass (skipped)"
elif [[ $FAILED -eq 0 ]]; then
  GC_OUT=$(kubectl get gatewayclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$GC_OUT" ]]; then
    # shellcheck disable=SC2206
    GATEWAY_CLASSES=($GC_OUT)
    if [[ " ${GATEWAY_CLASSES[*]} " == *" gke-l7-global-external-managed "* ]]; then
      GKE_ADDON=true
      record_ok "gatewayclass gke-l7-global-external-managed present (${#GATEWAY_CLASSES[@]} classes total)"
    else
      GKE_ADDON=false
      record_fail "gatewayclass gke-l7-global-external-managed not found — enable GKE Gateway add-on"
    fi
  else
    GKE_ADDON=false
    record_fail "gatewayclass no GatewayClass resources in cluster — enable GKE Gateway add-on"
  fi
fi

# --- Check 4: GKE policy CRDs ---
GCP_BP="false"
HCP="false"
GCP_GP="false"
if is_skipped 4; then
  record_warn "policies (skipped)"
else
  if kubectl get crd gcpbackendpolicies.networking.gke.io &>/dev/null; then GCP_BP=true; fi
  if kubectl get crd healthcheckpolicies.networking.gke.io &>/dev/null; then HCP=true; fi
  if kubectl get crd gcpgatewaypolicies.networking.gke.io &>/dev/null; then GCP_GP=true; fi
  if [[ "$GCP_BP" == "true" ]]; then
    record_ok "policies GCPBackendPolicy CRD present"
  else
    record_warn "policies GCPBackendPolicy CRD missing — migration will HALT later if CORS/timeout annotations are detected"
  fi
fi

# --- Check 5: namespaces ---
NAMESPACE_JSON="{}"
if is_skipped 5; then
  record_warn "namespaces (skipped)"
elif [[ -n "$NAMESPACES" ]]; then
  TMP_NS=""
  for ns in $NAMESPACES; do
    EXISTS="false"
    LABELED="false"
    if kubectl get namespace "$ns" &>/dev/null; then
      EXISTS="true"
      LBL=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.gateway-access}' 2>/dev/null || echo "")
      [[ "$LBL" == "ingress-nginx" ]] && LABELED="true"
      record_ok "namespaces $ns (labeled=$LABELED)"
    else
      record_warn "namespaces $ns does not exist yet"
    fi
    TMP_NS="$TMP_NS\"$ns\":{\"exists\":$EXISTS,\"labeled\":$LABELED},"
  done
  NAMESPACE_JSON="{${TMP_NS%,}}"
else
  record_ok "namespaces (no target namespace list provided — skipping)"
fi

# --- Check 6: traceability ---
if [[ -n "$CONTEXT" ]]; then
  record_ok "traceability recorded context=$CONTEXT project=$PROJECT"
else
  record_warn "traceability no kubectl context — run ID will lack cluster info"
fi

# --- Verify-only mode terminates here ---
if $VERIFY_ONLY; then
  echo ""
  echo "Summary: $PASSED passed, $WARNED warnings, $FAILED failures"
  [[ $FAILED -eq 0 ]] && exit 0 || exit 2
fi

# --- Build JSON output ---
jq_classes=$(printf '%s\n' "${GATEWAY_CLASSES[@]}" | jq -R . | jq -s .)
jq_warnings=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s '. | map(select(. != ""))')
jq_halts=$(printf '%s\n' "${HALTS[@]}" | jq -R . | jq -s '. | map(select(. != ""))')

cat <<EOF
{
  "context": "${CONTEXT:-unknown}",
  "cluster": "${CLUSTER:-unknown}",
  "server": "${SERVER:-unknown}",
  "project": "${PROJECT:-unknown}",
  "gatewayApiVersion": "$GATEWAY_API_VERSION",
  "gatewayClassesAvailable": $jq_classes,
  "gkeAddonEnabled": $GKE_ADDON,
  "policyCRDs": {
    "gcpbackendpolicies": $GCP_BP,
    "healthcheckpolicies": $HCP,
    "gcpgatewaypolicies": $GCP_GP
  },
  "namespaces": $NAMESPACE_JSON,
  "warnings": $jq_warnings,
  "halts": $jq_halts,
  "checksPassed": $PASSED,
  "checksWarned": $WARNED,
  "checksFailed": $FAILED,
  "timestamp": "$TIMESTAMP",
  "scriptVersion": "$VERSION"
}
EOF

[[ $FAILED -eq 0 ]] && exit 0 || exit 2
