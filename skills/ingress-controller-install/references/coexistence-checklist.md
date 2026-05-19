# Coexistence Checklist — Traefik alongside ingress-nginx

This document is consulted by the `ingress-controller-install` skill in
Step 0 (pre-install awareness) and Step 4 (validation gates). It is also
the operator's post-install verification guide.

The guiding rule: **never share an IngressClass name, never share a
LoadBalancer IP, never let two controllers fight over ports 80/443**.

---

## Pre-install checks (run by Step 4)

### 1. IngressClass name uniqueness

| Check | Command | Pass condition |
|---|---|---|
| Existing classes | `kubectl get ingressclass -o jsonpath='{.items[*].metadata.name}'` | The chosen `ingressClassName` is absent (or, on UPGRADE, refers to a Traefik-owned class) |
| Default-class flag | `kubectl get ingressclass -o json \| jq '.items[] \| select(.metadata.annotations."ingressclass.kubernetes.io/is-default-class"=="true") \| .metadata.name'` | At most one default class. Traefik values set `ingressClass.isDefaultClass: false` to avoid stealing the default from nginx. |

**Failure remediation**: pick a non-conflicting `ingressClassName`. The
default `traefik` collides only if you previously installed Traefik under
a different release name — in that case use `traefik-v3` or `traefik-new`.

### 2. LoadBalancer IP uniqueness

| Check | Command | Pass condition |
|---|---|---|
| nginx LB IP | `kubectl -n ingress-nginx get svc -o jsonpath='{.items[*].status.loadBalancer.ingress[*].ip}'` | The chosen `lbIp` does not appear in the result |
| Any LB IP collision | `kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.status.loadBalancer.ingress[0].ip}{"\n"}{end}'` | The chosen `lbIp` does not appear |

**Failure remediation**: allocate a new static IP. On GCP:

```bash
gcloud compute addresses create traefik-${ENV}-ip \
  --region=${REGION} --project=${PROJECT_ID}
gcloud compute addresses describe traefik-${ENV}-ip \
  --region=${REGION} --format='value(address)'
```

### 3. Port collision

Ports 80/443 are exposed by the **Service** in front of each controller,
not by the controller pods directly. Two `Service` objects of type
`LoadBalancer` can each listen on 80/443 as long as they have different
external IPs. The collision risk is only inside the chosen namespace.

| Check | Command | Pass condition |
|---|---|---|
| Namespace conflict | `kubectl -n ${NAMESPACE} get svc -o json \| jq '.items[] \| select(.spec.type=="LoadBalancer") \| .spec.ports[].port'` | Either the namespace does not exist, or no existing `LoadBalancer` Service in that namespace already binds ports 80/443 under a different release |

**Failure remediation**: pick a different namespace (e.g. `traefik-v3`)
or delete the stale Service.

---

## Post-install verification (run by operator after `install.sh`)

Step-by-step sanity checks. Run these in order; stop on the first failure.

| # | Command | Expected |
|---|---|---|
| 1 | `helm -n ${NAMESPACE} list` | Release `traefik` present, status `deployed` |
| 2 | `kubectl -n ${NAMESPACE} rollout status deploy/traefik --timeout=120s` | `successfully rolled out` |
| 3 | `kubectl get ingressclass` | Both `nginx` (existing) and the new `${INGRESS_CLASS_NAME}` are listed |
| 4 | `kubectl -n ${NAMESPACE} get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` | Matches `${LB_IP}` |
| 5 | `kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller` | Still `successfully rolled out` — Traefik install did not perturb nginx |
| 6 | Cross-controller smoke test: `curl -H 'Host: <nginx-host>' http://<nginx-lb-ip>/healthz` and `curl -H 'Host: <traefik-host>' http://<traefik-lb-ip>/healthz` | Both return non-error responses |

If any check fails, the operator should:

1. Capture `kubectl -n ${NAMESPACE} describe deploy traefik`
2. Capture `kubectl -n ${NAMESPACE} logs -l app.kubernetes.io/name=traefik --tail=200`
3. Roll back with `helm -n ${NAMESPACE} uninstall traefik` (NEW INSTALL) or
   `helm -n ${NAMESPACE} rollback traefik` (UPGRADE)

---

## When NOT to use this skill

- The cluster already has Traefik **and** nginx coexisting healthily, and
  you only want to bump nginx — use `helm-version-upgrade` instead.
- You want to migrate Ingress resources from nginx to Traefik — that is
  the `nginx-to-traefik` skill (Zeus side).
- You want to replace both with Gateway API — see `gateway-api-migration`.
