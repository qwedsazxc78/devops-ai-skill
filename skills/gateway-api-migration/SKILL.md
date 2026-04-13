---
name: gateway-api-migration
description: >
  Migrates Kustomize modules using NGINX Ingress to Gateway API resources,
  targeting GKE Gateway (gke-l7-global-external-managed). Handles master/minion
  topology (common.ingress/ + common.service/) as the primary case, with
  standalone Ingress as a fallback. Generates a side-by-side common.gateway/
  module, HTTPRoutes alongside existing minions, a resumable YAML state file,
  and a human migration report. Never modifies the master source; performs
  idempotent in-place edits only to common.service/overlays/<env>/kustomization.yaml.
version: "1.0.0"
---

# Gateway API Migration Skill

Invoked by Zeus pipeline `*gateway-migrate`. Canonical references:
- `references/annotation-map.md` — translation table
- `references/master-minion-topology.md` — topology detection rules
- `references/gke-gateway-notes.md` — GKE-specific resource facts
- `references/http-routing-guide.md` — HTTPRoute structure reference
- `references/ingress2gateway-integration.md` — second-opinion tool contract

## Activation

Triggered explicitly by `*gateway-migrate` from Zeus. Not auto-triggered.

## Invocation forms

```
*gateway-migrate                         # interactive discovery mode
*gateway-migrate <module-path>           # explicit target
*gateway-migrate <module-path> --resume  # resume from state.yaml
*gateway-migrate <module-path> --force   # bypass never-clobber on target
```

## Artifacts produced

Every successful run writes three things to the target repo:

1. A new `common.gateway/` Kustomize module (master → Gateway)
2. `common.service/overlays/<env>/*-httproute.yaml` files + an idempotent
   edit to `common.service/overlays/<env>/kustomization.yaml` (minions → HTTPRoutes)
3. `docs/reports/gateway-migration/<module-slug>/state.yaml` + `report.md`

## Step 0 — Tool check

Before any discovery, verify tool availability. Use `command -v` to probe.

| Tool | Required | On missing |
|---|---|---|
| `kustomize` | yes | HALT with `brew install kustomize` |
| `yq` | yes | HALT with `brew install yq` |
| `kubeconform` | no | WARN, SKIP Step 4b with `brew install kubeconform` |
| `ingress2gateway` | no | WARN, SKIP Step 4c with `brew install ingress2gateway` |

Record each tool's version in `state.yaml` under `environment.tools`:

```bash
kustomize version --short
yq --version
kubeconform -v 2>&1 | head -1
ingress2gateway version 2>&1 | head -1
```

If any required tool is missing, halt and print:

```
[HALT] Required tool missing: <tool>
Install: brew install <tool>
Re-run *gateway-migrate after install.
```

## Step 1 — Discover (topology-aware)

Classification rules (reproduced here for agent in-context use; full
rationale in `references/master-minion-topology.md`):

For each `kind: Ingress` manifest found in the repo:

| Signal | Classification |
|---|---|
| `metadata.annotations["nginx.ingress/mergeable-ingress-type"] == "master"` | **master** (authoritative) |
| `spec.rules[].host` present AND no `http.paths` anywhere | **master** (heuristic fallback) |
| `spec.rules[].http.paths[]` present AND no `spec.tls` AND `ingress.class: nginx` | **minion** |
| `spec.rules[].host` + `spec.rules[].http.paths[]` + `spec.tls` in one resource | **standalone** |

**Discovery algorithm:**

1. `Grep` the repo for `^kind: Ingress` and collect all matching files.
2. For each file, read the manifest and apply classification rules above.
3. Group masters by module (nearest ancestor containing `base/` + `overlays/`).
4. Group minions by module, then by service name (derived from filename:
   `argocd-nginx-ingress.yaml` → `argocd`).
5. For each minion, extract `spec.rules[0].host` and search all masters for
   a matching declared host (exact match, case-insensitive).
6. Pair each minion with its master:
   - 1 match → pair.
   - 0 matches → record as orphan minion, HALT at end of discovery.
   - 2+ matches → record as ambiguous, HALT.
