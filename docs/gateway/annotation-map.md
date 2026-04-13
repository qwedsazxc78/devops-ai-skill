# NGINX Ingress → GKE Gateway API Annotation Map

Canonical translation table for `*gateway-migrate`. Each row represents a
deterministic decision the converter makes every run. Single source of truth —
the skill's `references/annotation-map.md` symlinks here.

---

## Translation table

| # | Annotation | Category | GKE Gateway translation | Converter action |
|---|---|---|---|---|
| 1 | `kubernetes.io/ingress.class: nginx` | portable | `Gateway.spec.gatewayClassName: gke-l7-global-external-managed` | drop from resource, set on Gateway |
| 2 | `cert-manager.io/cluster-issuer: <x>` | portable | Preserved on `Certificate` resource referenced by Gateway listener | preserve; emit Certificate CR |
| 3 | `networking.gke.io/managed-certificates: a,b,c` | portable-GKE | Split by comma; each name becomes a `listener.tls.certificateRefs[kind=ManagedCertificate]` entry | one listener per hostname group; keep existing ManagedCertificate resources |
| 4 | `nginx.ingress/mergeable-ingress-type: master` | drop-info | No equivalent needed; HTTPRoutes merge natively | drop with INFO record |
| 5 | `nginx.ingress.kubernetes.io/enable-cors: "true"` | convertible | `GCPBackendPolicy.spec.cors` enabled | emit one GCPBackendPolicy per affected Service |
| 6 | `nginx.ingress.kubernetes.io/cors-allow-origin: "*"` | convertible | `GCPBackendPolicy.spec.cors.allowOrigins: ["*"]` | merge into policy from #5 |
| 7 | `nginx.ingress.kubernetes.io/cors-allow-methods` | convertible | `GCPBackendPolicy.spec.cors.allowMethods: [...]` | split comma-string, normalize |
| 8 | `nginx.ingress.kubernetes.io/cors-allow-headers` | convertible | `GCPBackendPolicy.spec.cors.allowHeaders: [...]` | split comma-string, normalize |
| 9a | `server-snippet` — `X-Content-Type-Options`, `X-XSS-Protection`, `X-Frame-Options` response headers | split-category (auto) | `HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add` | auto-convert; loss-free |
| 9b | `server-snippet` — `add_header Set-Cookie "..."` with no cookie name | split-category (stub) | No direct equivalent; likely legacy bug | TODO stub + Manual Review entry |
| 9c | `server-snippet` — `location ~ .../ { return 404; }` path denylists | split-category (stub) | Cloud Armor security policy territory | TODO stub + Manual Review entry with Cloud Armor pointer |
| 10 | `nginx.org/proxy-{connect,read,send}-timeout` | convertible-lossy | `GCPBackendPolicy.spec.timeoutSec` (single value) | emit `timeoutSec = max(read, send, connect)`, WARN in report |
| 11 | `spec.tls[].hosts` + `spec.tls[].secretName` | portable | One `listener` per hostname group with matching `certificateRefs` | preserve Secret names exactly |
| 12 | `spec.rules[].host` (host-only, no paths) | portable | One HTTPRoute per hostname, single `PathPrefix /` rule, `parentRef` on the hostname's listener | one-to-one mapping |
| 13 | `spec.rules[].http.paths[].backend.service` | portable | `HTTPRoute.spec.rules[].backendRefs[]` with same Service name + port | preserve; HALT if Service not found in module |

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

## Trade-offs called out in every report

1. A module migrated with TODO stubs can `kustomize build` cleanly but be
   *functionally incomplete*. Validation checks syntax, not semantics.

2. Per-hostname listeners can produce large Gateway resources (a 12-hostname
   module produces up to 24 listeners — one HTTP + one HTTPS per host).

3. CORS is attached to Services via `GCPBackendPolicy`, not to the Gateway or
   the HTTPRoute. An Ingress-level CORS annotation with 8 backends becomes 8
   `GCPBackendPolicy` resources. Reports must surface this "one-to-many"
   expansion.
