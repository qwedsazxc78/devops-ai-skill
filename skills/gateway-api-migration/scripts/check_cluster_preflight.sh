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
#   ./check_cluster_preflight.sh                              # default --gateway-class traefik
#   ./check_cluster_preflight.sh --gateway-class traefik      # explicit Traefik target
#   ./check_cluster_preflight.sh --gateway-class gke-l7-global-external-managed
#   ./check_cluster_preflight.sh --namespaces "a b c"         # probe those namespaces
#   ./check_cluster_preflight.sh --verify-only                # human OK/FAIL lines
#   ./check_cluster_preflight.sh --skip-check 4               # skip policy-CRD check
#   ./check_cluster_preflight.sh --offline                    # emit stub JSON, exit 0
#
# The --gateway-class flag controls which GatewayClass Check 3 looks for and
# which CRD set Check 4 probes:
#   traefik*    → probe middlewares.traefik.io + Traefik version (v3.1+ required)
#   gke-l7-*    → probe gcpbackendpolicies.networking.gke.io
#   other       → no provider CRD probe; skipped with info message
#
# Prints nothing other than JSON (or OK/FAIL lines in --verify-only mode).
# All informational output goes to stderr so `jq` can consume stdout.
# =============================================================================

set -uo pipefail

VERSION="1.2.0"
GATEWAY_CLASS="traefik"  # default — matches SKILL.md v1.2.0
NAMESPACES=""
VERIFY_ONLY=false
OFFLINE=false
SKIP_CHECKS=""

# --- Arg parse ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-class) GATEWAY_CLASS="$2"; shift 2 ;;
    --namespaces)    NAMESPACES="$2"; shift 2 ;;
    --verify-only)   VERIFY_ONLY=true; shift ;;
    --offline)       OFFLINE=true; shift ;;
    --skip-check)    SKIP_CHECKS="$SKIP_CHECKS $2"; shift 2 ;;
    --help|-h)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 0 ;;
    *) echo "[preflight] unknown arg: $1" >&2; exit 3 ;;
  esac
done

# --- Determine target family from GatewayClass prefix ---
case "$GATEWAY_CLASS" in
  traefik*)  TARGET_FAMILY="traefik" ;;
  gke-l7-*)  TARGET_FAMILY="gke" ;;
  *)         TARGET_FAMILY="vanilla" ;;
esac

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
  cat <<JSON
{
  "checkedOffline": true,
  "gatewayClass": "$GATEWAY_CLASS",
  "targetFamily": "$TARGET_FAMILY",
  "context": "unknown",
  "cluster": "unknown",
  "project": "unknown",
  "gatewayApiVersion": "assumed-v1",
  "gatewayClassesAvailable": ["assumed-$GATEWAY_CLASS"],
  "traefikVersion": null,
  "traefikAddonEnabled": null,
  "gkeAddonEnabled": null,
  "policyCRDs": {
    "middlewares.traefik.io": null,
    "serverstransports.traefik.io": null,
    "tlsoptions.traefik.io": null,
    "gcpbackendpolicies.networking.gke.io": null,
    "healthcheckpolicies.networking.gke.io": null,
    "gcpgatewaypolicies.networking.gke.io": null
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

# --- Check 3: GatewayClass (parameterized on --gateway-class) ---
GATEWAY_CLASSES=()
TRAEFIK_ADDON=null
GKE_ADDON=null
if is_skipped 3; then
  record_warn "gatewayclass (skipped)"
elif [[ $FAILED -eq 0 ]]; then
  GC_OUT=$(kubectl get gatewayclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
  if [[ -n "$GC_OUT" ]]; then
    # shellcheck disable=SC2206
    GATEWAY_CLASSES=($GC_OUT)
    if [[ " ${GATEWAY_CLASSES[*]} " == *" $GATEWAY_CLASS "* ]]; then
      case "$TARGET_FAMILY" in
        traefik) TRAEFIK_ADDON=true ;;
        gke)     GKE_ADDON=true ;;
      esac
      record_ok "gatewayclass $GATEWAY_CLASS present (${#GATEWAY_CLASSES[@]} classes total)"
    else
      case "$TARGET_FAMILY" in
        traefik)
          TRAEFIK_ADDON=false
          record_fail "gatewayclass $GATEWAY_CLASS not found — install Traefik v3.1+ (helm install traefik traefik/traefik --set providers.kubernetesGateway.enabled=true --set gateway.enabled=true)"
          ;;
        gke)
          GKE_ADDON=false
          record_fail "gatewayclass $GATEWAY_CLASS not found — enable GKE Gateway add-on (gcloud container clusters update --gateway-api=standard)"
          ;;
        *)
          record_fail "gatewayclass $GATEWAY_CLASS not found — install the controller that provides this class"
          ;;
      esac
    fi
  else
    record_fail "gatewayclass no GatewayClass resources in cluster"
  fi
fi

# --- Check 3b: Traefik version probe (Traefik target only) ---
TRAEFIK_VERSION=""
if is_skipped 3b || [[ "$TARGET_FAMILY" != "traefik" ]]; then
  :  # skip silently when not Traefik target