7. For each master host with no matching minion → record as orphan host
   (WARN, proceed).

**Interactive form (no args or `--interactive`):** print a numbered list
of detected migration units with hostname counts; user picks one.

**Explicit form (`*gateway-migrate <path>`):** treat `<path>` as the
master module path. Verify at least one Ingress exists inside. Auto-pair
minions from sibling modules.

**`--resume` form:** load `state.yaml`, read `currentStep` and `topology`,
jump to the matching step with a "resumed from step N" banner.

**Gates:**
- HALT if no Ingress found (interactive) or the path has no Ingress (explicit).
- HALT if `--resume` is set but no `state.yaml` exists.
- HALT on orphan minions (source config is broken).
- HALT on ambiguous pairings.
- WARN on orphan hosts; continue.

Write the discovered topology to `state.yaml` under `topology`, `master`,
`minions`, `orphanHosts`, `orphanMinions` fields. See the state YAML schema
example in the spec (§4.1).

## Step 2 — Analyze

For each Ingress manifest found in Step 1 (masters and minions), perform
annotation classification and structural extraction.

**For each master manifest:**

1. Extract annotations. For each annotation, look up its entry in
   `references/annotation-map.md` and classify into one of: `portable`,
   `portable-GKE`, `convertible`, `convertible-lossy`, `split-category
   (auto)`, `split-category (stub)`, `drop-info`.
2. Extract `spec.rules[].host` (the declared host list, no paths expected
   on masters).
3. Extract `spec.tls[]` — map each entry to `(hosts, secretName,
   managedCertificateName)`. The secretName corresponds to a Secret or
   ManagedCertificate resource name.
4. Parse any `server-snippet` annotation content per rows 9a/b/c:
   - **9a (auto)**: extract `add_header X-Content-Type-Options`,
     `add_header X-XSS-Protection`, `add_header X-Frame-Options` — record
     as auto-convert entries with their exact values.
   - **9b (stub)**: match `add_header Set-Cookie "..."` lines — record
     verbatim as stubbed directives.
   - **9c (stub)**: match `location ~ ... { ... return 404; }` blocks —
     record verbatim as stubbed directives with line numbers.

**For each minion manifest:**

1. Extract annotations. Usually just `kubernetes.io/ingress.class: nginx`
   which is drop/portable.
2. Extract `spec.rules[].host` (single host expected; record if multiple).
3. Extract `spec.rules[].http.paths[]` → list of `(path, pathType,
   backend.service.name, backend.service.port)`.
4. Resolve the minion's effective namespace:
   - Check `metadata.namespace` on the Ingress resource.
   - If absent, read the overlay's `kustomization.yaml` for a top-level
     `namespace:` field.
   - If still absent, HALT: "cannot determine namespace for minion
     `<file>`; migration requires explicit namespace."
5. Verify the referenced backend Service exists. Search the repo for
   `kind: Service` manifests matching the name. If missing → record WARN,
   proceed (Service might come from a Helm chart or another module).

**Write analysis to state YAML** under `steps[2]`:

```yaml
  - id: 2
    name: analyze
    status: done
    annotations:
      portable: [...]
      convertible: [...]
      splitCategory: [...]
      dropInfo: [...]
```

**Present the summary to the user** (terminal output):

```
Module: common.ingress → common.gateway (master/minion topology)

Master:   common.ingress/ (4 files)
  Hostnames declared:       14
  Annotation categories:
    portable:                3
    portable-GKE:            4  (ManagedCertificate refs)
    convertible:             4  (→ GCPBackendPolicy resources)
    split-category (auto):   3  (X-* headers → responseHeaderModifier)
    split-category (stub):   2  (Set-Cookie, path denylists)
    drop-info:               1  (mergeable-ingress-type)

Minions:  common.service/ (11 services × 3 envs = 33 files)
  All backend Services resolved: yes
  Orphan minions:              0
  Orphan hosts:                2  (will be listed in report)

Proceed with conversion? [y/N]
```

**Gate:** interactive — user must confirm. HALT on decline.
