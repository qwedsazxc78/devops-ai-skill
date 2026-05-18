# nginx → Traefik Ingress Annotation Translation

Authoritative table for `*nginx-to-traefik` skill A. Every row is a
deterministic translation decision the converter makes every run.

| # | nginx annotation | Category | Traefik Ingress equivalent | Converter action |
|---|---|---|---|---|
| 1 | `kubernetes.io/ingress.class: nginx` | portable | `ingressClassName: traefik` on `spec` | Always rewrite |
| 2 | `nginx.ingress.kubernetes.io/ssl-redirect: "true"` | drop-info | Implicit via Traefik EntryPoint (`websecure` redirect) | Drop; INFO in state |
| 3 | `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"` | drop-info | Same as row 2 | Drop; INFO in state |
| 4 | `nginx.ingress.kubernetes.io/backend-protocol: HTTPS` | convertible | `traefik.ingress.kubernetes.io/service.serversscheme: https` annotation | Translate |
| 5 | `nginx.ingress.kubernetes.io/proxy-body-size: 50m` | convertible-lossy | Middleware `buffering.maxRequestBodyBytes: 52428800` | WARN: unit conversion in report risk register |
| 6 | `nginx.ingress.kubernetes.io/cors-allow-origin: "*"` | convertible | Middleware `headers.accessControlAllowOriginList: ["*"]` | Reuse `cors@kubernetescrd` Middleware in `traefik` namespace if present; else stub |
| 7 | `nginx.ingress.kubernetes.io/configuration-snippet: <raw nginx>` | split-category (stub) | None — Traefik has no equivalent | Emit Traefik Ingress with TODO comment + WARN in report |
| 8 | `cert-manager.io/cluster-issuer: <name>` | portable | Same annotation | Carry through unchanged |
| 9 | `cert-manager.io/dns01-recursive-nameservers: <ns>` | portable | Same annotation | Carry through unchanged |
| 10 | `nginx.ingress.kubernetes.io/rewrite-target: <path>` | convertible | Middleware `replacePathRegex.replacement` | Translate (single-segment only); WARN otherwise |

## Category definitions

- **portable** — translates 1:1 with no information loss
- **convertible** — translates to a Traefik-specific resource/annotation
- **convertible-lossy** — translation drops information; WARN in report
- **drop-info** — annotation is obsolete under Traefik; drop silently with INFO in state
- **split-category (stub)** — cannot auto-convert; emit TODO + WARN

## Trade-offs called out in every Skill A report

1. **`configuration-snippet`** never translates — operators must rewrite the snippet as a Traefik Middleware manually.
2. **Body size limits** require unit conversion (`50m` → `52428800` bytes); always WARN to catch typos.
3. **CORS Middleware reuse**: if `cors@kubernetescrd` exists in the `traefik` namespace, skill A links to it; never regenerates.
