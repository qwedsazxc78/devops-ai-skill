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

## Step 3 — Convert (two-phase)

Conversion is split into **Phase 3A** (create new `common.gateway/` module)
and **Phase 3B** (create HTTPRoutes alongside minions + in-place edit
kustomization.yaml).

**Pre-flight:**

1. Check target path `<master-parent>/common.gateway/`:
   - If exists without `--force` → HALT: "Target already present; use
     `--resume` or `--force`."
   - If exists with `--force` → continue (existing content will be
     overwritten).
2. For each minion, check destination `common.service/overlays/<env>/<svc>-httproute.yaml`:
   - If exists without `--force` → HALT.
   - If exists with `--force` → overwrite.
3. For each `common.service/overlays/<env>/kustomization.yaml` that will
   be modified, capture the pre-edit SHA256 hash and record in state YAML
   under `steps[3].modified[].preEditHash`.

### Phase 3A — Generate `common.gateway/`

Atomic: write everything to `common.gateway.tmp/` first, then rename to
`common.gateway/`. On any failure, remove the temp directory.

1. `common.gateway/base/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: ingress-nginx
   resources:
     - gateway.yaml
     # - gcpbackendpolicy-<svc>.yaml (one per service with CORS)
   ```
2. `common.gateway/base/gateway.yaml`:
   - One `Gateway` resource, `gatewayClassName: gke-l7-global-external-managed`
   - One listener per master hostname
   - Each listener: `allowedRoutes.namespaces.from: Selector`,
     `selector.matchLabels.gateway-access: ingress-nginx`
   - TLS listeners reference the ManagedCertificate name from the master's
     TLS entries via `certificateRefs[kind: ManagedCertificate, name: <name>]`
   - HTTP listeners (port 80) included for HTTP→HTTPS redirect
3. `common.gateway/base/gcpbackendpolicy-<svc>.yaml` (only if Row 5–8
   annotations were present):
   - `apiVersion: networking.gke.io/v1`
   - `kind: GCPBackendPolicy`
   - `spec.targetRef` → the backend Service
   - `spec.cors` populated from CORS annotations
4. `common.gateway/overlays/{dev,stg,prd}/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: ingress-nginx
   resources:
     - ../../base
   patches:
     - path: gateway.patch.yaml
   ```
5. `common.gateway/overlays/<env>/gateway.patch.yaml`:
   - Per-env listeners with the environment's hostnames and
     ManagedCertificate refs
6. `common.gateway/argocd/{dev,stg,prd}.yaml`:
   - Copy `common.ingress/argocd/<env>.yaml`
   - Change `metadata.name` from `<name>` to `<name>-gateway`
   - Change `spec.source.path` from `common.ingress/overlays/<env>` to
     `common.gateway/overlays/<env>`
7. `common.gateway/MIGRATION.md`:
   - Copy `references/runbook-template.md`
   - Substitute variables: `{{master_module}}`, `{{generated_module}}`,
     `{{target_namespaces}}`, `{{hostnames_per_env}}`, `{{service_list}}`

Record each generated file in `state.yaml` under `steps[3].generated[]`.

### Phase 3B — Generate HTTPRoutes + edit kustomization.yaml

For each `(env, service)` tuple from the state's `minions[]`:

1. Read `references/httproute-template.yaml`, substitute variables:
   - `{{service}}` → minion's service name
   - `{{namespace}}` → minion's effective namespace
   - `{{hostname}}` → minion's declared host for this env
   - `{{listener_name}}` → Gateway listener name matching this hostname
   - `{{path_rules}}` → translated from minion's `spec.rules[].http.paths[]`
   - `{{backend_name}}` → minion's backend Service name
   - `{{backend_port}}` → minion's backend Service port
   - `{{response_header_filters}}` → X-* headers from master's server-snippet
2. Write to `common.service/overlays/<env>/<service>-httproute.yaml`.
3. Edit `common.service/overlays/<env>/kustomization.yaml` in place:
   ```bash
   # Check idempotency first
   if ! yq eval ".resources | contains([\"<svc>-httproute.yaml\"])" \
        "common.service/overlays/<env>/kustomization.yaml" | grep -q true; then
     yq eval -i ".resources += [\"<svc>-httproute.yaml\"]" \
        "common.service/overlays/<env>/kustomization.yaml"
   fi
   ```
4. After all edits for this env are complete, validate:
   ```bash
   kustomize build common.service/overlays/<env>
   ```
