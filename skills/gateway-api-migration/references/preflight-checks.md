# Cluster Preflight Checks

Operational checklist consumed by `*gateway-migrate` **Step 0b**. The goal is to
fail fast — *before* the skill generates any YAML — when the target cluster
cannot actually accept the resources the skill is about to produce.

Every check below has:
- A **probe** (how to run it)
- A **pass condition** (what "good" looks like)
- A **failure mode** (what the skill does when it fails)

The skill's Step 0b calls `scripts/check_cluster_preflight.sh` which runs all
probes and emits structured JSON to stdout. That JSON is written verbatim to
`state.yaml` under `environment.cluster`.

---

## Check 1 — kubectl context resolvable

**Probe:**

```bash
kubectl config current-context
kubectl cluster-info --request-timeout=5s
```

**Pass condition:** `current-context` prints a non-empty value and
`cluster-info` returns within 5s without error.

**Failure mode:** HALT with

```
[HALT] No usable kubectl context.
  Cause: `kubectl config current-context` failed OR cluster-info timed out.
  Fix:   kubectl config use-context <your-context>
         gcloud container clusters get-credentials <cluster> --region <region>
```

The skill refuses to generate resources when it cannot see the target cluster,
because Step 0b reads real data (GatewayClass names, CRD versions) that shape
the generated YAML. A silent offline run would produce wrong output.

**Escape hatch:** `*gateway-migrate --offline` skips this entire file and
assumes GKE defaults. Offline mode is documented in SKILL.md but is not
recommended for production migrations.

---

## Check 2 — Gateway API CRDs installed at the required version

**Probe:**

```bash
kubectl get crd gateways.gateway.networking.k8s.io \
  -o jsonpath='{.spec.versions[?(@.storage)].name}'
kubectl get crd httproutes.gateway.networking.k8s.io \
  -o jsonpath='{.spec.versions[?(@.storage)].name}'
```

**Pass condition:** both commands return `v1` (or `v1beta1`, with a WARN —
the skill generates `v1` resources, but `v1beta1` CRDs accept `v1` manifests
when they are GA-channel).

**Failure mode:** HALT with

```
[HALT] Gateway API CRDs missing or wrong version.
  Found: <empty> | v1alpha2 | v1beta1 | v1
  Fix:   kubectl apply -f \
         https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
         # Then re-run *gateway-migrate
```

The skill emits `apiVersion: gateway.networking.k8s.io/v1` unconditionally.
Clusters running `v1alpha2`-only CRDs will reject those manifests at apply
time — far later than Step 0b, after the skill has already written files to
the repo. Catching it here saves a cleanup round.

---

## Check 3 — Target GatewayClass visible (parameterized on `--gateway-class`)

**Probe:**

```bash
kubectl get gatewayclass -o jsonpath='{.items[*].metadata.name}'
```

**Pass condition:** output contains the GatewayClass name passed via
`--gateway-class <name>` (default: `traefik`).

| `--gateway-class` value | Pass condition |
|---|---|
| `traefik` (default) | `traefik` present, and the Traefik controller pod is Running |
| `traefik-external`, `traefik-internal`, `traefik-*` | the exact name present |
| `gke-l7-global-external-managed` (default GKE) | `gke-l7-global-external-managed` present. WARN if only `gke-l7-rilb` is present |
| any other name | the exact name present |

**Failure mode:** HALT with a message specific to the detected target:

```
[HALT] GatewayClass '<name>' not found in cluster.
  Cause: The skill was invoked with --gateway-class <name> but no such
         GatewayClass exists on the cluster.

  For Traefik targets (standalone helm install):
    Install Traefik v3.1+ with Gateway API support:
      helm repo add traefik https://traefik.github.io/charts
      helm install traefik traefik/traefik \
        --namespace traefik --create-namespace \
        --set providers.kubernetesGateway.enabled=true \
        --set gateway.enabled=true \
        --set image.tag=v3.1.6
    Verify: kubectl get gatewayclass traefik

  For Traefik targets (Kustomize helmCharts: managed deployment):
    The Helm chart renders the GatewayClass automatically — no standalone
    GatewayClass resource is needed. Add to the overlay's valuesInline:
      gatewayClass:
        enabled: true
      providers:
        kubernetesGateway:
          enabled: true
    Then ArgoCD sync / kustomize build will emit the GatewayClass.
    WARNING: do NOT also add a GatewayClass to kustomize resources: — the
    chart and the resource list will conflict with:
      "id exists; can not use behavior: 'unspecified'"
    See traefik-gateway-notes.md §Kustomize-managed Traefik for the full pattern.

  For GKE targets:
    Enable the GKE Gateway controller add-on on your cluster:
      gcloud container clusters update <cluster> --region <region> \
        --gateway-api=standard
    Wait ~2 minutes, verify: kubectl get gatewayclass gke-l7-global-external-managed

  Then re-run *gateway-migrate.
```

