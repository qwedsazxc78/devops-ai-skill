# Traefik Gateway — Notes for *gateway-migrate

This file captures Traefik-specific facts the `*gateway-migrate` skill must know
when generating Gateway API resources that target a Traefik-managed GatewayClass
(default: `traefik`). It is a reference for skill authors and reviewers, not
end-user documentation. All generated manifests must align with the constraints
and behaviours described here.

Traefik is the skill's **default** Gateway API target since v1.2.0. GKE Gateway
targets (`gke-l7-*`) remain fully supported as opt-in via `--gateway-class`.

## Why Traefik as the default

- **Vendor-neutral Gateway API**: runs on any Kubernetes distribution, not just
  GKE. Matches the Gateway API portability goal called out in the NGINX Ingress
  retirement analysis.
- **Middleware as the extension point**: instead of GKE's `GCPBackendPolicy` +
  `HealthCheckPolicy` pattern, Traefik uses a single `Middleware` CRD referenced
  from HTTPRoutes via `filters[].extensionRef`. The same Middleware resource can
  be shared across every HTTPRoute in a namespace — one CORS policy for all
  backends instead of N per-backend resources.
- **Native cert-manager fit**: `listener.tls.certificateRefs[kind=Secret]` with
  cert-manager-issued Certificate resources works out of the box, same pattern
  the eye-of-horus-gitops reference repo already uses.
- **Plugin ecosystem**: Traefik's plugin system (Traefik Hub / Yaegi plugins)
  covers the deferred-under-GKE items like path denylist (WAF-ish behaviour)
  that we'd otherwise punt to Cloud Armor under a GKE target.

## Required Traefik version

**Traefik v3.1+** is required for Gateway API `extensionRef` filter support
against custom CRDs (the Middleware CRD is the primary one we use). v3.0
supports the Gateway API but does not resolve `extensionRef` to custom
CRDs correctly; v2.x does not support the `gatewayClassName: traefik`
pattern at all.

The skill's Step 0b preflight check probes the Traefik pod image version
and halts with a clear upgrade instruction if Traefik <3.1 is detected.

## GatewayClass name

The Traefik Helm chart creates a GatewayClass named `traefik` by default.
Some deployments run multiple Traefik instances for different exposure
classes and rename them (e.g., `traefik-external`, `traefik-internal`).

The skill accepts any name via `--gateway-class <name>`. Default is
`traefik`. The Step 0b preflight uses whatever name was passed.

## CRDs the skill emits

### Standard Gateway API (always)

- `Gateway` (gateway.networking.k8s.io/v1)
- `HTTPRoute` (gateway.networking.k8s.io/v1)

### Traefik-specific (when `--gateway-class traefik*`)

- **`Middleware`** (traefik.io/v1alpha1) — the primary extension point.
  One resource per concern (CORS, path denylist, rate limiting, etc.),
  referenced from HTTPRoutes via `filters[].extensionRef`. Attached
  per-HTTPRoute, not per-Service like GKE's `GCPBackendPolicy`.
- **`ServersTransport`** (traefik.io/v1alpha1) — backend TLS configuration
  and forwarding timeouts. Emitted when the source Ingress had
  `nginx.org/proxy-*-timeout` annotations (row 10 in `annotation-map.md`).
- **`TLSOption`** (traefik.io/v1alpha1) — per-listener TLS behaviour
  (min version, cipher suites). Not currently emitted by v1.2 — future
  enhancement.
- **`TLSStore`** (traefik.io/v1alpha1) — shared TLS certificate store.
  Not currently emitted by v1.2 — cert-manager Secrets are referenced
  directly from the listener.

### GKE-specific (when `--gateway-class gke-l7-*`)

See `gke-gateway-notes.md`. These resources are NOT emitted under a
Traefik target:
- `GCPBackendPolicy`
- `HealthCheckPolicy`
- `GCPGatewayPolicy`
- `ManagedCertificate` references (the annotation becomes drop-info)

## CORS migration under Traefik

NGINX CORS annotations (rows 5–8 in `annotation-map.md`) become a **single
shared `Middleware`** of kind `headers`, attached to every HTTPRoute that
needs CORS via `filters[].extensionRef`.

