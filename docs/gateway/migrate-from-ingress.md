# Migrating from Ingress to Gateway API

> **Read this before running `*gateway-migrate`.** Explains the conceptual transformations the skill automates. For the operational runbook, see the report at `docs/reports/gateway-migration/<module>/report.md` after running the skill.

## Key differences

### Personas

The Ingress API has one user persona: the owner of Ingress resources who controls TLS termination, load-balancing infrastructure, and routing in a single object. With NGINX specifically, this surfaces as the master/minion split: SREs own master Ingress objects, app developers own minion Ingress objects — an informal convention bolted onto a single-persona API.

Gateway API formalizes four explicit personas: **infrastructure provider**, **cluster operator**, **application admin**, and **application developer**. The master/minion split maps cleanly: SREs become cluster operators who own Gateway resources; app developers own HTTPRoute resources. RBAC can enforce this boundary rather than relying on naming conventions.

| Ingress API Persona | Gateway API Persona |
|---------------------|---------------------|
| User | Application developer, Application admin, Cluster operator |
| Cluster operator | Cluster operator |
| Infrastructure provider | Infrastructure provider |

### Available features

Ingress natively supports only TLS termination and content-based routing (host header + URI path). Everything else — TLS redirects, response-header manipulation, traffic splitting, method/header/query-param matching, request mirroring — lives in implementation-specific annotations that don't transfer between controllers.

Gateway API natively covers all of the above as first-class fields on HTTPRoute and Gateway resources. Migrating off annotations is not optional cleanup; it is how you get portability.

### Extensibility approach

Ingress uses annotations: unstructured key-value pairs applied at the resource level, specific to each controller implementation.

Gateway API uses three structured extension points:

- **External references** — fields on HTTPRouteFilter, BackendObjectReference, or SecretObjectReference can point to implementation-specific custom resources.
- **Custom filter extensions** — the `extensionRef` field on HTTPRouteFilter allows implementation-specific filters without annotations.
- **Policy Attachment** — implementations define Policy custom resources that reference (not are referenced by) Gateway API objects, following a standard UX pattern. See the upstream Policy Attachment guide.

Annotations on Gateway API resources are strongly discouraged by the spec.

## Feature mapping

| Ingress concept | Gateway API equivalent | Notes |
|----------------|------------------------|-------|
| Implicit HTTP/HTTPS entry points | Explicit `Gateway` listeners on port 80 / 443 | Gateway owned by cluster operator / app admin |
| `spec.tls[].secretName` | `listener.tls.certificateRefs[].name` (Secret) | TLS termination moves to the listener |
| `spec.rules[].host` | `HTTPRoute.spec.hostnames[]` | Hostnames must match listener's `hostname` filter |
| `spec.rules[].http.paths[]` | `HTTPRoute.spec.rules[].matches[]` | Path types map directly (Prefix, Exact) |
| Per-hostname rules in one Ingress | One HTTPRoute per hostname (recommended) or shared HTTPRoute with merged rules | Rules in an HTTPRoute apply to all listed hostnames |
| NGINX mergeable-ingress-type master/minion | Native HTTPRoute merging via `parentRef` + `sectionName` | Conflict resolution is spec-defined, not controller-specific |
| `spec.defaultBackend` | No equivalent — define explicit catch-all rule (`/` Prefix) | Must be explicit; no implicit fallback |
| `spec.ingressClassName` | `HTTPRoute.spec.parentRefs[].name` → Gateway name | Also set `gatewayClassName` on the Gateway resource |
| TLS redirect annotation | Separate HTTPRoute on HTTP listener with `RequestRedirect` filter | See Worked example below |
| Traffic splitting annotation | `HTTPRoute.spec.rules[].backendRefs[].weight` | Native field, no annotation needed |
| Header/method/query matching annotations | `HTTPRoute.spec.rules[].matches[].headers/method/queryParams` | Native fields |

## Worked example

The input is a single Ingress with two hostnames, TLS, per-host path routing, and a `tls-redirect` annotation. The output is three Gateway API resources.

**Assumptions:**

- All resources in the same namespace.
- IngressClass `prod` and GatewayClass `prod` both exist in the cluster.
- The `tls-redirect` annotation is implementation-specific to `some-ingress-controller.example.org`.
- Referenced Secret and Service contents are omitted.

### Input: Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: example-ingress
  annotations:
    some-ingress-controller.example.org/tls-redirect: "True"
spec:
  ingressClassName: prod
  tls:
  - hosts:
    - foo.example.com
    - bar.example.com
    secretName: example-com
  rules:
  - host: foo.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: foo-app
            port:
              number: 80
      - path: /orders
        pathType: Prefix
        backend:
          service:
            name: foo-orders-app
            port:
              number: 80
  - host: bar.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: bar-app
            port:
              number: 80
```

### Output Step 1: Gateway

Replaces the implicit Ingress entry points. Defines HTTP and HTTPS listeners explicitly. TLS termination moves here from `spec.tls`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: example-gateway
spec:
  gatewayClassName: prod
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: "*.example.com"
  - name: https
    port: 443
    protocol: HTTPS
    hostname: "*.example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: example-com
  - name: https-default-tls-mode
    port: 8443
    protocol: HTTPS
    hostname: "*.foo.com"
    tls:
      certificateRefs:
      - kind: Secret
        name: foo-com
```

### Output Step 2: HTTPRoutes (one per hostname)

The single Ingress with two `rules[]` entries splits into two HTTPRoutes. Each attaches to the `https` listener via `parentRef.sectionName`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: foo
spec:
  parentRefs:
  - name: example-gateway
    sectionName: https
  hostnames:
  - foo.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: foo-app
      port: 80
  - matches:
    - path:
        type: PathPrefix
        value: /orders
    backendRefs:
    - name: foo-orders-app
      port: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: bar
spec:
  parentRefs:
  - name: example-gateway
    sectionName: https
  hostnames:
  - bar.example.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: bar-app
      port: 80
```

### Output Step 3: TLS redirect HTTPRoute

Replaces the `tls-redirect` annotation. Attaches to the `http` listener and issues a `RequestRedirect` to HTTPS for both hostnames.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: tls-redirect
spec:
  parentRefs:
  - name: example-gateway
    sectionName: http
  hostnames:
  - foo.example.com
  - bar.example.com
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        port: 443
```

## Implementation-specific annotations

The 13-row translation table mapping NGINX Ingress annotations to their Gateway API equivalents (HTTPRoute fields, Policy Attachment resources, or GKE-specific extensions) is maintained in [`annotation-map.md`](annotation-map.md). Do not guess annotation translations from the mapping above — consult that table, as several annotations have no portable Gateway API equivalent and require implementation-specific Policy resources.

## Automatic conversion

The `ingress2gateway` tool can auto-translate Ingress resources to HTTPRoute resources and is used by the `*gateway-migrate` skill as a second-opinion cross-check against the manual conversion. Its scope, flags, and known gaps are documented in [`ingress2gateway-integration.md`](ingress2gateway-integration.md).