elif [[ $FAILED -eq 0 ]]; then
  # Try common label selectors for Traefik pods
  TRAEFIK_IMG=$(kubectl get pods -A \
    -l app.kubernetes.io/name=traefik \
    -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
  if [[ -z "$TRAEFIK_IMG" ]]; then
    TRAEFIK_IMG=$(kubectl get pods -A \
      -l app=traefik \
      -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
  fi
  if [[ -n "$TRAEFIK_IMG" ]]; then
    TRAEFIK_VERSION=$(echo "$TRAEFIK_IMG" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
    if [[ -n "$TRAEFIK_VERSION" ]]; then
      # Compare: require v3.1+
      MAJOR=$(echo "$TRAEFIK_VERSION" | cut -d. -f1)
      MINOR=$(echo "$TRAEFIK_VERSION" | cut -d. -f2)
      if [[ "$MAJOR" -ge 4 ]] || { [[ "$MAJOR" -eq 3 ]] && [[ "$MINOR" -ge 1 ]]; }; then
        record_ok "traefik-version v$TRAEFIK_VERSION (>= v3.1 required for extensionRef)"
      else
        record_fail "traefik-version v$TRAEFIK_VERSION detected; v3.1+ required for Gateway API extensionRef support — upgrade with: helm upgrade traefik traefik/traefik --set image.tag=v3.1.6"
      fi
    else
      record_warn "traefik-version could not parse version from image: $TRAEFIK_IMG"
    fi
  else
    record_warn "traefik-version no Traefik pods found; unable to verify v3.1+ requirement"
  fi
fi

# --- Check 4: Target-specific policy CRDs ---
# Traefik CRDs
MIDDLEWARE_CRD="false"
SERVERSTRANSPORT_CRD="false"
TLSOPTION_CRD="false"
# GKE CRDs
GCP_BP="false"
HCP="false"
GCP_GP="false"
if is_skipped 4; then
  record_warn "policies (skipped)"
elif [[ "$TARGET_FAMILY" == "traefik" ]]; then
  if kubectl get crd middlewares.traefik.io &>/dev/null; then MIDDLEWARE_CRD=true; fi
  if kubectl get crd serverstransports.traefik.io &>/dev/null; then SERVERSTRANSPORT_CRD=true; fi
  if kubectl get crd tlsoptions.traefik.io &>/dev/null; then TLSOPTION_CRD=true; fi
  if [[ "$MIDDLEWARE_CRD" == "true" ]]; then
    record_ok "policies middlewares.traefik.io CRD present"
  else
    record_fail "policies middlewares.traefik.io CRD missing — Traefik Helm chart installs it automatically; verify Traefik v3.1+ is installed"
  fi
  [[ "$SERVERSTRANSPORT_CRD" == "true" ]] \
    || record_warn "policies serverstransports.traefik.io missing — migration will HALT later if proxy-*-timeout annotations detected"
  [[ "$TLSOPTION_CRD" == "true" ]] \
    || record_warn "policies tlsoptions.traefik.io missing — not required for v1.2 but future enhancements may need it"
elif [[ "$TARGET_FAMILY" == "gke" ]]; then
  if kubectl get crd gcpbackendpolicies.networking.gke.io &>/dev/null; then GCP_BP=true; fi
  if kubectl get crd healthcheckpolicies.networking.gke.io &>/dev/null; then HCP=true; fi
  if kubectl get crd gcpgatewaypolicies.networking.gke.io &>/dev/null; then GCP_GP=true; fi
  if [[ "$GCP_BP" == "true" ]]; then
    record_ok "policies GCPBackendPolicy CRD present"
  else
    record_warn "policies GCPBackendPolicy CRD missing — migration will HALT later if CORS/timeout annotations are detected"
  fi
else
  record_warn "policies target family '$TARGET_FAMILY' has no provider CRDs to probe"
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

# Quote the Traefik version or render null
if [[ -n "$TRAEFIK_VERSION" ]]; then
  TRAEFIK_VER_JSON="\"$TRAEFIK_VERSION\""
else
  TRAEFIK_VER_JSON="null"
fi

cat <<EOF
{
  "gatewayClass": "$GATEWAY_CLASS",
  "targetFamily": "$TARGET_FAMILY",
  "context": "${CONTEXT:-unknown}",
  "cluster": "${CLUSTER:-unknown}",
  "server": "${SERVER:-unknown}",
  "project": "${PROJECT:-unknown}",
  "gatewayApiVersion": "$GATEWAY_API_VERSION",
  "gatewayClassesAvailable": $jq_classes,
  "traefikVersion": $TRAEFIK_VER_JSON,
  "traefikAddonEnabled": $TRAEFIK_ADDON,
  "gkeAddonEnabled": $GKE_ADDON,
  "policyCRDs": {
    "middlewares.traefik.io": $MIDDLEWARE_CRD,
    "serverstransports.traefik.io": $SERVERSTRANSPORT_CRD,
    "tlsoptions.traefik.io": $TLSOPTION_CRD,
    "gcpbackendpolicies.networking.gke.io": $GCP_BP,
    "healthcheckpolicies.networking.gke.io": $HCP,
    "gcpgatewaypolicies.networking.gke.io": $GCP_GP
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
