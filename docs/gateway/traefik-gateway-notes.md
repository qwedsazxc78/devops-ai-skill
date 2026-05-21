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

## cert-manager integration

Unchanged from the GKE setup. The eye-of-horus-gitops reference repo uses
cert-manager with a DNS-01 ClusterIssuer (`clouddns-dns01-clusterissuer`)
to mint Certificate resources that create Secrets. Traefik listeners
reference those Secrets directly via `listener.tls.certificateRefs`:

```yaml
listeners:
  - name: https-dev-argocd
    protocol: HTTPS
    port: 443
    hostname: dev-argocd.example.com
    tls:
      mode: Terminate
      certificateRefs:
        - kind: Secret
          name: dev-argocd-ingress-nginx-crt
```

The `cert-manager.io/cluster-issuer` annotation on the original master
Ingress is **drop-info** for a Traefik target — cert-manager continues
to populate the Secrets from the existing Certificate resources; no new
Certificates are emitted by the migration.

## cross-namespace HTTPRoute attachment

Same mechanics as the GKE target. Every namespace that hosts an HTTPRoute
must carry the label `gateway-access: ingress-nginx` (or whatever label
the Gateway's `listeners[].allowedRoutes.namespaces.selector` uses —
the skill defaults to `gateway-access=ingress-nginx` for consistency
with the existing master/minion topology).

No `ReferenceGrant` is needed when the HTTPRoute's backendRefs are in
the same namespace as the HTTPRoute — which is the default for the
master/minion migration pattern.

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
