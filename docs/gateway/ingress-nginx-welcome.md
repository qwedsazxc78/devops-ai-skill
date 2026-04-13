# Ingress-NGINX → Gateway API — Welcome

Read this before running `*gateway-migrate`. Community pointers for Ingress-NGINX users migrating
to Gateway API.

## Why Gateway API?

- **Role separation** — the NGINX master/minion split (`common.ingress/` + `common.service/`) maps
  directly onto Gateway API's Gateway/HTTPRoute persona model. See `master-minion-topology.md`.
- **Feature portability** — Ingress extensibility relies on NGINX-specific annotations; Gateway
  API's filters, policies, and CRDs are first-class API surfaces.
- **Native merging** — HTTPRoutes attach to a Gateway listener via `parentRef`; no
  `mergeable-ingress-type: master/minion` annotation gymnastics required.

## Can I run both controllers in parallel?

Yes. Ingress-NGINX and the GKE Gateway controller each get different external LB IPs. You can
deploy the Gateway stack alongside the existing Ingress stack and migrate hostnames one at a time
via DNS. This is exactly the `*gateway-migrate` runbook strategy — after running the skill, see
`../reports/gateway-migration/<module>/report.md` for the per-hostname cutover checklist.

## Tools

The skill uses [ingress2gateway](./ingress2gateway-integration.md) as an upstream conversion tool
for second-opinion cross-checks in Step 4c (Validate). See `ingress2gateway-integration.md` for
install instructions, provider support, and graceful-degradation behaviour when the tool is absent.

## Conformance

GKE Gateway targets the **Standard** conformance channel. Check the
[Gateway API conformance reports](https://gateway-api.sigs.k8s.io/implementations/) before picking
any alternative implementation.

## Community resources

- **Mailing list**: [sig-network-gateway-api](https://groups.google.com/g/kubernetes-sig-network)
- **Slack**: `#sig-network-gateway-api` on [kubernetes.slack.com](https://kubernetes.slack.com)
- **GitHub discussions**: [kubernetes-sigs/gateway-api discussions](https://github.com/kubernetes-sigs/gateway-api/discussions)
