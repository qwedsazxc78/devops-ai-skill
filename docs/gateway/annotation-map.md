# NGINX Ingress → Gateway API Annotation Map

Canonical translation table for `*gateway-migrate`. Each row represents a
deterministic decision the converter makes every run. Single source of truth —
the skill's `references/annotation-map.md` symlinks here.

**Dual-target.** Since skill v1.2.0 the map supports two targets: the default
**Traefik** path (`--gateway-class traefik*`) and the GKE Gateway path
(`--gateway-class gke-l7-*`). Every row below has per-target guidance. The
skill branches on the `--gateway-class` prefix and emits whichever column
applies. Rows that are identical across targets (e.g., row 1 setting
`gatewayClassName`, the TLS listener rows, the basic hostname/path/backend
mapping) have a single `both` column.

---

## Translation table

| # | Annotation | Category | Traefik target (default) | GKE target (opt-in) | Converter action |
|---|---|---|---|---|---|
| 1 | `kubernetes.io/ingress.class: nginx` | portable | `Gateway.spec.gatewayClassName: traefik` (or `--gateway-class` override) | `Gateway.spec.gatewayClassName: gke-l7-global-external-managed` (or `--gateway-class` override) | drop from resource, set on Gateway |
| 2 | `cert-manager.io/cluster-issuer: <x>` | portable | **drop-info** — cert-manager continues to populate the Secrets referenced by `listener.tls.certificateRefs[kind=Secret]`; no new Certificate CR emitted | Same as Traefik path when `spec.tls[].secretName` is present. If the source also had `networking.gke.io/managed-certificates`, that takes precedence for GKE. | preserve existing cert-manager setup |
| 3 | `networking.gke.io/managed-certificates: a,b,c` | portable-GKE | **drop-info** — Traefik does not use `ManagedCertificate`. WARN in the report that the annotation listed certs that won't be referenced. | split by comma; each name → `listener.tls.certificateRefs[kind=ManagedCertificate]` | preserve or drop depending on target |
| 4 | `nginx.ingress/mergeable-ingress-type: master\|minion` | drop-info | drop — HTTPRoutes merge natively via `parentRef` | same | drop with INFO record |
| 5 | `nginx.ingress.kubernetes.io/enable-cors: "true"` | convertible | **1× `Middleware` kind: headers**, namespace-scoped to each target (shared via `filters[].extensionRef`) | **N× `GCPBackendPolicy.spec.cors`**, one per backend Service | emit CORS middleware(s) — see §CORS below |
| 6 | `nginx.ingress.kubernetes.io/cors-allow-origin: "*"` | convertible | `Middleware.spec.headers.accessControlAllowOriginList: ["*"]` | merge into `GCPBackendPolicy.spec.cors.allowOrigins` from #5 | merge into policy from #5 |
| 7 | `nginx.ingress.kubernetes.io/cors-allow-methods` | convertible | `Middleware.spec.headers.accessControlAllowMethods: [...]` | `GCPBackendPolicy.spec.cors.allowMethods: [...]` | split comma-string, normalize |
| 8 | `nginx.ingress.kubernetes.io/cors-allow-headers` | convertible | `Middleware.spec.headers.accessControlAllowHeaders: [...]` | `GCPBackendPolicy.spec.cors.allowHeaders: [...]` | split comma-string, normalize |
| 9a | `server-snippet` — `X-Content-Type-Options`, `X-XSS-Protection`, `X-Frame-Options` response headers | split-category (auto) | `HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add` | same | auto-convert; loss-free, both targets |
| 9b | `server-snippet` — `add_header Set-Cookie "..."` with no cookie name | split-category (stub) | No direct equivalent; TODO stub + Manual Review entry | same | emit stub, non-blocking |
| 9c | `server-snippet` — `location ~ .../ { return 404; }` path denylists | split-category (stub→auto under Traefik) | **1× `Middleware` kind: redirectRegex** returning 404 for matching paths. Plugin-based alternative (`blockpath`) emitted as commented-out option. NO longer a stub. | **still a stub** — Cloud Armor territory; TODO comment with Cloud Armor pointer | Traefik: emit middleware; GKE: emit stub |
| 10 | `nginx.org/proxy-{connect,read,send}-timeout` | convertible-lossy | **`ServersTransport.spec.forwardingTimeouts.{dialTimeout,responseHeaderTimeout,idleConnTimeout}`** — preserves the 3 separate values (less lossy than GKE!) | `GCPBackendPolicy.spec.timeoutSec = max(read, send, connect)` (collapsed to one value) | Traefik: preserve granularity; GKE: collapse with WARN |
| 11 | `spec.tls[].hosts` + `spec.tls[].secretName` | portable | One `listener` per hostname group with `certificateRefs[kind=Secret]` | same (also supports `kind: ManagedCertificate` if the row-3 annotation listed the host) | preserve Secret names exactly |
| 12 | `spec.rules[].host` (host-only, no paths) | portable | One HTTPRoute per hostname, single `PathPrefix /` rule, `parentRef` on the hostname's listener | same | one-to-one mapping |
| 13 | `spec.rules[].http.paths[].backend.service` | portable | `HTTPRoute.spec.rules[].backendRefs[]` with same Service name + port | same | preserve; HALT if Service not found in module |

