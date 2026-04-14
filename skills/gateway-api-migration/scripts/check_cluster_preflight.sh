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
#   ./check_cluster_preflight.sh --context <kubectl-context>  # don't change current context
#   ./check_cluster_preflight.sh --namespaces "a b c"         # probe those namespaces
#   ./check_cluster_preflight.sh --verify-only                # human OK/FAIL lines
#   ./check_cluster_preflight.sh --skip-check 4               # skip policy-CRD check
#   ./check_cluster_preflight.sh --offline                    # emit stub JSON, exit 0
#
# The --context flag is the safest way to probe a non-current cluster: it
# scopes every kubectl call to the named context for this run only, without
# touching the user's `kubectl config current-context` setting. Useful when
# the active context is prod and you want to preflight dev.
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

VERSION="1.2.1"
GATEWAY_CLASS="traefik"  # default — matches SKILL.md v1.2.0
KUBE_CONTEXT=""          # empty means "use kubectl current-context as-is"
NAMESPACES=""
VERIFY_ONLY=false
OFFLINE=false
SKIP_CHECKS=""

# --- Arg parse ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway-class) GATEWAY_CLASS="$2"; shift 2 ;;
    --context)       KUBE_CONTEXT="$2"; shift 2 ;;
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

# --- kubectl wrapper that honours --context without touching global state ---
# All cluster probes go through this function instead of calling kubectl
# directly. When --context is set, every call gets the same --context flag;
# when it's empty, calls behave exactly like plain `kubectl ...`.
kubectl_ctx() {
  if [[ -n "$KUBE_CONTEXT" ]]; then
    kubectl --context="$KUBE_CONTEXT" "$@"
  else
    kubectl "$@"
  fi
}

# --- Run a kubectl probe and classify the outcome ---
# Returns one of three states via stdout:
#   ok:<output>    — command succeeded, output (possibly empty) follows
#   forbidden:     — command failed with a 403 Forbidden / GCP IAM error
#   missing:       — command failed because the resource truly doesn't exist
#                    (CRD not installed, namespace doesn't exist, etc.)
#   error:<msg>    — any other failure (network, malformed, etc.)
#
# The forbidden detection is the critical bit: GKE GCP IAM denies CRD/namespace
# list operations with messages like:
#   Error from server (Forbidden): ... is forbidden: User "..." cannot list ...
#   ... requires one of ["container.namespaces.list"] permission(s) in Cloud IAM
# Without this distinction the script would tell operators "install Traefik"
# when the real fix is "grant container.viewer or equivalent IAM role."
kubectl_probe() {
  local out err rc
  err=$(mktemp)
  out=$(kubectl_ctx "$@" 2>"$err")
  rc=$?
  local stderr_content
  stderr_content=$(<"$err")
  rm -f "$err"
  if [[ $rc -eq 0 ]]; then
    printf 'ok:%s' "$out"
    return 0
  fi
  if echo "$stderr_content" | grep -q -E 'Forbidden|forbidden|requires one of \[.+permission'; then
    printf 'forbidden:%s' "$stderr_content"
    return 0
  fi
  if echo "$stderr_content" | grep -q -E 'NotFound|not found|the server doesn'\''t have a resource type'; then
    printf 'missing:%s' "$stderr_content"
    return 0
  fi
  printf 'error:%s' "$stderr_content"
  return 0
}

# --- Helper: peel off the "ok:" / "forbidden:" / "missing:" / "error:" prefix ---
probe_state()  { echo "${1%%:*}"; }
probe_value()  { echo "${1#*:}"; }

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
  # When --context is passed, that's the authoritative target — don't fall
  # back to the global current-context. When --context is empty, use whatever
  # kubectl considers current.
  if [[ -n "$KUBE_CONTEXT" ]]; then
    CONTEXT="$KUBE_CONTEXT"
  else
    CONTEXT=$(kubectl config current-context 2>/dev/null || echo "")
  fi
  if [[ -n "$CONTEXT" ]]; then
    # Try a low-permission probe first: `kubectl version` doesn't need any
    # API permissions, just an apiserver TCP connection. This separates
    # "can't reach cluster" from "can reach but auth-restricted".
    VERSION_PROBE=$(kubectl_probe version --request-timeout=5s -o json)
    case "$(probe_state "$VERSION_PROBE")" in
      ok)
        CLUSTER=$(kubectl_ctx config view -o jsonpath='{.contexts[?(@.name=="'"$CONTEXT"'")].context.cluster}' 2>/dev/null || echo "")
        SERVER=$(kubectl_ctx config view -o jsonpath='{.clusters[?(@.name=="'"$CLUSTER"'")].cluster.server}' 2>/dev/null || echo "")
        PROJECT=$(gcloud config get-value project 2>/dev/null || echo "unknown")
        record_ok "context=$CONTEXT"
        ;;
      forbidden)
        # Cluster reachable but every probe returns 403. Record as a soft
        # failure: continue to other checks (so we surface ALL the forbidden
        # cases at once instead of bailing on the first one), but the overall
        # exit code reflects the failure.
        record_fail "context $CONTEXT reachable but Cloud IAM denies basic API access. Grant roles/container.viewer (or container.developer) and re-run. The remaining checks may also fail with FORBIDDEN — those are not separate problems, just symptoms of the same missing IAM permission."
        ;;
      *)
        record_fail "context kubectl version unreachable within 5s for context=$CONTEXT — network/auth/cluster down"
        ;;
    esac
  else
    record_fail "context no current-context set — run: kubectl config use-context <ctx>  OR pass --context <ctx>"
  fi