### Source annotations

```yaml
nginx.ingress.kubernetes.io/enable-cors: "true"
nginx.ingress.kubernetes.io/cors-allow-origin: "*"
nginx.ingress.kubernetes.io/cors-allow-methods: "PUT, GET, POST, OPTIONS"
nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,X-CustomHeader,..."
```

### Generated Middleware (single file, shared across all HTTPRoutes)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: common-cors
  namespace: ingress-nginx    # same namespace as the Gateway
spec:
  headers:
    accessControlAllowOriginList:
      - "*"
    accessControlAllowMethods:
      - PUT
      - GET
      - POST
      - OPTIONS
    accessControlAllowHeaders:
      - DNT
      - X-CustomHeader
      - X-LANG
      - Keep-Alive
      - User-Agent
      - X-Requested-With
      - If-Modified-Since
      - Cache-Control
      - Content-Type
      - X-Api-Key
      - X-Device-Id
      - Access-Control-Allow-Origin
    accessControlMaxAge: 100
    addVaryHeader: true
```

### HTTPRoute filter reference

Every HTTPRoute that needs CORS gains a filter:

```yaml
spec:
  rules:
    - filters:
        - type: ExtensionRef
          extensionRef:
            group: traefik.io
            kind: Middleware
            name: common-cors
      # ...
```

**Cross-namespace consideration:** if the Middleware lives in
`ingress-nginx` and the HTTPRoute lives in `argocd`, Traefik resolves the
`extensionRef` against the HTTPRoute's own namespace by default. To
share a single Middleware across namespaces, the skill emits the
Middleware in each target service's namespace (not in `ingress-nginx`).
That's N copies of the same YAML, but still simpler than GKE's
N-`GCPBackendPolicy`-with-different-targetRefs pattern. For the
eye-of-horus-gitops dev migration this produces 7 Middleware resources
(one per namespace: argocd, monitoring, airflow, metabase, n8n, qdrant,
uptime) instead of 11 GCPBackendPolicies.

## Path denylist migration under Traefik

NGINX `server-snippet` path denylists (row 9c) become a `Middleware` of
kind `redirectRegex` that sends matching paths to an HTTP 404 response.

### Source snippet

```nginx
location ~ \.(ht|env|example|lock|yaml|md|gitignore|gitmodules|txt)$ {
  deny all;
  return 404;
}
location ~ /(.git|dbconfig|vendor|docs|Dockerfile|system|models)/ {
  deny all;
  return 404;
}
```

### Generated Middleware (default — no plugin required)

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: block-sensitive-paths
  namespace: <target-namespace>
spec:
  # Traefik doesn't have a native "return 404" middleware; the cleanest
  # plugin-free approach is to redirect matching paths to a non-existent
  # internal path, which Traefik then responds to with 404.
  redirectRegex:
    regex: "^(.*/)(\\.ht|\\.env|\\.example|\\.lock|\\.yaml|\\.md|\\.gitignore|\\.gitmodules|\\.txt)$"
    replacement: "/__blocked_by_gateway_migrate__"
    permanent: false
```

### Alternative — plugin-based (commented-out in generated output)

```yaml
# Plugin-based alternative (requires traefik-plugin-blockpath to be declared
# in Traefik's static config). Emitted as a commented block in the generated
# Middleware file so operators can switch if they have the plugin installed.
#
# spec:
#   plugin:
#     blockpath:
#       regex:
#         - "\\.(ht|env|example|lock|yaml|md|gitignore|gitmodules|txt)$"
#         - "/(\\.git|dbconfig|vendor|docs|Dockerfile|system|models)/"
```

## Helm install cheat sheet

For the runbook's Phase 0 (pre-cutover setup):

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --set providers.kubernetesGateway.enabled=true \
  --set gateway.enabled=true \
  --set image.tag=v3.1.6   # pin to v3.1+ for extensionRef support

# Verify the GatewayClass appeared:
kubectl get gatewayclass traefik

