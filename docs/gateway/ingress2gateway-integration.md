# ingress2gateway Integration

The `*gateway-migrate` skill uses [kubernetes-sigs/ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway)
as an optional second-opinion cross-check in Step 4c (Validate). It is not a hard dependency — the skill
runs correctly without it, and Step 4a (`kustomize build`) remains the authoritative validation gate.

## Install

```bash
# macOS
brew install ingress2gateway

# Cross-platform (requires Go 1.21+)
go install github.com/kubernetes-sigs/ingress2gateway@latest

# Verify
ingress2gateway version
```

## Providers

Supported providers: `ingress-nginx`, `gce`, `istio`, `kong`, `apisix`, `openapi`.

**Relevant to this project: `ingress-nginx` (current) and `gce` (parallel GKE Ingress).**

## What upstream handles

- Mechanical Ingress → Gateway + HTTPRoute structure
- Common Ingress annotations for its supported providers
- Growing but limited annotation coverage (check upstream README for the current matrix)

## What our skill does that upstream does not

- GKE-specific `GCPBackendPolicy`, `GCPGatewayPolicy`, `HealthCheckPolicy`
- `ManagedCertificate` listener references
- CORS → `GCPBackendPolicy.cors` transformation
- `server-snippet` parsing and response-header extraction (row 9a)
- TODO stub generation with context
- Migration state tracking and resume
- Master/minion topology detection across two Kustomize modules

## How the skill invokes it

Step 4c runs the following command and diffs the output against the skill's generated resources:

```bash
ingress2gateway print --providers ingress-nginx \
  --input-file common.ingress/overlays/prd/app.ingress.yaml
```

## Diff normalization rules

Before comparing the skill's output against ingress2gateway's output, the skill normalizes both sides:

- Sort map keys alphabetically
- Strip comments
- Normalize list order by `metadata.name`
- Ignore `metadata.annotations` differences that are purely formatting (whitespace, key order)

## Graceful degradation

If `ingress2gateway` is not found on `PATH`, Step 4c is skipped with a `WARN` and an install hint is
surfaced to the user (pointing at the `brew install` / `go install` options above). The skill never
hard-depends on the tool. Step 4a (`kustomize build`) remains the authoritative validation pass and
is always executed regardless of whether ingress2gateway is available.