---

## Category definitions

- **portable** — translates 1:1 with no information loss
- **portable-GKE** — translates to a GKE-specific resource; not portable to other GatewayClasses
- **convertible** — translates to a new kind of resource (e.g., `GCPBackendPolicy`)
- **convertible-lossy** — translation drops information; WARN in report
- **split-category (auto)** — part of the annotation auto-converts, part gets stubbed
- **split-category (stub)** — cannot auto-convert; TODO stub with Manual Review entry
- **drop-info** — annotation is obsolete under Gateway API; drop silently with an INFO record in state

---

## Row 9 detail: server-snippet split

NGINX `server-snippet` is a catch-all escape hatch that embeds raw NGINX
directives. Because it can contain arbitrary directives, the converter must
classify each directive individually and take the least-risky action per class.
Three sub-cases arise in practice:

### 9a — Security headers (auto-convert)

**Source pattern:**

```nginx
server-snippet: |
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Frame-Options SAMEORIGIN;
```

**Target — HTTPRoute `responseHeaderModifier` filter:**

```yaml
filters:
  - type: ResponseHeaderModifier
    responseHeaderModifier:
      add:
        - name: X-Content-Type-Options
          value: nosniff
        - name: X-XSS-Protection
          value: "1; mode=block"
        - name: X-Frame-Options
          value: SAMEORIGIN
```

This is a loss-free conversion. The header names and values are known constants;
the converter recognises each by exact string match and emits the YAML fragment
above into every HTTPRoute rule that was attached to the annotated Ingress.

**Duplication risk (runbook flag):** If the operator later moves these security
headers to the application layer (e.g., via a response-headers middleware in the
app framework), the headers will be set twice — once by the HTTPRoute filter and
once by the app. The migration report surfaces a **Duplication Risk** notice:

> Row 9a auto-converted X-* security headers to HTTPRoute responseHeaderModifier.
> If your application sets the same headers, remove one source to avoid
> duplicate header values being forwarded to clients.

### 9b — Set-Cookie rewrites (stub)

**Source pattern:**

```nginx
server-snippet: |
  add_header Set-Cookie "SameSite=None; Secure";
```

`add_header Set-Cookie "..."` with no cookie name is almost certainly legacy bug
config. NGINX's `add_header` directive adds a new response header — it does not
rewrite or modify existing `Set-Cookie` headers emitted by the upstream. Without
a cookie name, the directive inserts a malformed `Set-Cookie` header (missing the
required `name=value` pair) that browsers will typically ignore.

Because the intended semantics are ambiguous, the converter **cannot** produce a
correct Gateway API equivalent. It emits:

1. A `# TODO(gateway-migrate): manual review required` stub comment in the
   generated HTTPRoute file.
2. A **Manual Review** entry in the migration report:

   > Row 9b: `add_header Set-Cookie` directive found with no cookie name.
   > This is likely a legacy NGINX misconfiguration. Decide whether the intent
   > was (a) to set a new cookie — use an app-layer `Set-Cookie` header, or
   > (b) to rewrite an existing cookie — use a `GCPBackendPolicy`
   > `responseHeaderModifier` with the exact `name=value` pair.

The migrated module will still pass `kustomize build` but the behaviour is
functionally incomplete until the operator resolves the stub.

### 9c — Path denylists (stub)

**Source patterns:**

```nginx
server-snippet: |
  location ~ \.(ht|env|git|config|bak|sql|log)$ { return 404; }
  location ~ /(.git|dbconfig|wp-admin|phpmyadmin) { return 404; }
```