# Verify the CRDs are installed:
kubectl get crd | grep traefik.io
# Expected at minimum:
#   middlewares.traefik.io
#   serverstransports.traefik.io
#   tlsoptions.traefik.io
#   tlsstores.traefik.io
```

## CRITICAL: Gateway listener port = internal container port (not LB exposedPort)

Traefik's Gateway API provider maps Gateway listeners to entrypoints by
**matching the listener's `port` to the entrypoint's internal container port**,
not the LoadBalancer's `exposedPort`. This is the single most common cause of
`PortUnavailable` and the Traefik default-cert fallback.

Default Traefik Helm chart entrypoint ports:

| Entrypoint | Container port | LB `exposedPort` | Listener `port` to use |
|---|---|---|---|
| `web` | 8000 | 80 | **8000** |
| `websecure` | 8443 | 443 | **8443** |
| `traefik` (dashboard) | 8080 | 8080 | 8080 |

**Wrong:**
```yaml
listeners:
  - name: websecure
    port: 443          # ← LB port — Traefik finds no matching entrypoint
    protocol: HTTPS
```

**Correct:**
```yaml
listeners:
  - name: websecure
    port: 8443         # ← container port — matches the websecure entrypoint
    protocol: HTTPS
```

Symptom of wrong port: `status.conditions[reason=PortUnavailable]` on the
Gateway + `PROGRAMMED: false` + Traefik serving `TRAEFIK DEFAULT CERT` for
the hostname (because no listener is configured, Traefik falls back to its
self-signed default).

Verify correct port by checking the chart-generated `traefik-gateway`:
```bash
kubectl get gateway traefik-gateway -n traefik \
  -o jsonpath='{.spec.listeners[*].port}'
# Should show: 8000 (for web) — confirms 8443 is needed for websecure
```

---

## Kustomize-managed Traefik (helmCharts: valuesInline pattern)

Repos like eye-of-horus-gitops manage Traefik via Kustomize `helmCharts:` with
`valuesInline` overrides rather than a standalone `helm install`. Gateway API
support is enabled through the overlay's `kustomization.yaml`, not via
`helm upgrade --set`.

### Enabling the provider

Add to the target overlay's `helmCharts[].valuesInline` block — **not** to the
shared `base/app.values.yaml` (which is copied across all envs — see
`traefik-values-drift` pre-commit hook):

```yaml
helmCharts:
  - name: traefik
    # ... (existing chart config unchanged)
    valuesInline:
      gatewayClass:
        enabled: true          # chart renders GatewayClass named "traefik"
      providers:
        kubernetesGateway:
          enabled: true        # activates --providers.kubernetesgateway arg in pod
```

Both flags work together: `gatewayClass.enabled` gates the chart template that
emits the `GatewayClass` object; `providers.kubernetesGateway.enabled` adds the
`--providers.kubernetesgateway` flag to the Traefik pod args. Neither alone
is sufficient.

### CRITICAL: never add GatewayClass to Kustomize resources when chart owns it

When these `valuesInline` flags are set, the Helm chart generates the
`GatewayClass` object as part of its rendered output. If you also declare a
`GatewayClass` in your overlay's `resources:` list, Kustomize throws a merge
conflict at build time:

```
Error: id resid.ResId{..., Kind:"GatewayClass", Name:"traefik"} exists;
       can not use behavior: 'unspecified', behavior must be merge or replace
```

**Rule: only add `Gateway` and `HTTPRoute` to `resources:`. Let the chart own
`GatewayClass`.**

Correct overlay `resources:` list:

```yaml
resources:
  - ../../base
  - app.dashboard-gateway.yaml   # contains Gateway + HTTPRoute only
```

`app.dashboard-gateway.yaml` content — GatewayClass omitted:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <gateway-name>
  namespace: traefik
spec:
  gatewayClassName: traefik
  listeners:
    - name: websecure
      hostname: <your-host>
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: <existing-cert-secret>
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <route-name>
  namespace: traefik
spec:
  parentRefs:
    - name: <gateway-name>
      namespace: traefik
      sectionName: websecure
  hostnames:
    - <your-host>
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>
          port: <port>
```

### Expected chart-generated objects (not migration artifacts)