fi

# --- Check 2: Gateway API CRDs ---
GATEWAY_API_VERSION="none"
if is_skipped 2; then
  record_warn "crds (skipped)"
elif [[ $FAILED -eq 0 ]]; then
  GW_PROBE=$(kubectl_probe get crd gateways.gateway.networking.k8s.io \
    -o jsonpath='{.spec.versions[?(@.storage)].name}')
  HR_PROBE=$(kubectl_probe get crd httproutes.gateway.networking.k8s.io \
    -o jsonpath='{.spec.versions[?(@.storage)].name}')
  GW_STATE=$(probe_state "$GW_PROBE"); GW_CRD_VER=$(probe_value "$GW_PROBE")
  HR_STATE=$(probe_state "$HR_PROBE"); HR_CRD_VER=$(probe_value "$HR_PROBE")

  if [[ "$GW_STATE" == "forbidden" || "$HR_STATE" == "forbidden" ]]; then
    record_fail "crds CANNOT VERIFY — Cloud IAM denies CRD list. Grant roles/container.viewer or container.developer to the kubectl user. (See https://cloud.google.com/kubernetes-engine/docs/how-to/iam)"
  elif [[ "$GW_STATE" == "ok" && "$HR_STATE" == "ok" && "$GW_CRD_VER" == "v1" && "$HR_CRD_VER" == "v1" ]]; then
    GATEWAY_API_VERSION="v1"
    record_ok "crds gateway=v1 httproute=v1"
  elif [[ "$GW_STATE" == "ok" && "$HR_STATE" == "ok" && -n "$GW_CRD_VER" && -n "$HR_CRD_VER" ]]; then
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
  GC_PROBE=$(kubectl_probe get gatewayclass -o jsonpath='{.items[*].metadata.name}')
  GC_STATE=$(probe_state "$GC_PROBE"); GC_OUT=$(probe_value "$GC_PROBE")
  if [[ "$GC_STATE" == "forbidden" ]]; then
    record_fail "gatewayclass CANNOT VERIFY — Cloud IAM denies gatewayclass list. Grant container.thirdPartyObjects.list (or roles/container.viewer)."
  elif [[ "$GC_STATE" == "ok" && -n "$GC_OUT" ]]; then
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
  TRAEFIK_IMG=$(kubectl_ctx get pods -A \
    -l app.kubernetes.io/name=traefik \
    -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
  if [[ -z "$TRAEFIK_IMG" ]]; then
    TRAEFIK_IMG=$(kubectl_ctx get pods -A \
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
# Helper: probe a single CRD; return "true" / "false" / "forbidden"
crd_state() {
  local probe
  probe=$(kubectl_probe get crd "$1" -o jsonpath='{.metadata.name}')
  case "$(probe_state "$probe")" in
    ok)        echo "true" ;;
    forbidden) echo "forbidden" ;;
    *)         echo "false" ;;
  esac
}

if is_skipped 4; then
  record_warn "policies (skipped)"