These `location ~ ... { return 404; }` blocks are WAF / deny-list rules that
block requests to sensitive paths. Gateway API has no native equivalent resource
for this pattern. The correct migration target is a
[Cloud Armor security policy](https://cloud.google.com/armor/docs/security-policy-overview).

Cloud Armor supports:

- **Preconfigured WAF rules** — `evaluatePreconfiguredWaf('lfi-v33-stable')` and
  similar rule sets cover common path-traversal and sensitive-file access
  patterns.
- **Custom rules** — `request.path.matches('/(\.git|dbconfig|wp-admin)')` with
  action `deny(404)`.

The converter emits:

1. A `# TODO(gateway-migrate): manual review required` stub comment.
2. A **Manual Review** entry in the migration report:

   > Row 9c: path denylist `location ~ ...` found. This is WAF territory.
   > Create a Cloud Armor security policy with matching custom rules and attach
   > it to the `GCPBackendPolicy` via `spec.securityPolicy.name`.
   > Reference: https://cloud.google.com/armor/docs/security-policy-overview

The migrated module will still pass `kustomize build` but traffic to the denied
paths will **not** be blocked until the Cloud Armor policy is applied.

---

## CORS translation detail (rows 5–8)

**Traefik target**: CORS is a single `Middleware` of kind `headers`, shared
across every HTTPRoute that needs CORS via `filters[].extensionRef`. One
middleware per *target namespace* (because Traefik resolves `extensionRef`
against the HTTPRoute's own namespace by default). For a module with 11
backends across 7 namespaces, the skill emits **7 Middleware resources**
(one per namespace), each with identical CORS config.

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: common-cors
  namespace: <httproute-namespace>
spec:
  headers:
    accessControlAllowOriginList: ["*"]
    accessControlAllowMethods: [PUT, GET, POST, OPTIONS]
    accessControlAllowHeaders: [DNT, X-CustomHeader, ...]
    accessControlMaxAge: 100
    addVaryHeader: true
```

HTTPRoute filter:

```yaml
rules:
  - filters:
      - type: ExtensionRef
        extensionRef:
          group: traefik.io
          kind: Middleware
          name: common-cors
    # ...
```

**GKE target**: CORS attaches to backend Services via `GCPBackendPolicy`, not
to the Gateway or HTTPRoute. Every backend Service that needs CORS gets its
own `GCPBackendPolicy` resource, because the policy's `targetRef` points at
one Service at a time. For a module with 11 backends, the skill emits **11
GCPBackendPolicy resources**.

The one-to-many expansion is the key trade-off called out in every GKE-target
report. Traefik's middleware pattern sidesteps it by allowing sharing
across HTTPRoutes.

## Path-denylist translation detail (row 9c)

**Traefik target**: `location ~ ... { return 404; }` becomes a `Middleware` of
kind `redirectRegex` whose replacement path triggers a 404 (Traefik doesn't
have a first-class "return 404" middleware; this is the clean plugin-free
workaround). The skill also emits a commented-out alternative using the
`blockpath` Yaegi plugin for operators who have it installed in Traefik's
static config.

```yaml
# Default — plugin-free, regex-only
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: block-sensitive-paths
  namespace: <target-namespace>
spec:
  redirectRegex:
    regex: "^(.*/)(\\.ht|\\.env|\\.git|\\.svn|\\.bak|\\.sql|\\.log)$"
    replacement: "/__blocked_by_gateway_migrate__"
    permanent: false
```

HTTPRoutes that need the protection reference this middleware via the same
`ExtensionRef` pattern as CORS. Under Traefik, **row 9c is no longer a stub**
— it's fully auto-converted.

**GKE target**: still a stub with a Cloud Armor pointer. Cloud Armor is the
correct home for path-based WAF rules in GCP, but requires out-of-band setup
that the skill can't automate. Operators run `gcloud compute security-policies
create` manually and attach via `GCPBackendPolicy.spec.securityPolicy.name`.

## Trade-offs called out in every report

1. A module migrated with TODO stubs can `kustomize build` cleanly but be
   *functionally incomplete*. Validation checks syntax, not semantics.

2. Per-hostname listeners can produce large Gateway resources (a 12-hostname
   module produces up to 24 listeners — one HTTP + one HTTPS per host). Both
   targets share this limitation. Wildcard consolidation is a v2 feature.

3. **CORS scaling**: under Traefik, one Middleware per namespace. Under GKE,
   one `GCPBackendPolicy` per backend Service. Traefik target is typically
   3–5× fewer files for modules with many backends.

4. **Path denylists**: under Traefik, auto-converted. Under GKE, always a
   manual-review stub requiring Cloud Armor setup.