When `providers.kubernetesGateway.enabled: true`, the Helm chart also renders a
default `traefik-gateway` Gateway object (listening on port 8000, the `web`
entrypoint). This is the chart's own Gateway for general traffic — it is **not**
a naming conflict with migration-created Gateways and should not be deleted.
Expect two Gateway objects in the namespace: the chart's `traefik-gateway` and
your migration Gateway.

```bash
kubectl get gateway -n traefik
# NAME                   CLASS     ADDRESS      PROGRAMMED   AGE
# traefik-gateway        traefik   11.0.0.14    True         5m   ← chart default
# traefik-dashboard-gw   traefik   11.0.0.14    True         2m   ← migration target
```

## cert-manager integration

cert-manager handles TLS for Traefik Gateway resources via two mechanisms.
Use the annotation approach (preferred) when cert-manager ≥1.15 is available;
fall back to an explicit Certificate CR otherwise.

### Preferred: Gateway annotation (cert-manager ≥1.15 gateway-shim)

Add `cert-manager.io/cluster-issuer` directly to the Gateway's annotations.
cert-manager's gateway-shim watches Gateway objects, reads the annotation +
`listener.tls.certificateRefs[name]`, and auto-creates and renews the
Certificate CR — no explicit `Certificate` resource is needed.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: traefik-dashboard-gw
  namespace: traefik
  annotations:
    cert-manager.io/cluster-issuer: clouddns-dns01-clusterissuer
spec:
  gatewayClassName: traefik
  listeners:
    - name: websecure
      hostname: dev-dashboard-traefik.awoo.org
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: dev-dashboard-traefik-crt  # cert-manager creates + renews this
```

This is the **recommended best practice** — mirrors the Ingress annotation pattern
exactly, auto-rotates before expiry, and keeps the Gateway self-sufficient
(no dependency on a parallel Ingress to provision the secret).

Rotation policy defaults to `Always`; control with:
```yaml
annotations:
  cert-manager.io/cluster-issuer: clouddns-dns01-clusterissuer
  cert-manager.io/private-key-rotation-policy: Always  # default; explicit for clarity
```

### Fallback: explicit Certificate CR (any cert-manager version)

When cert-manager <1.15 or the gateway-shim feature is not enabled, emit
a `Certificate` resource alongside the Gateway:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dev-dashboard-traefik-crt
  namespace: traefik
spec:
  secretName: dev-dashboard-traefik-crt
  issuerRef:
    name: clouddns-dns01-clusterissuer
    kind: ClusterIssuer
  dnsNames:
    - dev-dashboard-traefik.awoo.org
```

The Gateway then references `dev-dashboard-traefik-crt` via `certificateRefs`
as before — cert-manager manages renewal via the Certificate object directly.

### Migration action (annotation-map row 2)

The `cert-manager.io/cluster-issuer` annotation on the source Ingress is **not
dropped** — it is **moved to the Gateway**. The converter action is:

```
source Ingress annotation → Gateway.metadata.annotations (same key, same value)
```

This is a change from the v1.1 behaviour (which classified the annotation as
drop-info). The updated annotation-map row 2 documents this correction.

## Gateway topology: default pattern for Traefik (Option A)

When migrating a batch of Traefik Ingresses where each backend lives in a
different namespace (e.g. `monitoring`, `argocd`, `airflow`), two layouts
are possible:

| Option | Gateway location | HTTPRoute location | `backendRefs` | `ReferenceGrant` needed? |
|---|---|---|---|---|
| **A — Gateway per host in `traefik` ns** *(default)* | `traefik` | `traefik` | cross-ns to backend service | **No** — Traefik's `allowCrossNamespace: true` covers it |
| B — Single shared Gateway + ReferenceGrant | `traefik` | `traefik` | cross-ns via ReferenceGrant in each backend ns | Yes, one per backend namespace |

**The skill defaults to Option A.** Rationale:

- Matches the dashboard POC pattern — proven on real cluster.
- `allowCrossNamespace: true` is standard in the Traefik Helm chart
  (`providers.kubernetesCRD.allowCrossNamespace: true` and
  `providers.kubernetesGateway.experimentalChannel: true` cover it).
  `backendRefs` pointing to another namespace work without any extra
  manifest.
