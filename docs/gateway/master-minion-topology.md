# Master/Minion Topology Detection

The NGINX `mergeable-ingress-type` pattern splits Ingress resources across two
Kustomize modules: a master (host-only, TLS-owning, SRE-owned) and one or more
minions (paths + backends, app-dev-owned, no TLS section). NGINX merges them at
runtime into a single virtual server. This split maps cleanly onto Gateway API's
persona model — the master becomes a SRE-owned `Gateway` resource declaring
listeners per host, while each minion becomes an app-dev-owned `HTTPRoute`
resource carrying paths and backend references. Migrating off
`mergeable-ingress-type` is one of the main wins of Gateway API: the runtime
merging becomes native `HTTPRoute` attachment via `parentRef`, and the two-module
ownership boundary is preserved rather than collapsed. Detecting this topology
correctly before conversion is the first thing the skill does, because the entire
output structure — two modules, cross-namespace parentRefs, one HTTPRoute per
minion — depends on it.

## Classification rules

**Classification rules for every `kind: Ingress` found in the repo:**

| Signal | Classification |
|---|---|
| `metadata.annotations["nginx.ingress/mergeable-ingress-type"] == "master"` | master (strong) |
| `spec.rules[].host` present AND no `spec.rules[].http.paths` anywhere | master (heuristic) |
| `spec.rules[].http.paths[]` present AND no `spec.tls` AND `ingress.class: nginx` | minion |
| `spec.rules[].host` + `spec.rules[].http.paths[]` + `spec.tls` in one resource | standalone |

## Pairing algorithm

1. For each minion, take its `spec.rules[].host` values.
2. Search all masters for a matching host (case-insensitive, exact match).
3. If a minion's host matches exactly one master → pair them.
4. If a minion's host matches zero masters → orphan minion (HALT).
5. If a minion's host matches multiple masters → ambiguous (HALT).
6. For each master host with no matching minion → orphan host (WARN, proceed).

## Worked example — eye-of-horus-gitops

**Master file:** `common.ingress/base/app.ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-master
  annotations:
    nginx.ingress/mergeable-ingress-type: "master"
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: argocd.awoo.org
    - host: grafana.awoo.org
    - host: airflow.awoo.org
  tls:
    - hosts:
        - argocd.awoo.org
        - grafana.awoo.org
        - airflow.awoo.org
      secretName: managed-cert
```

**Minion file:** `common.service/overlays/dev/argocd-nginx-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-minion
  annotations:
    nginx.ingress/mergeable-ingress-type: "minion"
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: argocd.awoo.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```

**Result:** The master's host `argocd.awoo.org` matches the minion's host
exactly (case-insensitive). The pair is formed: the master drives the
`Gateway` listener for `argocd.awoo.org`; the minion is converted to an
`HTTPRoute` in the `argocd` namespace with `parentRef` pointing at that
`Gateway`.

## Standalone fallback

If no master is detected — meaning no Ingress in the repo matches the first two
classification signals (the strong `mergeable-ingress-type: master` annotation
or the heuristic host-only rule) — the skill falls back to single-module
migration. In this mode, both the `Gateway` resource and all its `HTTPRoute`
resources are co-located inside one new `common.gateway/` module, mirroring the
structure of the original standalone Ingress rather than splitting ownership
across two modules.

## Cross-namespace parentRef requirements

- Gateway lives in master's namespace (`ingress-nginx` in the reference repo).
- HTTPRoutes live in each service's namespace (`argocd`, `monitoring`, etc.).
- Gateway listener must set `allowedRoutes.namespaces.from: Selector` with label selector `gateway-access: ingress-nginx`.
- User must label target namespaces with `kubectl label namespace <ns> gateway-access=ingress-nginx` before HTTPRoutes attach — the skill surfaces this command in the runbook.
- No `ReferenceGrant` needed: each HTTPRoute's `backendRefs[]` are same-namespace (the backend Service lives in the same namespace as the HTTPRoute).