5. On build failure:
   - Restore `kustomization.yaml` from the pre-edit SHA256 snapshot
     captured in pre-flight.
   - Remove all newly created `*-httproute.yaml` files for this env.
   - HALT: "In-place edit validation failed. Target repo reverted to
     pre-edit state. Error: <kustomize output>. Fix and re-run with
     `--resume`."

Record each modification in `state.yaml` under `steps[3].modified[]`.

**TODO stubs:** insert inline in generated YAML as:

```yaml
# TODO(gateway-migrate): <reason> — see report.md Manual Review #<n>
```

Apply to:
- Gateway listener comments when `server-snippet` has stubbed directives
- HTTPRoute comments when the minion's backend relies on a stubbed feature

**Atomicity:**

- Phase 3A uses a temp directory (`common.gateway.tmp/`) — failure before
  rename leaves no partial state in the target location.
- Phase 3B treats each env as an atomic group: all HTTPRoutes for an env
  are written before the kustomization edit; rollback removes all of
  them together.
- `--resume` skips any `(env, service)` tuple already recorded as
  complete in `state.yaml`.

**Gate:** HALT on any write failure, target-exists-without-force, or
in-place edit validation failure.

## Step 4 — Validate

### 4a. Kustomize build (required)

For each generated overlay in `common.gateway/` and for each modified
overlay in `common.service/`:

```bash
kustomize build common.gateway/overlays/dev
kustomize build common.gateway/overlays/stg
kustomize build common.gateway/overlays/prd
kustomize build common.service/overlays/dev
kustomize build common.service/overlays/stg
kustomize build common.service/overlays/prd
```

Record each result in `state.yaml` under `steps[4].checks.kustomizeBuild`.

On failure → HALT. Leave generated files in place for user debugging.
User can fix and re-run with `--resume`.

### 4b. Kubeconform (optional)

Only if `kubeconform` was detected in Step 0. Run against the generated
output with Gateway API CRD schemas:

```bash
kustomize build common.gateway/overlays/prd | \
  kubeconform -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/{{.ResourceKind}}_{{.Group}}_{{.KindLowerSuffix}}.json' \
    -ignore-missing-schemas
```

GKE-specific resources (`GCPBackendPolicy`, `ManagedCertificate`) won't
have public schemas — use `-ignore-missing-schemas`. Warnings are WARN
not FAIL.

### 4c. Second-opinion diff (optional)

Only if `ingress2gateway` was detected. For each master Ingress manifest:

```bash
ingress2gateway print --providers ingress-nginx \
  --input-file common.ingress/overlays/prd/app.ingress.yaml \
  > /tmp/i2g-output-prd.yaml
```

Normalize both outputs (sort map keys alphabetically, strip comments,
normalize list order by `metadata.name`) and compute a line-level diff
against the skill's generated `common.gateway/` equivalent. Record in
`state.yaml`:

```yaml
  - id: 4
    name: validate
    checks:
      ingress2gatewaySecondOpinion:
        status: ran
        divergences: <count>
        summary: <one-line>
        details: <full diff written to docs/reports/gateway-migration/<slug>/second-opinion.diff>
```

Divergences are informational only — never halt.

**Gate:** HALT on 4a failure; WARN on 4b/4c.

## Step 5 — Render report

Generate `docs/reports/gateway-migration/<module-slug>/report.md` from
`state.yaml`. Follow `prompts/shared/report-format.md`. Required sections:

1. **Header** — module, target GatewayClass, date, verdict
   (`PASS` / `COMPLETED WITH MANUAL REVIEW REQUIRED` / `FAIL`)
2. **Summary table** — 8-row table of step results
3. **Topology** — master/minion (or standalone), counts, orphan list
4. **Annotation Inventory** — portable / convertible / split-category /
   drop-info from state YAML
5. **Manual Review Required** — for each split-category stub and
   drop-info entry: what it was, why no direct translation, suggested
   alternative, exact `file:line` of occurrences
6. **Cutover Runbook** — per-hostname DNS phases (copy from
   `references/runbook-template.md` with variable substitution)
7. **Rollback Procedure** — DNS-flip back; both stacks coexist until
   Phase 4 cleanup
8. **Second Opinion** — only if Step 4c ran; normalized diff + explanation
9. **Consolidation Opportunities** — optional follow-ups (wildcard cert,
   etc.)

Verdict escalation rules:
- Any `splitCategory.stubbed` entries → `COMPLETED WITH MANUAL REVIEW REQUIRED`
- Any Step 4a failure → `FAIL`
- Otherwise → `PASS`

On write failure, WARN and print the report to stdout as fallback.