The most common cause of a failed migration is applying generated
resources to a cluster where the Gateway controller isn't actually running.
Nothing blocks creation of the Kubernetes objects, but traffic never flows
because no controller reconciles them. Detecting this here avoids a
post-deploy "why isn't anything happening?" session.

### Check 3b — Traefik version probe (Traefik targets only)

When the target is Traefik, also probe the controller pod's image version.
Traefik **v3.1+** is required for Gateway API `extensionRef` filter support
against custom CRDs (which the skill uses heavily for Middleware
attachment).

**Probe:**

```bash
kubectl get pods -A -l app.kubernetes.io/name=traefik \
  -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null \
  | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+'
```

**Pass condition:** version ≥ 3.1.0. WARN if version parsing fails
(non-standard image tag) and continue.

**Failure mode:** HALT if Traefik <3.1.0 is detected:

```
[HALT] Traefik v<found> detected; v3.1+ required for extensionRef support.
  Fix: Upgrade Traefik to v3.1 or later:
       helm upgrade traefik traefik/traefik -n traefik --set image.tag=v3.1.6
```

---

## Check 4 — Target-specific policy CRDs present

The CRD set probed depends on `--gateway-class`.

### 4a — Traefik targets

When `--gateway-class` starts with `traefik`, probe Traefik's CRDs:

```bash
kubectl get crd middlewares.traefik.io \
  -o jsonpath='{.metadata.name}' 2>/dev/null || true
kubectl get crd serverstransports.traefik.io \
  -o jsonpath='{.metadata.name}' 2>/dev/null || true
kubectl get crd tlsoptions.traefik.io \
  -o jsonpath='{.metadata.name}' 2>/dev/null || true
```

**Pass condition:**
- `middlewares.traefik.io` present → required for CORS + path-denylist + any
  HTTPRoute `extensionRef` target. HALT if missing.
- `serverstransports.traefik.io` present → required only if the source Ingress
  had `proxy-*-timeout` annotations (row 10). Conditional HALT.
- `tlsoptions.traefik.io` optional → WARN only if missing (used for future
  listener-level TLS config).

**Failure mode (conditional HALT on middlewares.traefik.io missing):**

```
[HALT] Traefik Middleware CRD missing; migration requires it for CORS and
       path-denylist translations.
  Fix: Install Traefik v3.1+:
       helm install traefik traefik/traefik -n traefik --create-namespace \
         --set providers.kubernetesGateway.enabled=true \
         --set image.tag=v3.1.6
       The Helm chart installs all Traefik CRDs automatically.
```

### 4b — GKE targets

When `--gateway-class` starts with `gke-l7-`, probe GKE policy CRDs:

```bash
kubectl get crd gcpbackendpolicies.networking.gke.io \
  -o jsonpath='{.metadata.name}' 2>/dev/null || true
kubectl get crd healthcheckpolicies.networking.gke.io \
  -o jsonpath='{.metadata.name}' 2>/dev/null || true
```

**Pass condition:** both CRDs present → pass. `gcpbackendpolicies` missing →
HALT **only if** the migration will emit `GCPBackendPolicy` resources
(i.e., annotation-map rows 5–8 or 10 are hit in the source Ingress).
Otherwise WARN and continue — the skill records which policy CRDs were
absent so the report can flag them.

**Failure mode (conditional HALT):**

```
[HALT] GCPBackendPolicy CRD missing but source Ingress has CORS/timeout annotations.
  Cause: the generated module will include GCPBackendPolicy resources that
         cannot be applied to this cluster.
  Fix:   The GKE Gateway controller add-on installs these CRDs automatically.
         Verify the add-on is enabled on the cluster.
```

The conditionality matters for both targets: a migration that doesn't need
CORS/timeouts/path-denylists doesn't need the provider-specific CRDs, so a
missing CRD is fine. Flagging it unconditionally would cause spurious halts
on simple Ingress manifests.

---

## Check 5 — Target namespaces exist and carry (or can carry) the attachment label

**Probe:** for each namespace the skill plans to attach HTTPRoutes to
(derived from the minion set), run:

```bash
kubectl get namespace <ns> -o jsonpath='{.metadata.labels.gateway-access}'
```

**Pass condition:** either the namespace exists (any label value is fine —
the runbook tells the operator how to set `gateway-access=ingress-nginx`
during Phase 1 pre-cutover), or the namespace is listed in the source
repo as a yet-to-be-applied `kind: Namespace` manifest.

