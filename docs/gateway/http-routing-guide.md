# HTTPRoute Reference

This is a distilled HTTPRoute reference for `*gateway-migrate`, tailored to the migrations the skill actually performs. It covers the subset of the Gateway API HTTPRoute spec that the skill generates or directly depends on — path matching, the filters it emits, and parentRef attachment mechanics. For the full upstream specification, see gateway-api.sigs.k8s.io/guides/http-routing/.

All YAML the skill generates targets `apiVersion: gateway.networking.k8s.io/v1` (GA since Gateway API v1.0). Do not use the `v1beta1` API version for new resources — it is deprecated and will be removed in a future release of the Gateway API.

## Anatomy of an HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <svc>
  namespace: <svc-namespace>
spec:
  parentRefs:                    # which Gateway listener to attach to
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: common-gateway
      namespace: ingress-nginx
      sectionName: <listener-name>   # must match a listener name on the Gateway
  hostnames:                     # SNI / Host-header match
    - <hostname>
  rules:
    - matches:
        - path:
            type: PathPrefix     # Exact | PathPrefix | RegularExpression
            value: /
      filters:                   # optional: header rewrites, redirects, mirrors
        - type: ResponseHeaderModifier
          responseHeaderModifier:
            add:
              - name: X-Frame-Options
                value: SAMEORIGIN
      backendRefs:
        - name: <service-name>
          port: <port>
          weight: 1              # traffic splitting; omit when only one backend
```

## Path matching

Gateway API supports three path match types on `rules[].matches[].path.type`:

- **PathPrefix** — matches the specified prefix and all sub-paths beneath it. Equivalent to Ingress `pathType: Prefix`. A value of `/api` matches `/api`, `/api/`, `/api/v1/users`, etc.
- **Exact** — matches only the literal string. Equivalent to Ingress `pathType: Exact`. A value of `/healthz` matches only `/healthz`, not `/healthz/`.
- **RegularExpression** — implementation-specific; not supported by all GatewayClasses. Some GKE Gateway modes do not support regex path matching. Avoid unless your GatewayClass explicitly documents support.

**Ingress mapping:**

| Ingress `pathType` | HTTPRoute `path.type` |
|---|---|
| `Prefix` | `PathPrefix` |
| `Exact` | `Exact` |
| `ImplementationSpecific` | Varies — review manually |

Trailing-slash semantics differ slightly between Ingress controllers and HTTPRoute implementations. For example, some NGINX Ingress configurations treat `/foo` and `/foo/` as equivalent under `Prefix`, while Gateway API implementations may not normalize the trailing slash identically. `*gateway-migrate` copies path values verbatim from the source Ingress and flags any trailing-slash edge cases in the migration report for manual review.

## Header and query matching

HTTPRoute supports fine-grained matching on request headers and query parameters. `*gateway-migrate` does **not** currently generate these — they are documented here for manual edits post-migration.

```yaml
# Header match — route only when X-Api-Version: 2 is present
- matches:
    - headers:
        - name: X-Api-Version
          value: "2"
          type: Exact         # Exact | RegularExpression

# Query parameter match — route only when ?debug=true is present
- matches:
    - queryParams:
        - name: debug
          value: "true"
```

Multiple entries within a single `matches[]` item are ANDed together (all conditions must be true). Multiple items in the `matches` list are ORed (any condition being true triggers the rule). Rules within a single HTTPRoute are evaluated in declaration order; the first matching rule wins.

Header and query matching can be combined with path matching in a single `matches[]` entry to create precise, multi-dimensional routing conditions.

## Filters used by *gateway-migrate

Filters are applied to matching requests (or responses) before forwarding. The skill generates two filter types and documents two more for manual use.

**RequestRedirect** (generated) — the skill creates a dedicated HTTPRoute attached to the port 80 listener whose sole purpose is to redirect all HTTP traffic to HTTPS:

```yaml
filters:
  - type: RequestRedirect
    requestRedirect:
      scheme: https
      port: 443
      statusCode: 301
```

**ResponseHeaderModifier** (generated) — maps security annotations from `annotation-map.md` rows 9a. The skill injects X-* security headers as response header additions:

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

**URLRewrite** (available, not generated) — rewrites the request path or hostname before forwarding to the backend. Useful post-migration when path stripping is needed. Not emitted by the skill in v1; add manually if your Ingress used `nginx.ingress.kubernetes.io/rewrite-target`.

**RequestMirror** (not used in v1) — mirrors a copy of matching requests to a secondary backend without affecting the primary response. Useful for shadow testing a new service version.

**ExtensionRef** (not used in v1) — delegates filter logic to a provider-specific CRD. Behavior depends entirely on the GatewayClass implementation.

## Backend splitting (weighted)

Multiple entries in `backendRefs` with `weight` fields enable traffic splitting across backend services. `*gateway-migrate` does **not** generate weighted backends — it always emits a single `backendRef`. The following pattern is documented for manual canary deploys post-migration:

```yaml
backendRefs:
  - name: svc-v1
    port: 80
    weight: 90
  - name: svc-v2
    port: 80
    weight: 10
```

Weights are relative integers. The above sends 90 % of traffic to `svc-v1` and 10 % to `svc-v2`. Omitting `weight` on a single backend is equivalent to `weight: 1`.

Both backend services must exist in the same namespace as the HTTPRoute unless a `ReferenceGrant` is configured. The Gateway controller load-balances across healthy endpoints independently for each backend.

## Attachment rules

An HTTPRoute becomes active only when it successfully attaches to a Gateway listener. Three conditions must hold:

1. **`sectionName` must match a listener name.** `parentRefs[].sectionName` must equal the `name` field of an existing listener on the target Gateway. If the name does not match, the HTTPRoute remains unattached and no traffic is routed — check `kubectl get httproute -o yaml` for `status.parents` to diagnose.

2. **The Gateway must permit the HTTPRoute's namespace.** The Gateway's `listeners[].allowedRoutes.namespaces` setting controls which namespaces may attach. The skill configures `allowedRoutes.namespaces.from: Selector` with a namespace label `gateway-access: ingress-nginx`. Any namespace that needs to attach an HTTPRoute must carry this label. See `master-minion-topology.md` for the full label and ReferenceGrant setup.

3. **Multiple HTTPRoutes on the same listener are merged natively.** Gateway API merges routing rules from all attached HTTPRoutes into a single effective rule set — no special annotations needed. This is the native replacement for NGINX's `mergeable-ingress-type: master/minion` pattern covered in `master-minion-topology.md`.

**Diagnosing attachment failures:** run `kubectl get httproute <name> -n <namespace> -o jsonpath='{.status.parents}'` to see per-parent attachment status and reason codes. Common reasons: `NotAllowedByListeners` (namespace not permitted by `allowedRoutes`), `NoMatchingParent` (Gateway or `sectionName` not found), `ResolvedRefs` (backend Service missing or port incorrect). All three are surfaced in the HTTPRoute's `.status.parents[].conditions` array.

You can also check `kubectl describe httproute <name>` for human-readable events that explain why an HTTPRoute did not attach.

**Note on cross-namespace references:** when `backendRefs` point to a Service in a different namespace, a `ReferenceGrant` in the target namespace must explicitly permit it. The skill always co-locates the HTTPRoute with its backend Service, so cross-namespace `backendRefs` are not generated but may be needed for shared infrastructure services added post-migration.
