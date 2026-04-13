# GKE Gateway — Notes for *gateway-migrate

This file captures GKE-specific facts the `*gateway-migrate` skill must know when generating
Gateway API resources that target `gke-l7-*` GatewayClasses. It is a reference for skill
authors and reviewers, not end-user documentation. All generated manifests must align with
the constraints and behaviors described here.

## GatewayClasses

GKE ships several GatewayClass names. The skill must emit the correct `spec.gatewayClassName`
based on the target load balancer type. When the source Ingress has no class annotation (or
uses `nginx`), the skill defaults to `gke-l7-global-external-managed`.

| Name | Scope | Description |
|---|---|---|
| `gke-l7-global-external-managed` | Global | External HTTP(S) Load Balancer — **default target for *gateway-migrate** |
| `gke-l7-regional-external-managed` | Regional | Regional external HTTP(S) LB |
| `gke-l7-rilb` | Regional | Internal HTTP(S) LB (private backends) |
| `gke-l7-gxlb` | — | **Deprecated** — do not use |

Do not emit `gke-l7-gxlb` under any circumstances. If detected in an existing manifest,
flag it as an error and replace with `gke-l7-global-external-managed` in the generated output.

## Policies (GKE extensions)

GKE extends Gateway API with policy resources that attach to existing resources via
`spec.targetRef`. The skill must be aware of these when migrating Ingress annotations that
have no standard Gateway API equivalent. Policies are emitted as separate YAML documents —
they must never be inlined into the Gateway or HTTPRoute spec.

- `GCPBackendPolicy` — CORS, IAP, Cloud Armor, timeouts, session affinity.
  `targetRef` points at a Service (not a Route). One policy per Service is the recommended
  pattern; merge multiple concerns into a single `GCPBackendPolicy` per Service.
- `GCPGatewayPolicy` — SSL policies, region. `targetRef` points at the Gateway resource.
  Used to attach a named SSL policy or pin the Gateway to a specific GCP region.
- `HealthCheckPolicy` — backend health check configuration. `targetRef` points at a Service.
  Replaces NGINX upstream health check annotations and `nginx.ingress.kubernetes.io/healthz-*`
  annotations.
- All policies use the "Policy attachment" pattern: the Policy references the target resource
  via `spec.targetRef`; the target resource never references the Policy. This is important —
  do not add policy references to the Gateway or HTTPRoute manifests.

## ManagedCertificate integration

GKE's `networking.gke.io/v1 ManagedCertificate` resources are referenced from Gateway
listeners via `certificateRefs[kind: ManagedCertificate]`. The Gateway controller resolves
them against the same namespace as the Gateway.

- Provisioning time: 15–60 minutes after DNS validation of the listed domains. The skill must
  emit a comment in the generated Gateway manifest reminding operators of this delay.
- The skill **preserves existing ManagedCertificate resources** — it does not create new ones.
  The master Ingress's `networking.gke.io/managed-certificates` annotation value maps directly
  to listener `certificateRefs` entries. Example mapping:

  ```
  # Ingress annotation
  networking.gke.io/managed-certificates: "my-cert,other-cert"

  # Becomes Gateway listener certificateRefs
  certificateRefs:
    - kind: ManagedCertificate
      name: my-cert
    - kind: ManagedCertificate
      name: other-cert
  ```

- If the annotation lists multiple certificates, the skill emits one `certificateRef` entry
  per certificate name, preserving the original order.
- ManagedCertificate resources are namespace-scoped in GKE. Ensure the certificate and the
  Gateway share the same namespace.

## cert-manager coexistence

cert-manager can issue `Certificate` resources that create Secrets, referenced from Gateway
listeners via `certificateRefs[kind: Secret]`. The Secret name matches the `Certificate`
resource's `spec.secretName` field.

- The eye-of-horus-gitops reference repo uses cert-manager + GKE ManagedCertificate
  **in parallel** — some hosts have cert-manager certs, others have ManagedCertificate.
  The skill preserves both, emitting the correct `certificateRef` kind per host.
- `cert-manager.io/cluster-issuer` annotations on the master Ingress are preserved on the
  emitted `Certificate` resource. The annotation is moved from the Ingress to the
  `Certificate.metadata.annotations` field.
- The skill does not attempt to reconcile or consolidate cert-manager and ManagedCertificate
  domains. Each host retains whichever certificate type was originally configured.
- If a host has neither a ManagedCertificate nor a cert-manager Certificate reference, the
  skill emits a TODO comment on the listener's `certificateRefs` field and continues.

## Required CRDs

Gateway API standard channel must be installed before Gateway resources can be applied.
Install using the official manifest:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```

GKE-specific CRDs (`GCPBackendPolicy`, `HealthCheckPolicy`, `GCPGatewayPolicy`, etc.) are
provisioned automatically by the GKE Gateway controller add-on. Enable the add-on on the
cluster before running `*gateway-migrate`. Without this add-on, applying the generated
manifests will fail with "no matches for kind" errors.

Check that CRDs are installed:

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected output includes at minimum:
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`

For GKE policy CRDs, verify separately:

```bash
kubectl get crd | grep networking.gke.io
```

## Known limitations for v1

- **Per-hostname listeners scale linearly.** A 12-hostname module produces a 24-listener
  Gateway (one HTTP + one HTTPS per host). Wildcard consolidation is a v2 feature. Operators
  managing modules with more than 20 hostnames should be warned about the listener count
  before applying.
- **No auto-generated Cloud Armor policies.** `server-snippet` path denylists (row 9c in
  `annotation-map.md`) get TODO stubs pointing at Cloud Armor — the skill does not generate
  `GCPBackendPolicy.spec.securityPolicy` rules. Manual configuration of Cloud Armor security
  policies is required after migration.
- **Single GatewayClass.** v1 targets `gke-l7-global-external-managed` only. Other GKE
  GatewayClasses require a v2 `GatewayClassStrategy` implementation. If the source Ingress
  targets an internal or regional load balancer, the skill emits a warning comment and still
  generates `gke-l7-global-external-managed` — the operator must update this manually.