elif [[ "$TARGET_FAMILY" == "traefik" ]]; then
  MW_STATE=$(crd_state middlewares.traefik.io)
  ST_STATE=$(crd_state serverstransports.traefik.io)
  TO_STATE=$(crd_state tlsoptions.traefik.io)

  case "$MW_STATE" in
    true)
      MIDDLEWARE_CRD=true
      record_ok "policies middlewares.traefik.io CRD present"
      ;;
    forbidden)
      MIDDLEWARE_CRD="forbidden"
      record_fail "policies CANNOT VERIFY middlewares.traefik.io — Cloud IAM denies CRD list. Grant roles/container.viewer (or container.developer) before assuming Traefik is missing."
      ;;
    *)
      MIDDLEWARE_CRD=false
      record_fail "policies middlewares.traefik.io CRD missing — Traefik Helm chart installs it automatically; verify Traefik v3.1+ is installed"
      ;;
  esac
  case "$ST_STATE" in
    true)      SERVERSTRANSPORT_CRD=true ;;
    forbidden) SERVERSTRANSPORT_CRD="forbidden"; record_warn "policies CANNOT VERIFY serverstransports.traefik.io (IAM forbidden)" ;;
    *)         SERVERSTRANSPORT_CRD=false; record_warn "policies serverstransports.traefik.io missing — migration will HALT later if proxy-*-timeout annotations detected" ;;
  esac
  case "$TO_STATE" in
    true)      TLSOPTION_CRD=true ;;
    forbidden) TLSOPTION_CRD="forbidden" ;;
    *)         TLSOPTION_CRD=false; record_warn "policies tlsoptions.traefik.io missing — not required for v1.2 but future enhancements may need it" ;;
  esac
elif [[ "$TARGET_FAMILY" == "gke" ]]; then
  GCP_BP_STATE=$(crd_state gcpbackendpolicies.networking.gke.io)
  HCP_STATE=$(crd_state healthcheckpolicies.networking.gke.io)
  GCP_GP_STATE=$(crd_state gcpgatewaypolicies.networking.gke.io)
  case "$GCP_BP_STATE" in
    true)      GCP_BP=true; record_ok "policies GCPBackendPolicy CRD present" ;;
    forbidden) GCP_BP="forbidden"; record_fail "policies CANNOT VERIFY GCPBackendPolicy — Cloud IAM denies CRD list" ;;
    *)         GCP_BP=false; record_warn "policies GCPBackendPolicy CRD missing — migration will HALT later if CORS/timeout annotations are detected" ;;
  esac
  [[ "$HCP_STATE" == "true" ]] && HCP=true || HCP="$HCP_STATE"
  [[ "$GCP_GP_STATE" == "true" ]] && GCP_GP=true || GCP_GP="$GCP_GP_STATE"
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
    NS_PROBE=$(kubectl_probe get namespace "$ns" -o jsonpath='{.metadata.labels.gateway-access}')
    case "$(probe_state "$NS_PROBE")" in
      ok)
        EXISTS="true"
        LBL=$(probe_value "$NS_PROBE")
        [[ "$LBL" == "ingress-nginx" ]] && LABELED="true"
        record_ok "namespaces $ns (labeled=$LABELED)"
        ;;
      forbidden)
        record_warn "namespaces $ns CANNOT VERIFY — Cloud IAM denies namespace get/list"
        ;;
      *)
        record_warn "namespaces $ns does not exist yet"
        ;;
    esac
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
# Convert per-CRD state variables (which may hold true / false / "forbidden")
# into JSON-safe literals: bare booleans for true/false, quoted strings
# otherwise.
to_json_literal() {
  case "$1" in
    true|false|null) echo "$1" ;;
    *) echo "\"$1\"" ;;
  esac
}
MIDDLEWARE_CRD_JSON=$(to_json_literal "$MIDDLEWARE_CRD")
SERVERSTRANSPORT_CRD_JSON=$(to_json_literal "$SERVERSTRANSPORT_CRD")
TLSOPTION_CRD_JSON=$(to_json_literal "$TLSOPTION_CRD")
GCP_BP_JSON=$(to_json_literal "$GCP_BP")
HCP_JSON=$(to_json_literal "$HCP")
GCP_GP_JSON=$(to_json_literal "$GCP_GP")

# bash 3.2 unbound-variable guard: an empty array cannot be expanded with [@]
# under `set -u`. Use printf with a default to materialise the empty list.
if [[ "${#GATEWAY_CLASSES[@]}" -eq 0 ]]; then
  jq_classes='[]'
else
  jq_classes=$(printf '%s\n' "${GATEWAY_CLASSES[@]}" | jq -R . | jq -s .)
fi
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
    "middlewares.traefik.io": $MIDDLEWARE_CRD_JSON,
    "serverstransports.traefik.io": $SERVERSTRANSPORT_CRD_JSON,
    "tlsoptions.traefik.io": $TLSOPTION_CRD_JSON,
    "gcpbackendpolicies.networking.gke.io": $GCP_BP_JSON,
    "healthcheckpolicies.networking.gke.io": $HCP_JSON,
    "gcpgatewaypolicies.networking.gke.io": $GCP_GP_JSON
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