**Failure mode:** WARN (not HALT) with

```
[WARN] Target namespace '<ns>' does not exist in the cluster.
  Reason: the skill cannot verify that HTTPRoutes will be able to attach
          until the namespace exists and is labeled gateway-access=ingress-nginx.
  Action: the migration report's "Namespace setup" section lists exact
          `kubectl create namespace` + `kubectl label` commands. Run these
          during Phase 1 pre-cutover.
```

This is WARN, not HALT, because the namespace may legitimately be created
by a separate sync that happens after the migration PR merges. The skill's
job is to surface it, not to enforce creation order.

---

## Check 6 — Cluster name / project context recorded for traceability

**Probe:**

```bash
kubectl config view --minify -o jsonpath='{.contexts[0].context.cluster}'
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
gcloud config get-value project 2>/dev/null || echo unknown
```

**Pass condition:** any non-empty output.

**Failure mode:** informational only — record whatever was found in
`state.yaml.environment.cluster` so the report header can display it.

---

## Structured output schema

The preflight script writes JSON to stdout with this exact shape. The skill
reads it (e.g., with `jq`) into `state.yaml.environment.cluster`:

```json
{
  "context": "gke_awoo-prd_asia-east1_main",
  "cluster": "gke_awoo-prd_asia-east1_main",
  "server": "https://34.x.x.x",
  "project": "awoo-prd",
  "gatewayApiVersion": "v1",
  "gatewayClassesAvailable": ["gke-l7-global-external-managed", "gke-l7-rilb"],
  "gkeAddonEnabled": true,
  "policyCRDs": {
    "gcpbackendpolicies": true,
    "healthcheckpolicies": true,
    "gcpgatewaypolicies": false
  },
  "namespaces": {
    "argocd":     {"exists": true,  "labeled": false},
    "monitoring": {"exists": true,  "labeled": false},
    "tracing":    {"exists": false, "labeled": false}
  },
  "warnings": [
    "namespace 'tracing' does not exist"
  ],
  "halts": [],
  "checksPassed": 5,
  "checksWarned": 1,
  "checksFailed": 0,
  "timestamp": "2026-04-14T12:34:56Z"
}
```

When `halts[]` is non-empty, the skill prints the halt reasons and exits
with code 2. When only `warnings[]` is populated, the skill continues and
surfaces them in the report's **Risk Register** section.

---

## Check 7 — Traefik entrypoint port mapping (Traefik targets only)

When the target is Traefik, Gateway listeners must use the **internal container
port** of each entrypoint, not the LoadBalancer's `exposedPort`. Using the
wrong port causes `PortUnavailable` + `PROGRAMMED: false` + Traefik default
cert served for the hostname.

**Probe:** read entrypoint ports from the live Traefik deployment args:

```bash
kubectl get deployment traefik -n traefik \
  -o jsonpath='{.spec.template.spec.containers[0].args}' \
  | tr ' ' '\n' | grep "entryPoints\|entrypoints" | grep -i "address\|port"
```

Or read from the chart-generated Gateway (always correct):

```bash
kubectl get gateway traefik-gateway -n traefik \
  -o jsonpath='{.spec.listeners}' | jq '.[] | {name, port, protocol}'
```

**Standard ports** (Traefik Helm chart defaults):

| Entrypoint | Container port | LB `exposedPort` | Use in listener |
|---|---|---|---|
| `web` | 8000 | 80 | **8000** |
| `websecure` | 8443 | 443 | **8443** |
| `traefik` | 8080 | 8080 | 8080 |

**Pass condition:** every `port:` in every generated `Gateway.spec.listeners[]`
matches a container port from the above table (or from the live probe).

**Failure mode:** WARN (not HALT) with:

```
[WARN] Gateway listener port <N> does not match any known Traefik entrypoint
       container port. Traefik will report PortUnavailable and serve the
       default self-signed cert for this hostname.
  Fix: change listener port to the container port (e.g., 8443 for websecure,
       not 443). See traefik-gateway-notes.md §CRITICAL for the full table.
```

Record the port map in `state.yaml.environment.cluster.traefikEntrypointPorts`
so the converter can reference it during Step 3A listener generation.

---

## Escape hatches

- `*gateway-migrate --offline` skips Step 0b entirely. State records
  `environment.cluster.checkedOffline: true`. The report header flags
  "offline run — cluster assumptions not verified."
- `*gateway-migrate --skip-preflight <check-id>` lets the operator bypass
  an individual check (e.g., `--skip-preflight 4` to force-generate without
  the policy CRDs check). Every skip is recorded in `state.yaml` under
  `environment.cluster.skippedChecks[]` so the report audit trail is
  complete.
