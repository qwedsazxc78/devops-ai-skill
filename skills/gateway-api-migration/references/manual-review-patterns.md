# Manual Review Patterns

Deep guidance on annotations that `*gateway-migrate` cannot auto-convert.
The skill emits `TODO(gateway-migrate):` stubs pointing back here.

---

## Pattern: server-snippet security headers

**What each header protects against:**

- `X-Content-Type-Options: nosniff` — prevents browsers from MIME-sniffing a
  response away from the declared `Content-Type`. Mitigates drive-by download
  attacks where a script is served as `text/plain` but executed as JavaScript.

- `X-XSS-Protection: 1; mode=block` — instructs older browsers (IE, pre-78
  Chrome) to block pages when a reflected XSS attack is detected. Modern
  browsers ignore this header in favour of CSP, but legacy clients may require
  it.

- `X-Frame-Options: SAMEORIGIN` — prevents the page from being embedded in an
  `<iframe>` on a cross-origin domain. Mitigates clickjacking attacks.

**Auto-conversion (row 9a):** the skill extracts these three headers from the
NGINX `server-snippet` and places them in the HTTPRoute as a
`ResponseHeaderModifier` filter:

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

**WARNING — duplication risk:** if the application also sets these headers at
the app layer (Helmet.js, Spring Security, Django's `SecurityMiddleware`,
etc.), both the Gateway filter and the app will add them to the response,
resulting in duplicate headers. Browsers typically use the first occurrence,
but this is fragile.

**Action:** pick one home for these headers and delete the other. The Gateway
filter is the right home for a shared platform policy; app-layer headers are
the right home if each service has different requirements.

---

## Pattern: server-snippet Set-Cookie rewrites

**What this looks like in NGINX:**

```nginx
add_header Set-Cookie "SameSite=None; Secure";
```

**Why it cannot be auto-converted:** `add_header Set-Cookie "..."` with no
cookie name is NGINX adding a raw `Set-Cookie` *response header*, not rewriting
an existing cookie that the application set. This is almost always legacy
misconfiguration — the intent was probably to add `SameSite` and `Secure`
flags to existing application cookies, but NGINX's `add_header` directive does
not modify existing headers; it appends a new one.

The result is a bare `Set-Cookie: SameSite=None; Secure` header with no name
and no value, which most browsers silently discard. The annotation is therefore
a no-op in practice.

**Recommendation:**

1. **Remove entirely** if the cookie flags are being set by the application or
   a proper cookie serialisation library (the annotation is doing nothing).
2. **Migrate to app-layer cookie serialisation** if you genuinely need
   `SameSite=None; Secure` on cookies — set the flags in the framework's
   session/cookie configuration.

**Do NOT** try to fake this with a Gateway `ResponseHeaderModifier` filter.
There is no clean Gateway API equivalent for rewriting individual cookie
attributes on headers added by a backend service.

The skill emits a `TODO(gateway-migrate): Set-Cookie snippet` stub in the
generated HTTPRoute. Review and delete the stub after deciding.

---

## Pattern: server-snippet path denylists (Cloud Armor territory)

**What this looks like in NGINX:**

```nginx
location ~ \.(ht|env|git|svn|bak|sql|log)$ {
    return 404;
}
```

**Why it cannot be auto-converted:** these `location` blocks perform
WAF-style request filtering — blocking requests by URI pattern. Gateway API
has no native equivalent at the HTTPRoute level. Attempting to model this
with HTTPRoute `matches` rules would create a fragile allowlist/denylist
that is hard to maintain and easy to misconfigure.

**Correct home:** [GCP Cloud Armor security policies](https://cloud.google.com/armor/docs/security-policy-overview)
attached to the backend via `GCPBackendPolicy.spec.securityPolicy`.

Minimal Cloud Armor rule example (gcloud CLI):

```bash
# Create a security policy
gcloud compute security-policies create block-sensitive-paths \
  --description "Block requests to sensitive file extensions"

# Add a rule matching the path pattern
gcloud compute security-policies rules create 1000 \
  --security-policy block-sensitive-paths \
  --expression "request.path.matches('(?i)\\.(ht|env|git|svn|bak|sql|log)$')" \
  --action deny-404

# Attach to the backend service
gcloud compute backend-services update <backend-service-name> \
  --security-policy block-sensitive-paths \
  --global
```

Or equivalently in a `GCPBackendPolicy` YAML:

```yaml
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: {{service}}-backend-policy
  namespace: {{namespace}}
spec:
  default:
    securityPolicy: block-sensitive-paths
  targetRef:
    group: ""
    kind: Service
    name: {{service}}
```

**Note:** the skill emits `TODO(gateway-migrate): path-denylist snippet` stubs
for these location blocks. It does NOT generate the Cloud Armor policy
automatically because the correct rule semantics (which paths, which response
code, allow vs. deny) depend on the application's specific threat model.

---

## Pattern: mergeable-ingress-type

**What this looks like in NGINX:**

```yaml
nginx.ingress.kubernetes.io/mergeable-ingress-type: "master"
# or
nginx.ingress.kubernetes.io/mergeable-ingress-type: "minion"
```

**Why no action is needed:** the NGINX master/minion model is *obsolete* under
Gateway API. The master annotation exists solely to declare a "virtual host
parent" — a role that HTTPRoute fills natively through its `parentRef` field.

Each HTTPRoute attaches to a specific Gateway listener via `parentRef.sectionName`.
This is exactly what `mergeable-ingress-type: minion` was doing — attaching a
route fragment to a parent. The parent concept is built into the Gateway API
spec; there is no need for an annotation to declare it.

**Skill behaviour (row 4 in `annotation-map.md`):** the skill drops
`mergeable-ingress-type` as a **drop-info** annotation. The state file records
the drop. No action is required from the reviewer.

---

## Pattern: proxy-*-timeout

**What this looks like in NGINX annotations:**

```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"
nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
```

**The problem:** NGINX exposes three independent timeout controls:

| Annotation | Controls |
|---|---|
| `proxy-connect-timeout` | Time to establish TCP connection to upstream |
| `proxy-read-timeout` | Time between successive reads from upstream |
| `proxy-send-timeout` | Time between successive writes to upstream |

GKE's `GCPBackendPolicy.spec.timeoutSec` is a **single value** that represents
the overall request timeout. There is no per-phase granularity.

**Skill behaviour:** the skill collapses the three values to
`max(connect, read, send)` and records a `WARN` in the migration report. The
generated `GCPBackendPolicy` uses this maximum value.

**Action required if timeouts were deliberately different:** if `proxy-connect-timeout`
was intentionally much lower than `proxy-read-timeout` (e.g. to fail-fast on
unavailable backends while allowing long-running streaming reads), the collapsed
value will be too permissive for the connect phase.

Options:
1. Accept the collapsed timeout if the difference was not intentional (most common).
2. Implement a per-phase timeout at the application layer (e.g. configure
   the HTTP client's connect/read timeouts in the service itself).
3. Use Cloud Armor or a service mesh (Istio/ASM) if per-phase Gateway-level
   timeout control is a hard requirement.

Review the WARN in the report's Section 4 and confirm which option applies.