- No `ReferenceGrant` objects to maintain.
- Each host gets its own named Gateway → independent cert lifecycle,
  independent `PROGRAMMED` status, easy per-host rollback.
- `allowedRoutes.namespaces.from: Same` keeps the listener tight
  (only HTTPRoutes in the `traefik` namespace can attach).

**Option A canonical template** (one file per migrated Ingress):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: <service>-gw
  namespace: traefik
  annotations:
    cert-manager.io/cluster-issuer: <issuer>   # triggers cert-manager gateway-shim
spec:
  gatewayClassName: traefik
  listeners:
    - name: websecure
      hostname: <host>
      port: 8443          # CRITICAL: internal container port, not LB exposedPort (443)
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: <service>-crt
      allowedRoutes:
        namespaces:
          from: Same      # only traefik-ns HTTPRoutes attach
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <service>-gw
  namespace: traefik      # same ns as Gateway → satisfies allowedRoutes: Same
spec:
  parentRefs:
    - name: <service>-gw
      namespace: traefik
      sectionName: websecure
  hostnames:
    - <host>
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <service-name>   # service in a DIFFERENT namespace — works via
          namespace: <backend-ns> # Traefik allowCrossNamespace: true (no ReferenceGrant)
          port: <port>
```

**To override to Option B** (single shared Gateway + ReferenceGrant), pass
`--gateway-topology shared` to the skill. The skill will emit one
`ReferenceGrant` per backend namespace. Option B is recommended only when
the cluster operator needs to minimise the total number of Gateway objects.

## cross-namespace HTTPRoute attachment

Same mechanics as the GKE target. Every namespace that hosts an HTTPRoute
must carry the label `gateway-access: ingress-nginx` (or whatever label
the Gateway's `listeners[].allowedRoutes.namespaces.selector` uses —
the skill defaults to `gateway-access=ingress-nginx` for consistency
with the existing master/minion topology).

No `ReferenceGrant` is needed when the HTTPRoute's backendRefs are in
the same namespace as the HTTPRoute — which is the default for the
master/minion migration pattern (Option A).

## Known limitations for v1.2

- **Per-plugin middleware is heavier than shared policy CRDs.** If a
  cluster already has dozens of Traefik Middlewares, adding more for
  every migrated module increases the control plane's resource watch
  load. Not a blocker but worth monitoring.
- **`TLSOption` not emitted.** Listener-level TLS min-version and cipher
  suite configuration is pinned to the Traefik Helm chart's defaults.
  If you need custom TLS settings per listener, add a `TLSOption`
  manually after migration.
- **No shared GCP-style BackendPolicy** — every HTTPRoute gains the CORS
  filter individually. Not a correctness issue, just more verbose at
  the HTTPRoute level. If this becomes a maintenance headache a future
  v1.3 could introduce a `Middleware` chain that every HTTPRoute
  references once instead of listing each concern separately.
- **Single GatewayClass per migration run.** v1.2 migrates to one
  GatewayClass at a time. If a cluster needs both `traefik-external`
  and `traefik-internal`, run the skill twice with different
  `--gateway-class` values and different target overlay paths.

## Debugging attachment failures

If an HTTPRoute isn't attaching to the Gateway:

```bash
# Check HTTPRoute conditions:
kubectl get httproute <name> -n <ns> \
  -o jsonpath='{.status.parents[0].conditions}' | jq .

# Common reasons and fixes:
#   Accepted: False, reason: NotAllowedByListeners
#     → namespace missing the gateway-access=ingress-nginx label
#   Accepted: False, reason: NoMatchingParent
#     → Gateway not found, sectionName typo, or wrong namespace on parentRef
#   ResolvedRefs: False, reason: BackendNotFound
#     → Service name or port mismatch in backendRefs
#   ResolvedRefs: False, reason: InvalidKind
#     → extensionRef filter points at a CRD Traefik can't resolve
#       (e.g., Middleware in wrong namespace, wrong Traefik version)
```

The new Step 4d validator check `httproute-parentref-name` catches the
NoMatchingParent case at generation time. The `middleware-coverage`
check (new in v1.2) catches InvalidKind for missing Middleware refs.
