# Gateway API Migration Skill — Design Spec

**Status:** implemented — shipped in v1.7.0 (initial skill); dual-target (Traefik/GKE) extension shipped in v1.8.0; Traefik-source support shipped in v1.11.0; precedence fix shipped in v1.13.0
**Date:** 2026-04-13
**Author:** alexhsieh (via brainstorming session)
**Target agent:** Zeus (GitOps / Kustomize + ArgoCD)
**Target release:** devops-ai-skill v1.7.0

## 1. Overview

A new Zeus skill + pipeline that migrates Kustomize modules using NGINX Ingress
(`networking.k8s.io/v1 Ingress`) to Gateway API resources (`Gateway`,
`HTTPRoute`), targeting GKE Gateway (`gke-l7-global-external-managed`) as the
data plane.

Invoked via `*gateway-migrate`, the pipeline discovers Ingress-using modules in
the active GitOps repo, analyzes their annotations, converts them into new
Gateway API resources, validates the output with `kustomize build` and
(optionally) `ingress2gateway` as a second opinion, and emits a
human-readable migration report plus a machine-readable YAML state file.

### Primary topology: master/minion across two modules

The skill is deliberately scoped around the real patterns found in the
reference GitOps repo (`gitops/sre/eye-of-horus-gitops`), which uses the
classic NGINX `mergeable-ingress-type: master/minion` split across **two
Kustomize modules**:

- **Master module** (`common.ingress/`) — owned by the SRE/cluster-operator
  persona. Declares hostnames, TLS termination, GKE `ManagedCertificate`
  references, `server-snippet` security hardening. Host-only Ingress
  resources with no `http.paths`.
- **Minion modules** (`common.service/overlays/<env>/<svc>-nginx-ingress.yaml`)
  — owned by the application-developer persona. One Ingress per service,
  each with `spec.rules[].http.paths[]` and a single backend Service. No
  TLS section; inherits TLS from the master via nginx merging.

This split maps **cleanly onto Gateway API's personas model**:

- Master Ingress → **`Gateway`** (SRE-owned, listeners per host)
- Each minion Ingress → **`HTTPRoute`** (app-dev-owned, paths + backends)

Migrating *off* `mergeable-ingress-type` is one of the main wins of Gateway
API: the master/minion merging becomes native HTTPRoute attachment via
`parentRef`.

### Fallback topology: standalone Ingress

For modules that use a single Ingress with both hosts and paths (no
master/minion split), the skill falls back to single-module migration: one
`common.gateway/` module containing both the Gateway and its HTTPRoutes.

### Real annotations this skill knows how to handle

From the reference repo's production Ingress resources:

- cert-manager + GKE ManagedCertificate (SSL renewal via cert-manager with
  `cluster-issuer: clouddns-dns01-clusterissuer`)
- NGINX `server-snippet` security hardening (`X-Content-Type-Options`,
  `X-XSS-Protection`, `X-Frame-Options`, Set-Cookie rewrites, path denylists
  for `.env`/`.git`/`.yaml` etc.)
- CORS annotations (`enable-cors`, `cors-allow-origin/methods/headers`)
- `mergeable-ingress-type: master` (obsolete under Gateway API)
- Multi-env overlays (`dev`, `stg`, `prd`) with per-env hostname prefixes
  and per-host ManagedCertificate Secrets

## 2. Goals & Non-Goals

### 2.1 Goals (v1)

1. **End-to-end migration pipeline** — discover, analyze, convert, validate,
   report — not just an advisor.
2. **Master/minion topology as first-class** — detect the NGINX master/minion
   split across two Kustomize modules (master + services), migrate both
   sides in a single run, and produce a Gateway resource in a new
   `common.gateway/` module plus one HTTPRoute per minion co-located next
   to the minion in `common.service/`.
3. **Safe cutover** — never modify the master source (`common.ingress/`).
   For minions, the skill adds new HTTPRoute files alongside existing
   minion Ingress files (never overwrites minions) and performs controlled,
   idempotent in-place edits only to `common.service/overlays/<env>/kustomization.yaml`
   to register the new resources.
4. **Resumable** — persist per-migration state as YAML so failed runs can be
   resumed from the failing step without re-analysis.
5. **Honest about the hard parts** — annotations that cannot be translated
   cleanly are left as explicit `TODO(gateway-migrate)` stubs in the generated
   YAML, with full context in the migration report's Manual Review section.
   No silent drops.
6. **Graceful tool degradation** — optional tools (`kubeconform`,
   `ingress2gateway`) warn and skip when missing; required tools (`kustomize`,
   `yq`) halt with install hints.
7. **Single-target, extensible** — ships one `GatewayClassStrategy`
   implementation (GKE), but the converter is structured so additional
   strategies (NGINX Gateway Fabric, Istio, Envoy Gateway) can be added in v2
   without changing the pipeline.
8. **Fallback to standalone** — for modules that don't use the master/minion
   split, fall back to a single-module migration that produces one
   `common.gateway/` module containing both the Gateway and its HTTPRoutes.

### 2.2 Non-Goals (v1)

The following are explicitly excluded and will fail loudly if requested:

1. Other GatewayClasses beyond GKE (listed as v2 extension points).
2. Using `ingress2gateway` as the authoritative converter — it runs only in
   Step 4c as a second opinion.
3. Batch mode (`--all`) — migrations are one module at a time in v1.
4. Auto-commit or auto-PR generation. The pipeline stops at "here are the
   files to stage and a suggested commit message."
5. Cloud Armor policy generation for `server-snippet` path denies or
   Set-Cookie rewrites. These are stubbed with TODO markers pointing at
   Cloud Armor, not auto-generated.
6. Wildcard listener consolidation. Even when hostnames share a parent
   domain, v1 generates per-hostname listeners. Report flags the
   consolidation opportunity as optional follow-up.
7. Migration of non-`Ingress` resources (Services of type `LoadBalancer`,
   ExternalDNS records, etc.).
8. Integration with other Zeus pipelines. `*gateway-migrate` does not
   auto-trigger `*review` or `*health` on the generated module.

## 3. Architecture

### 3.1 Skill + pipeline split

Follows the existing Zeus pattern: one thick skill holds the authoritative
logic; one thin pipeline wraps it as a checklist of gates.

**Skill package layout (in `devops-ai-skill` repo):**

```
skills/gateway-api-migration/
  SKILL.md                                 # Authoritative skill definition
  references/
    annotation-map.md                      # Translation table (inlined copy of docs/gateway/annotation-map.md)
    gke-gateway-notes.md                   # GKE-specific facts (inlined copy)
    http-routing-guide.md                  # HTTPRoute reference (inlined copy)
    migration-from-ingress.md              # Upstream concepts (inlined copy)
    ingress-nginx-welcome.md               # Upstream welcome (inlined copy)
    ingress2gateway-integration.md         # Second-opinion tool facts (inlined copy)
    master-minion-topology.md              # Detection rules, classification heuristics, cross-namespace notes
    manual-review-patterns.md              # Server-snippet, mergeable-ingress — what to do manually
    runbook-template.md                    # Template copied into generated module's MIGRATION.md
    httproute-template.yaml                # HTTPRoute skeleton per minion

prompts/zeus/
  gateway-migrate.md                       # Thin 8-step pipeline wrapping the skill

docs/gateway/                              # Single source of truth, human-facing
  migrate-from-ingress.md                  # Rewritten from upstream; project header
  ingress-nginx-welcome.md                 # Rewritten; filename typo fixed
  http-routing-guide.md                    # NEW — distilled from gateway-api.sigs.k8s.io/guides/http-routing/
  gke-gateway-notes.md                     # NEW — GatewayClasses, policies, ManagedCertificate
  annotation-map.md                        # NEW — canonical translation table
  ingress2gateway-integration.md           # NEW — upstream tool facts
  master-minion-topology.md                # NEW — how the skill detects master/minion splits
```

**Expected target-repo output (in the GitOps repo the skill runs against):**

```
# Master → Gateway (new module, created from scratch)
common.gateway/
  base/
    kustomization.yaml                     # new
    gateway.yaml                           # new — one Gateway, listeners per host
    gcpbackendpolicy-*.yaml                # new — per-service (if CORS present)
  overlays/{dev,stg,prd}/
    kustomization.yaml                     # new
    gateway.patch.yaml                     # new — per-env hosts and cert refs
  argocd/
    dev.yaml stg.yaml prd.yaml             # new — copied from common.ingress/argocd
  MIGRATION.md                             # new — cutover/rollback runbook

# Minions → HTTPRoutes (added alongside existing minions, side-by-side)
common.service/
  overlays/dev/
    argocd-nginx-ingress.yaml              # UNCHANGED (existing minion)
    argocd-httproute.yaml                  # NEW — HTTPRoute for argocd
    grafana-nginx-ingress.yaml             # UNCHANGED
    grafana-httproute.yaml                 # NEW
    airflow-nginx-ingress.yaml             # UNCHANGED
    airflow-httproute.yaml                 # NEW
    ...
    kustomization.yaml                     # MODIFIED (idempotent) — adds *-httproute.yaml to resources
  overlays/stg/
    ... same pattern
  overlays/prd/
    ... same pattern

# Audit trail
docs/reports/gateway-migration/
  common-ingress/
    state.yaml                             # new — machine state, resumable
    report.md                              # new — human report
```

**Change classes the skill makes to the target repo:**

| Class | Applies to | Safety rule |
|---|---|---|
| Create new files | `common.gateway/**`, `common.service/overlays/<env>/*-httproute.yaml`, `docs/reports/gateway-migration/**` | HALT if target exists without `--force` |
| Modify existing files (in-place edit, idempotent) | `common.service/overlays/<env>/kustomization.yaml` (append `*-httproute.yaml` to `resources:`) | Use `yq` atomic edit; re-running is a no-op if entries already present |
| Never touch | `common.ingress/**`, existing `common.service/overlays/<env>/<svc>-nginx-ingress.yaml` files | Pipeline HALT if any write would land here |

### 3.2 Registration touch-points

Must be updated atomically in the same commit as the skill to keep
`version-consistency` checks green and cross-platform installs coherent:

| File | Change |
|---|---|
| `docs/PROJECT.md` | Add skill row + `*gateway-migrate` pipeline row to Zeus tables |
| `CLAUDE.md` | Add `*gateway-migrate` to Zeus commands table |
| `AGENTS.md` | Same |
| `GEMINI.md` | Same |
| `.gemini/commands/devops/zeus-gateway-migrate.toml` | New Gemini TOML command entry |
| `.claude-plugin/plugin.json` | Version bump 1.6.0 → 1.7.0 |
| `.claude-plugin/marketplace.json` | Version bump |
| `.gemini/extensions/devops/gemini-extension.json` | Version bump |
| `package.json`, `VERSION` | Version bump |
| `scripts/setup/setup-antigravity.sh` | Add `/zeus-gateway-migrate` workflow symlink |

### 3.3 Single-source-of-truth principle

`docs/gateway/annotation-map.md` is canonical. The skill's
`references/annotation-map.md` is either a symlink (preferred, on platforms
where setup scripts create symlinks) or an inlined copy (on platforms where
symlinks are unreliable). The `pnpm version:consistency` check is extended
to verify the two files match.

### 3.4 Delivery Model

`*gateway-migrate` follows the standard Zeus command delivery pattern: the
skill lives in the `devops-ai-skill` package, is installed once per user
(globally via `install-global.sh` or per-repo via `setup.sh`), and is
invoked from within a Zeus session on the *target* GitOps repo. No files
from this skill are copied into the target repo at install time — the
skill operates on `$PWD` via dynamic discovery.

**Intended workflow:**

```bash
cd /path/to/target-gitops-repo       # e.g. gitops/sre/eye-of-horus-gitops
# Zeus activates via repo-detect (Kustomize + ArgoCD indicators)
*gateway-migrate                     # or *gateway-migrate common.ingress
# Skill discovers common.ingress/ in $PWD, generates common.gateway/
# and docs/reports/gateway-migration/ in $PWD, then exits.
git add common.gateway/ docs/reports/gateway-migration/
git commit                           # commit from within target repo
```

This matches how every other Zeus command (`*review`, `*health`,
`*scaffold`, `*pre-merge`) already works. The `devops-ai-skill` plugin is
the delivery mechanism; no target-project install step is required beyond
the one-time `setup.sh` (or globally-installed plugin) on the user's
machine.

**Rationale for not adding a separate "transfer" or "install-in-target"
command:**

1. **Pattern consistency** — every existing Zeus skill operates on `$PWD`.
   A new skill that requires a separate transfer step would break the
   mental model.
2. **No path hardcoding** — per `docs/PROJECT.md`, agents must discover
   directories dynamically. A transfer command would either hardcode a
   target or take a CLI arg, neither of which Zeus commands use today.
3. **No sync problem** — the skill lives in one place (`devops-ai-skill`).
   Updates propagate via `pnpm update -g devops-ai-skill`, not via
   re-transferring files into every target repo.
4. **Output lands where it is committed** — running under Zeus inside the
   target repo means `$PWD` *is* the commit destination. No file copying,
   path translation, or "where did my output go" confusion.
5. **The migration is one-shot, not long-lived runtime code.** Unlike
   pre-commit hooks, CI jobs, or bots (which *do* need to be checked into
   the target repo because they execute without Zeus), `*gateway-migrate`
   is an interactive, human-driven, run-once-and-commit operation. Zeus
   only needs to be present *for the migration run*, not permanently in
   the target's `.git` history.

**What does not need to exist:**
- A `*gateway-migrate-install <target>` or similar transfer command.
- Skill files checked into target repos.
- Hardcoded target paths in the skill.

**What does end up checked in to the target repo after a migration:**
- `common.gateway/` — the generated Kustomize module.
- `common.gateway/MIGRATION.md` — cutover + rollback runbook filled in
  from the skill's template.
- `docs/reports/gateway-migration/<module-slug>/state.yaml` — audit trail.
- `docs/reports/gateway-migration/<module-slug>/report.md` — human report.
- Nothing else from the skill itself.

## 4. Outputs — The Three Artifacts

Every successful migration produces three distinct artifacts. Each has one
job; mixing them was an early temptation to resist.

### 4.1 Machine state — `state.yaml`

Per-module, resumable, committed to git as part of the audit trail.

**Location:** `docs/reports/gateway-migration/<module-slug>/state.yaml`

**Example (abridged):**

```yaml
schemaVersion: 1
topology: master-minion    # or: standalone
module: common.ingress
moduleSlug: common-ingress
targetGatewayClass: gke-l7-global-external-managed
generatedModule: common.gateway
createdAt: 2026-04-13T10:22:00Z
updatedAt: 2026-04-13T10:25:14Z
status: in_progress    # discovering | analyzing | converting | validating | completed | failed | aborted
currentStep: 4
environment:
  tools:
    kustomize: v5.4.2
    yq: v4.44.1
    kubeconform: v0.6.7
    ingress2gateway: v0.3.0
master:
  module: common.ingress
  namespace: ingress-nginx
  files:
    - common.ingress/base/app.ingress.yaml
    - common.ingress/overlays/dev/app.ingress.yaml
    - common.ingress/overlays/stg/app.ingress.yaml
    - common.ingress/overlays/prd/app.ingress.yaml
  hostnamesDeclared:
    dev: 14
    stg: 14
    prd: 12
minions:
  - service: argocd
    module: common.service
    namespace: argocd
    backendService: argocd-server
    backendPort: 80
    pathRules:
      - path: /
        pathType: Prefix
    files:
      dev: common.service/overlays/dev/argocd-nginx-ingress.yaml
      stg: common.service/overlays/stg/argocd-nginx-ingress.yaml
      prd: common.service/overlays/prd/argocd-nginx-ingress.yaml
    hostnames:
      dev: dev-argocd.awoo.org
      stg: stg-argocd.awoo.org
      prd: argocd.awoo.org
  - service: grafana
    module: common.service
    namespace: monitoring
    backendService: grafana
    backendPort: 80
    pathRules:
      - path: /
        pathType: Prefix
    files:
      dev: common.service/overlays/dev/grafana-nginx-ingress.yaml
      stg: common.service/overlays/stg/grafana-nginx-ingress.yaml
      prd: common.service/overlays/prd/grafana-nginx-ingress.yaml
    hostnames:
      dev: dev-grafana.awoo.org
      stg: stg-grafana.awoo.org
      prd: grafana.awoo.org
  # ... (11+ minion entries for eye-of-horus-gitops)
orphanHosts:
  - host: dev-alertmanager.awoo.org
    declaredIn: common.ingress/overlays/dev/app.ingress.yaml
    reason: no minion Ingress found with this host
orphanMinions: []
steps:
  - id: 1
    name: discover
    status: done
    startedAt: 2026-04-13T10:22:00Z
    completedAt: 2026-04-13T10:22:01Z
    findings:
      topologyDetected: master-minion
      masterFiles: 4
      minionCount: 11
      minionFiles: 33
      hostnameCount: 14
      orphanHosts: 2
      orphanMinions: 0
  - id: 2
    name: analyze
    status: done
    annotations:
      portable:
        - key: cert-manager.io/cluster-issuer
          count: 1
          translation: cert-manager Certificate referenced from Gateway listener (unchanged)
        - key: kubernetes.io/ingress.class
          count: 1
          translation: Gateway.spec.gatewayClassName (dropped from resource)
        - key: networking.gke.io/managed-certificates
          count: 4
          translation: listener.tls.certificateRefs[kind=ManagedCertificate]
      convertible:
        - key: nginx.ingress.kubernetes.io/enable-cors
          count: 1
          translation: GCPBackendPolicy.spec.cors
        - key: nginx.ingress.kubernetes.io/cors-allow-origin
          count: 1
          translation: GCPBackendPolicy.spec.cors.allowOrigins
        - key: nginx.ingress.kubernetes.io/cors-allow-methods
          count: 1
          translation: GCPBackendPolicy.spec.cors.allowMethods
        - key: nginx.ingress.kubernetes.io/cors-allow-headers
          count: 1
          translation: GCPBackendPolicy.spec.cors.allowHeaders
      splitCategory:
        - key: nginx.ingress.kubernetes.io/server-snippet
          count: 1
          autoConverted:
            - header: X-Content-Type-Options
              target: HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add
            - header: X-XSS-Protection
              target: HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add
            - header: X-Frame-Options
              target: HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add
          stubbed:
            - directive: 'add_header Set-Cookie "..."'
              reason: legacy add_header Set-Cookie with no cookie name; needs manual review
            - directive: 'location ~ \.(ht|env|...)$ { return 404; }'
              reason: NGINX path denylist; recreate as Cloud Armor security policy
      dropInfo:
        - key: nginx.ingress/mergeable-ingress-type
          count: 1
          reason: obsolete under Gateway API; HTTPRoutes merge natively
  - id: 3
    name: convert
    status: done
    generated:
      # Gateway side (new common.gateway/ module)
      - common.gateway/base/kustomization.yaml
      - common.gateway/base/gateway.yaml
      - common.gateway/overlays/dev/kustomization.yaml
      - common.gateway/overlays/dev/gateway.patch.yaml
      - common.gateway/overlays/stg/kustomization.yaml
      - common.gateway/overlays/stg/gateway.patch.yaml
      - common.gateway/overlays/prd/kustomization.yaml
      - common.gateway/overlays/prd/gateway.patch.yaml
      - common.gateway/argocd/dev.yaml
      - common.gateway/argocd/stg.yaml
      - common.gateway/argocd/prd.yaml
      - common.gateway/MIGRATION.md
      # HTTPRoute side (new files added to existing common.service/ overlays)
      - common.service/overlays/dev/argocd-httproute.yaml
      - common.service/overlays/dev/grafana-httproute.yaml
      - common.service/overlays/dev/airflow-httproute.yaml
      # ... one per minion per env
      - common.service/overlays/stg/argocd-httproute.yaml
      # ...
      - common.service/overlays/prd/argocd-httproute.yaml
      # ...
    modified:
      # In-place idempotent edits to register new HTTPRoute files
      - path: common.service/overlays/dev/kustomization.yaml
        editType: yq-append-resources
        added: [argocd-httproute.yaml, grafana-httproute.yaml, airflow-httproute.yaml, ...]
      - path: common.service/overlays/stg/kustomization.yaml
        editType: yq-append-resources
        added: [argocd-httproute.yaml, grafana-httproute.yaml, ...]
      - path: common.service/overlays/prd/kustomization.yaml
        editType: yq-append-resources
        added: [argocd-httproute.yaml, grafana-httproute.yaml, ...]
    todoStubs: 2
  - id: 4
    name: validate
    status: in_progress
    checks:
      kustomizeBuild:
        dev: pass
        stg: pass
        prd: in_progress
      kubeconform: skipped   # Gateway API CRDs not installed in validation env
      ingress2gatewaySecondOpinion:
        status: ran
        divergences: 2
        summary: our converter emitted GCPBackendPolicy and 3 responseHeaderModifier filters that upstream dropped silently
  - id: 5
    name: report
    status: pending
  - id: 6
    name: runbook
    status: pending
  - id: 7
    name: pre-commit
    status: pending
reportPath: docs/reports/gateway-migration/common-ingress/report.md
```

**Rules:**
- YAML is preferred over JSON for comment support, diff-friendliness, and
  repo consistency.
- On re-run with `--resume`, the skill reads this file and jumps to
  `currentStep`. If `status: completed` without `--force`, the pipeline
  refuses to re-run.
- `status: failed` or `aborted` resumes cleanly. `status: in_progress` means
  a previous run crashed mid-step — the skill will re-execute the current
  step from scratch.
- All writes use an atomic write helper: stage to temp, fsync, rename.

### 4.2 Human report — `report.md`

**Location:** `docs/reports/gateway-migration/<module-slug>/report.md`

Generated from `state.yaml` at Step 5. Follows the structure in
`prompts/shared/report-format.md`.

**Required sections:**

1. **Header** — module, target GatewayClass, date, verdict
   (`PASS` / `COMPLETED WITH MANUAL REVIEW` / `FAIL`)
2. **Summary table** — 8-row table of step results
3. **Annotation Inventory** — portable / convertible / split-category /
   drop-info, rendered from state YAML
4. **Manual Review Required** — for each split-category stub and drop-info
   entry:
   - what the original annotation was doing
   - why GKE Gateway cannot express it cleanly
   - suggested alternatives (app-layer, Cloud Armor, different GatewayClass)
   - exact `file:line` of each occurrence in the source module
5. **Cutover Runbook** — deploy → smoke test → flip ArgoCD → delete old
6. **Rollback Procedure** — one-paragraph "unsync new, re-sync old"
7. **Second Opinion** (only if `ingress2gateway` was available) — normalized
   diff between our converter output and `ingress2gateway print`, with
   explanations for divergences
8. **Consolidation Opportunities** — optional follow-ups the user can take
   post-migration (e.g., wildcard cert to collapse listeners)

### 4.3 Generated artifacts in the target repo

Output is split across two modules to preserve Gateway API's role separation.

**4.3.1 `common.gateway/` — new module, created from scratch**

Side-by-side with `common.ingress/`. Never modifies the master source.
Mirrors the master's `base/` + `overlays/{dev,stg,prd}/` + `argocd/` layout.
Contains the Gateway resource, per-env gateway patches, ArgoCD Applications
pointing at the new module, and `MIGRATION.md` filled from the runbook
template.

Cross-namespace parentRef is enabled at the listener level:

```yaml
# Excerpt of common.gateway/base/gateway.yaml
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: argocd-https
      port: 443
      protocol: HTTPS
      hostname: argocd.awoo.org
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: ingress-nginx
      tls:
        mode: Terminate
        certificateRefs:
          - group: networking.gke.io
            kind: ManagedCertificate
            name: prd-argocd-ingress-nginx-crt
    # ... one listener per hostname
```

**4.3.2 `common.service/` modifications — add HTTPRoutes next to minions**

For each minion Ingress in `common.service/overlays/<env>/<svc>-nginx-ingress.yaml`,
the skill generates a co-located HTTPRoute at
`common.service/overlays/<env>/<svc>-httproute.yaml`. The existing minion
file is left unchanged — both exist side-by-side during cutover.

Each HTTPRoute:

```yaml
# Excerpt of common.service/overlays/dev/argocd-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd        # same namespace as backend Service
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: common-gateway
      namespace: ingress-nginx
      sectionName: argocd-https
  hostnames:
    - dev-argocd.awoo.org
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 80
```

The skill also edits `common.service/overlays/<env>/kustomization.yaml`
in-place to register the new HTTPRoute files in the `resources:` list.
This is the only class of in-place edit the skill performs; rules:

1. **`yq`-atomic**: the edit uses `yq eval -i` with a deterministic
   operator that appends entries to `.resources` without reordering or
   reformatting other fields.
2. **Idempotent**: if the HTTPRoute file is already listed in `resources:`,
   the edit is a no-op. Re-running the skill is safe.
3. **Pre-flight validation**: before the edit, the skill reads the file,
   verifies it parses as YAML, and captures the pre-edit hash into
   `state.yaml` under `steps[3].modified[].preEditHash`.
4. **Post-edit validation**: after the edit, `kustomize build
   common.service/overlays/<env>` must succeed. If it fails, the skill
   reverts the edit from the pre-edit hash snapshot.
5. **Audit**: every in-place edit is recorded in state YAML under
   `steps[3].modified[]` with the `editType: yq-append-resources` marker
   and the list of entries added.

**4.3.3 Required target namespace labeling (post-generation, user-run)**

The generated Gateway uses `allowedRoutes.namespaces.from: Selector` with
label `gateway-access: ingress-nginx`. Before the new HTTPRoutes can
attach, the user must label the target namespaces. The runbook includes
the exact command, discovered from state YAML:

```bash
kubectl label namespace argocd monitoring airflow --overwrite \
  gateway-access=ingress-nginx
```

This is a one-time, user-run step; the skill does not `kubectl` anything.

## 5. Annotation Translation

The canonical translation table (kept in `docs/gateway/annotation-map.md`).
Each row represents a deterministic decision the converter makes every run.

| # | Annotation | Category | GKE Gateway translation | Converter action |
|---|---|---|---|---|
| 1 | `kubernetes.io/ingress.class: nginx` | portable | `Gateway.spec.gatewayClassName: gke-l7-global-external-managed` | drop from resource, set on Gateway |
| 2 | `cert-manager.io/cluster-issuer: <x>` | portable | Preserved on `Certificate` resource referenced by Gateway listener | preserve; emit Certificate CR |
| 3 | `networking.gke.io/managed-certificates: a,b,c` | portable-GKE | Split by comma; each name becomes a `listener.tls.certificateRefs[kind=ManagedCertificate]` entry | one listener per hostname group; keep existing ManagedCertificate resources |
| 4 | `nginx.ingress/mergeable-ingress-type: master` | drop-info | No equivalent needed; HTTPRoutes merge natively | drop with INFO record |
| 5 | `nginx.ingress.kubernetes.io/enable-cors: "true"` | convertible | `GCPBackendPolicy.spec.cors` enabled | emit one GCPBackendPolicy per affected Service |
| 6 | `nginx.ingress.kubernetes.io/cors-allow-origin: "*"` | convertible | `GCPBackendPolicy.spec.cors.allowOrigins: ["*"]` | merge into policy from #5 |
| 7 | `nginx.ingress.kubernetes.io/cors-allow-methods` | convertible | `GCPBackendPolicy.spec.cors.allowMethods: [...]` | split comma-string, normalize |
| 8 | `nginx.ingress.kubernetes.io/cors-allow-headers` | convertible | `GCPBackendPolicy.spec.cors.allowHeaders: [...]` | split comma-string, normalize |
| 9a | `server-snippet` — `X-Content-Type-Options`, `X-XSS-Protection`, `X-Frame-Options` response headers | split-category (auto) | `HTTPRoute.spec.rules[].filters[].responseHeaderModifier.add` | auto-convert; loss-free |
| 9b | `server-snippet` — `add_header Set-Cookie "..."` with no cookie name | split-category (stub) | No direct equivalent; likely legacy bug | TODO stub + Manual Review entry |
| 9c | `server-snippet` — `location ~ .../ { return 404; }` path denylists | split-category (stub) | Cloud Armor security policy territory | TODO stub + Manual Review entry with Cloud Armor pointer |
| 10 | `nginx.org/proxy-{connect,read,send}-timeout` | convertible-lossy | `GCPBackendPolicy.spec.timeoutSec` (single value) | emit `timeoutSec = max(read, send, connect)`, WARN in report |
| 11 | `spec.tls[].hosts` + `spec.tls[].secretName` | portable | One `listener` per hostname group with matching `certificateRefs` | preserve Secret names exactly |
| 12 | `spec.rules[].host` (host-only, no paths) | portable | One HTTPRoute per hostname, single `PathPrefix /` rule, `parentRef` on the hostname's listener | one-to-one mapping |
| 13 | `spec.rules[].http.paths[].backend.service` | portable | `HTTPRoute.spec.rules[].backendRefs[]` with same Service name + port | preserve; HALT if Service not found in module |

**Accepted recommendations on open rows:**

- **Row 9a/b/c split** — auto-convert the three X-* security headers (row 9a),
  stub both the Set-Cookie directives (9b) and the path denylists (9c). The
  runbook explicitly flags the risk that X-* headers might now be duplicated
  if the user also moves them to the app layer.
- **Row 11 listeners** — per-hostname listeners, not wildcard. Report surfaces
  a "Consolidation Opportunity" section pointing at wildcard certs as an
  optional follow-up.

**Trade-offs the report must call out:**

1. A module migrated with TODO stubs can `kustomize build` cleanly but be
   *functionally incomplete*. Validation checks syntax, not semantics.
2. Per-hostname listeners can produce large Gateway resources (your prd
   module has 12 hostnames → up to 24 listeners).
3. CORS is attached to Services via `GCPBackendPolicy`, not to the Gateway or
   the Ingress. An Ingress-level CORS annotation with 8 backends becomes 8
   `GCPBackendPolicy` resources. The report calls this out as a
   "one-to-many" expansion.

## 6. Pipeline Flow — `*gateway-migrate`

### 6.1 Invocation forms

```
*gateway-migrate                         # interactive discovery mode (A)
*gateway-migrate common.ingress          # explicit target module (B)
*gateway-migrate common.ingress --resume # resume from state.yaml
*gateway-migrate common.ingress --force  # bypass never-clobber on target path
```

### 6.2 Step 0 — Tool check

| Tool | Required? | On missing |
|---|---|---|
| `kustomize` | yes | HALT — `brew install kustomize` |
| `yq` | yes | HALT — `brew install yq` |
| `kubeconform` | no | WARN, SKIP 4b — `brew install kubeconform` |
| `ingress2gateway` | no | WARN, SKIP 4c — `brew install ingress2gateway` |

Records versions in `state.yaml` under `environment.tools`.

### 6.3 Step 1 — Discover (topology-aware)

This step detects the topology before doing anything else. The detection
rules live in `references/master-minion-topology.md`.

**Classification rules for every `kind: Ingress` found in the repo:**

| Signal | Classification |
|---|---|
| `metadata.annotations["nginx.ingress/mergeable-ingress-type"] == "master"` | master (strong) |
| `spec.rules[].host` present AND no `spec.rules[].http.paths` anywhere | master (heuristic) |
| `spec.rules[].http.paths[]` present AND no `spec.tls` AND `ingress.class: nginx` | minion |
| `spec.rules[].host` + `spec.rules[].http.paths[]` + `spec.tls` in one resource | standalone |

**Pairing:**

1. For each minion, take its `spec.rules[].host` values.
2. Search all masters for a matching host (case-insensitive, exact match).
3. If a minion's host matches exactly one master → pair them.
4. If a minion's host matches zero masters → orphan minion (HALT).
5. If a minion's host matches multiple masters → ambiguous (HALT).
6. For each master host with no matching minion → orphan host (WARN, proceed).

**Form A (interactive):** Grep repo for `^kind: Ingress`, classify, pair,
present as a migration unit:

```
Discovered migration unit: master/minion topology
  Master:  common.ingress/               (4 files, 14 hostnames declared)
  Minions: common.service/overlays/      (11 services across 3 envs = 33 files)
    ✓ argocd        → dev/stg/prd-argocd.awoo.org     → argocd-server:80
    ✓ grafana       → dev/stg/prd-grafana.awoo.org    → grafana:80
    ✓ airflow       → dev/stg/prd-airflow.awoo.org    → airflow-webserver:8080
    ... (11 services total)
  Orphan hosts:   2  (dev-alertmanager, dev-n8n — declared in master, no minion)
  Orphan minions: 0

Proceed with end-to-end master + minion migration? [y/N]
```

If only standalone Ingresses are found, present the single-module fallback
flow instead.

**Form B (explicit):** `*gateway-migrate common.ingress` — verify the path
is a master module, auto-discover paired minions in sibling modules by
hostname.

**`--resume`:** Load `state.yaml`, find `currentStep`, show "resumed from
step N" banner. Read `topology` field to pick the right flow.

**Gates:**
- HALT if no Ingress found (form A) or path invalid (form B).
- HALT if orphan minions exist (source config is broken).
- HALT if ambiguous master-minion pairings exist.
- WARN on orphan hosts; continue.

### 6.4 Step 2 — Analyze

Read every Ingress manifest in the module. For each:

1. Extract annotations; classify against `annotation-map.md`.
2. Extract `spec.rules[]`, `spec.tls[]`, backend Service refs.
3. Resolve every backend Service — verify `metadata.name` exists as a
   `kind: Service` elsewhere in the module. Missing → WARN and record.
4. Determine listener strategy from TLS entries — per-hostname unless a
   wildcard hostname is found (none expected in v1).

Write full analysis to state YAML `steps[2]` and optionally to
`analysis-raw.yaml` for debugging. Present the summary to the user.

**Gate:** interactive — user must confirm to proceed. HALT on decline.

### 6.5 Step 3 — Convert (two-phase)

Two phases: (A) generate the new `common.gateway/` module, (B) generate
HTTPRoutes in `common.service/` and edit overlay kustomization.yaml files
in-place.

**Pre-flight:**
- Target path `<module-parent>/common.gateway/` must not exist (HALT without
  `--force`).
- For each minion, the destination HTTPRoute path
  `common.service/overlays/<env>/<svc>-httproute.yaml` must not exist
  (HALT without `--force`; with `--force`, overwrite).
- For each `common.service/overlays/<env>/kustomization.yaml`, capture the
  pre-edit file hash into state YAML for rollback.

**Phase 3A — `common.gateway/` generation:**

1. `common.gateway/base/kustomization.yaml` — lists Gateway + any per-service
   GCPBackendPolicy resources.
2. `common.gateway/base/gateway.yaml` — single Gateway resource with one
   listener per master hostname, `allowedRoutes.namespaces.from: Selector`
   with label `gateway-access: ingress-nginx`, and `certificateRefs`
   pointing at the existing ManagedCertificate resources by name.
3. `common.gateway/base/gcpbackendpolicy-<svc>.yaml` — one per backend
   Service that had convertible annotations (CORS, timeouts).
4. `common.gateway/overlays/{dev,stg,prd}/kustomization.yaml` — references
   base, applies per-env gateway patch.
5. `common.gateway/overlays/{dev,stg,prd}/gateway.patch.yaml` — per-env
   hostname list and certRef list, mirroring what the master's overlay
   patches.
6. `common.gateway/argocd/{dev,stg,prd}.yaml` — copied from
   `common.ingress/argocd/*.yaml`, with `path:` rewritten to point at
   `common.gateway/overlays/<env>`. ArgoCD app name gets `-gateway` suffix
   to avoid collision with the master's app.
7. `common.gateway/MIGRATION.md` — filled from `runbook-template.md` with
   this migration's specifics (service list, target namespaces for
   labeling, env-specific host lists).

**Phase 3B — `common.service/` HTTPRoute generation + in-place edits:**

For each minion in the state YAML's `minions` array:

1. Generate `common.service/overlays/<env>/<svc>-httproute.yaml` with:
   - `metadata.namespace` = minion's namespace (Service's namespace)
   - `spec.parentRefs[0]` = cross-namespace ref to Gateway in
     `ingress-nginx` namespace, with `sectionName` = the listener name
     matching this hostname
   - `spec.hostnames` = minion's `spec.rules[].host` list
   - `spec.rules` = translated from minion's `spec.rules[].http.paths[]`
     (PathPrefix from `path` + `pathType`)
   - `spec.rules[].backendRefs[]` = minion's backend Service name + port
   - Response-header filters from master's `server-snippet` X-* headers
     (apply to every HTTPRoute, per the row 9a split)
   - TODO stubs for row 9b/9c server-snippet directives
2. Edit `common.service/overlays/<env>/kustomization.yaml` in place using
   `yq eval -i`:
   ```bash
   yq eval -i '.resources += ["argocd-httproute.yaml"]' kustomization.yaml
   ```
   Idempotent: check if the entry already exists first via
   `yq eval '.resources | contains(["argocd-httproute.yaml"])' kustomization.yaml`.
3. After all edits to an env's kustomization.yaml are complete, run
   `kustomize build common.service/overlays/<env>` to validate. On
   failure, restore the pre-edit hash and HALT.

**Atomicity:**

- Phase 3A writes to a temp `common.gateway.tmp/` then renames to
  `common.gateway/`. If Phase 3A fails, the temp is removed and nothing
  lands in the target repo.
- Phase 3B is per-env: for each env, all file creates + the kustomization
  edit happen in one atomic group. If the post-edit `kustomize build`
  fails, the skill:
  1. Removes the newly created `*-httproute.yaml` files for that env.
  2. Restores `kustomization.yaml` from the pre-edit hash.
  3. HALT with the build error — user can re-run with `--resume`.
- If Phase 3A succeeds but Phase 3B fails at env N, Phase 3A output
  (`common.gateway/`) remains in place for debugging. `--resume` picks up
  at env N.

**TODO stubs** are inlined where applicable as
`# TODO(gateway-migrate): <reason> — see report.md Manual Review #<n>`,
both in HTTPRoutes (for row 9b/9c) and in Gateway listener comments.

**Gate:** HALT on write failure, target-exists-without-force, or in-place
edit validation failure.

### 6.6 Step 4 — Validate

**4a. `kustomize build`** each overlay. Failure → HALT, leave generated
module in place for debugging.

**4b. `kubeconform`** (if installed) against Gateway API CRD schemas. Unknown
CRDs (e.g., `GCPBackendPolicy`) produce WARN not FAIL.

**4c. Second opinion** (if `ingress2gateway` installed):

```bash
ingress2gateway print --providers ingress-nginx \
  --input-file <each source Ingress manifest>
```

Capture upstream output, normalize both (sort keys, strip comments), diff
against our output. Record summary in state YAML; render full diff in
report's Second Opinion section. Divergences never halt — they are
informational.

**Gate:** HALT on 4a failure; WARN on 4b/4c.

### 6.7 Step 5 — Render report

Build `report.md` from `state.yaml`. On write failure, WARN and print to
stdout as fallback.

### 6.8 Step 6 — Runbook & next steps

Print to session and also write to `common.gateway/MIGRATION.md`. The
runbook is structured around a **per-hostname DNS cutover**, not a
big-bang ArgoCD flip, because the master/minion topology makes per-host
cutover safe and gradual.

```
Migration complete: common.ingress → common.gateway (master/minion topology)
  Generated:
    - common.gateway/ (N files)
    - common.service/overlays/{dev,stg,prd}/*-httproute.yaml (M files)
  Modified (idempotent):
    - common.service/overlays/{dev,stg,prd}/kustomization.yaml
  Report:      docs/reports/gateway-migration/common-ingress/report.md
  Manual review items: 2 — see report Section 4

Pre-cutover setup (run once):
  1. Review the manual-review items in the report.
  2. Install Gateway API CRDs in target clusters if not already:
       kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
  3. Install the GKE Gateway controller (if not already installed).
  4. Label target namespaces so HTTPRoutes can attach to the Gateway:
       kubectl label namespace argocd monitoring airflow <...> --overwrite \
         gateway-access=ingress-nginx

Cutover phases:
  Phase 1 — Deploy Gateway (no traffic yet)
    - Sync ArgoCD app: common-gateway-dev → deploys common.gateway/overlays/dev
    - Wait for Gateway to acquire external IP:
        kubectl get gateway common-gateway -n ingress-nginx -o wide
    - Record the new IP. Nothing points at it yet.

  Phase 2 — Deploy HTTPRoutes alongside existing minions
    - Sync the updated common.service/ ArgoCD apps.
    - New *-httproute.yaml files are applied alongside existing minion
      *-nginx-ingress.yaml files. BOTH stacks serve the same hostnames:
        - Old path: DNS → ingress-nginx load balancer → minion Ingress
        - New path: test via new Gateway IP only (no DNS change yet)
    - Verify HTTPRoutes attached successfully:
        kubectl get httproute -A
        kubectl describe httproute argocd-server -n argocd

  Phase 3 — Per-hostname DNS cutover (gradual, reversible)
    For each hostname (start with the lowest-risk one, e.g. a dashboard):
      a. Test the new path directly:
           curl --resolve dev-argocd.awoo.org:443:<new-gateway-ip> \
                https://dev-argocd.awoo.org
      b. Update the DNS A/AAAA record to point at the new Gateway IP.
      c. Wait for DNS TTL + a monitoring soak (15 min minimum).
      d. Check error rates, latency, cert serving.
      e. If healthy, move to next hostname. If not, DNS rollback to
         previous IP — Phase 2 stack is still live.

  Phase 4 — Bake and clean up (after all hostnames stable 1+ week)
    - Unsync + delete common.ingress/ ArgoCD apps.
    - Delete common.ingress/ module from the repo.
    - Remove minion *-nginx-ingress.yaml files from
      common.service/overlays/<env>/ and their entries from kustomization.yaml.

Rollback at any point in Phases 1-3:
  - DNS flip back to the old ingress-nginx LB IP.
  - The old master + minion stack was never removed; it's still serving.
  - If HTTPRoutes misbehave, unsync common.service/ ArgoCD app and they
    detach from the Gateway. Minions keep routing traffic.
  - Common.ingress/ was never modified by the migration; it is exactly
    as the skill found it.

Why per-hostname DNS cutover instead of ArgoCD sync flip:
  - Granularity: flip one service at a time; failures are scoped.
  - Reversibility: DNS change is the only forward step; everything else
    is just "both stacks coexist," which is safe.
  - No big-bang: no moment where you rely on a single sync-order to not
    drop traffic.
```

### 6.9 Step 7 — Pre-commit hints

Suggested commit message (following `commit-rules`):

```
feat(ingress): migrate common.ingress to Gateway API (master/minion)

- Generate common.gateway/ Kustomize module (Gateway + base/dev/stg/prd overlays)
- Add HTTPRoutes to common.service/overlays/{dev,stg,prd}/ for 11 services
- Register new HTTPRoute files in common.service/overlays/*/kustomization.yaml
- Target: gke-l7-global-external-managed
- 11 HTTPRoutes, 14 listeners, 3 responseHeaderModifier filters
- 2 manual review items — see docs/reports/gateway-migration/common-ingress/report.md
- common.ingress/ and common.service/overlays/*/*-nginx-ingress.yaml
  untouched — side-by-side for safe per-hostname DNS cutover
```

Files to stage:
- `common.gateway/**`
- `common.service/overlays/dev/*-httproute.yaml`
- `common.service/overlays/stg/*-httproute.yaml`
- `common.service/overlays/prd/*-httproute.yaml`
- `common.service/overlays/dev/kustomization.yaml` (modified)
- `common.service/overlays/stg/kustomization.yaml` (modified)
- `common.service/overlays/prd/kustomization.yaml` (modified)
- `docs/reports/gateway-migration/<slug>/state.yaml`
- `docs/reports/gateway-migration/<slug>/report.md`

No auto-commit. User drives git.

### 6.10 Halt / resume semantics

| Failure point | State | Resume behavior |
|---|---|---|
| Step 1 discovery fails | no state written | re-run normally |
| Step 2 analyze errors | state exists, step 2 marked error | `--resume` re-runs from step 2 |
| Step 3 write fails | temp dir cleaned, no partial output | re-run normally; target still clean |
| Step 4a build fails | generated module left in place | user fixes; `--resume` re-runs from step 4 |
| Step 4b/4c warn | state records warnings | no halt; continue |
| User aborts step 2 | state `status: aborted` | `--resume` restarts from step 2 |
| Run completes | state `status: completed` | rerun refused unless `--force` |

## 7. `ingress2gateway` Integration

Upstream: [kubernetes-sigs/ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway).
Official Kubernetes SIG project; the recommended tool for mechanical
Ingress → Gateway conversion.

**Install:** `brew install ingress2gateway` or `go install github.com/kubernetes-sigs/ingress2gateway@latest`.

**Providers:** `ingress-nginx`, `gce`, `istio`, `kong`, `apisix`, `openapi`.
Relevant to this project: `ingress-nginx` (current) and `gce` (parallel GKE
Ingress).

**What upstream handles:**
- Mechanical Ingress → Gateway + HTTPRoute structure
- Common Ingress annotations for its supported providers
- Growing but limited annotation coverage

**What upstream does NOT handle (our skill does):**
- GKE-specific `GCPBackendPolicy`, `GCPGatewayPolicy`, `HealthCheckPolicy`
- `ManagedCertificate` listener references
- CORS → `GCPBackendPolicy.cors` transformation
- `server-snippet` parsing and response-header extraction
- TODO stub generation with context
- Migration state tracking and resume

**Integration role:** second-opinion cross-check only. Runs in Step 4c.
Divergences are informational and explain *why* they diverged (we added
GKE-specific resources; upstream dropped annotations we stubbed; etc.).

**Graceful degradation:** if `ingress2gateway` is not on PATH, Step 4c is
skipped with WARN and an install hint. The skill never hard-depends on it.

## 8. Tool Dependencies & Graceful Degradation

Following the project principle: missing optional tools SKIP the check with
install hints; missing required tools HALT.

| Tool | Required | Purpose | Install hint |
|---|---|---|---|
| `kustomize` | yes | build validation | `brew install kustomize` |
| `yq` | yes | state YAML manipulation | `brew install yq` |
| `kubeconform` | no | schema validation | `brew install kubeconform` |
| `ingress2gateway` | no | second-opinion diff | `brew install ingress2gateway` |

The skill records installed tool versions in `state.yaml` at Step 0 so the
report reflects the environment the migration ran in.

`scripts/install-tools.sh` should be extended to add `ingress2gateway` to
the optional tool list.

## 9. Testing Strategy

### 9.1 Structure tests (part of `pnpm test`)

- `skills/gateway-api-migration/SKILL.md` has required YAML frontmatter
  (`name`, `description`, `version`).
- All files referenced from `SKILL.md` under `references/` exist.
- `prompts/zeus/gateway-migrate.md` exists and references the skill.
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `docs/PROJECT.md` all list
  `*gateway-migrate` in Zeus command tables.
- `.gemini/commands/devops/zeus-gateway-migrate.toml` exists, correct format.
- `docs/gateway/annotation-map.md` and
  `skills/gateway-api-migration/references/annotation-map.md` are identical
  (or are a valid symlink pair).

### 9.2 Fixture conversion tests

Directory: `tests/gateway-api-migration/fixtures/`

| Fixture | Topology | Exercises | Assertion |
|---|---|---|---|
| `standalone-simple/` | standalone | minimal Ingress + Service (single resource with host+paths+TLS) | golden `common.gateway/` matches |
| `standalone-cors/` | standalone | rows 5–8 | `GCPBackendPolicy` golden + 1 policy per Service |
| `standalone-server-snippet/` | standalone | row 9a/b/c split | X-* headers in `responseHeaderModifier`, Set-Cookie + path-denies stubbed with `TODO(gateway-migrate)` markers |
| `master-minion-minimal/` | master/minion | detection, pairing, cross-namespace parentRef | topology detected as `master-minion`, one HTTPRoute generated per minion, kustomization.yaml edited idempotently |
| `master-minion-orphan-host/` | master/minion | orphan-host detection | WARN recorded in state, migration proceeds |
| `master-minion-orphan-minion/` | master/minion | orphan-minion error path | HALT at step 1 with clear error |
| `master-minion-ambiguous/` | master/minion | two masters declaring same hostname | HALT at step 1 with ambiguity error |
| `master-minion-idempotent/` | master/minion | `--resume` of already-migrated module | in-place kustomization.yaml edits detected as no-op |
| `mergeable-master/` | master/minion | row 4 drop on master | output lacks `mergeable-ingress-type`; state records drop-info entry |
| `eye-of-horus-sample/` | master/minion | real-world fidelity | trimmed copy of `common.ingress/` + matching minions from `common.service/overlays/` in reference repo; end-to-end conversion including per-env patches and cross-namespace parentRefs |

Driver: `tests/run-gateway-migration-fixtures.sh`. Golden files updated via
`pnpm test:gateway:update`.

### 9.3 Resume tests

- Kill-at-step-3: run partial, verify `state.yaml` has `status: aborted`,
  re-run with `--resume`, assert step 2 is skipped and step 3 proceeds.
- Inject invalid `kustomization.yaml` into fixture → step 4a fails → target
  dir remains → `--resume` picks up at step 4 after fix.

### 9.4 Graceful-degradation tests

- `ingress2gateway` mocked missing → step 4c SKIP, overall step 4 PASS.
- `kustomize` missing → Step 0 HALT with correct install hint.

### 9.5 Out of scope for automated tests

- Live GKE deployment of the generated Gateway.
- `kubeconform` against live Gateway API CRD schema URLs (unstable in CI).
- Cutover runbook execution.

## 10. `docs/gateway/` Rewrite Scope

### 10.1 Files to produce or rewrite

| File | Status | Source | Purpose | Target length |
|---|---|---|---|---|
| `migrate-from-ingress.md` | rewrite | existing | Project-facing concepts + feature mapping | ~300 lines |
| `ingress-nginx-welcome.md` | rewrite (filename typo fix) | existing `welcom-Ingress-NGINX.md` | Community pointers + ingress2gateway | ~50 lines |
| `http-routing-guide.md` | NEW | `gateway-api.sigs.k8s.io/guides/http-routing/` | HTTPRoute reference for converter | ~200 lines |
| `gke-gateway-notes.md` | NEW | GCP docs | GatewayClasses, policies, ManagedCertificate | ~150 lines |
| `annotation-map.md` | NEW | Section 5 of this spec | Canonical translation table | ~250 lines |
| `ingress2gateway-integration.md` | NEW | upstream README | Tool facts, providers, integration role | ~60 lines |

**Delete:** `docs/gateway/welcom-Ingress-NGINX.md` (typo in filename,
replaced by rewrite).

### 10.2 Why rewrite rather than link out

- The skill runs in AI sessions where web fetch may be unavailable. Local
  references are directly citable.
- Tailoring to this project (GKE Gateway, eye-of-horus-gitops patterns)
  makes references actionable, not generic.
- Upstream docs change. A checked-in snapshot is diffable in git history.

## 11. v2 Extension Points

Designed in, not implemented in v1.

1. **`GatewayClassStrategy` interface** — add new strategies (NGINX Gateway
   Fabric, Istio, Envoy Gateway) by implementing `generateGateway`,
   `generateListener`, `translateAnnotation`, `backendPolicyKind`. State
   YAML's `targetGatewayClass` field already parameterizes selection.
2. **`AnnotationTranslator` registry** — third-party annotations register
   via files dropped into `references/annotation-map.d/`. v2 loader reads
   the directory.
3. **`--batch` flag** — walks all Ingress-using modules, produces one state
   file per module and a consolidated summary. Only invocation layer
   changes.
4. **`--dry-run` flag** — runs steps 1–4 without writing files; prints what
   would be generated. Useful for CI preview.
5. **Auto-MR/PR opening** — optional post-step using `gitlab-cli` or `gh`
   to push a branch and open an MR/PR pre-filled with the report.

## 12. Considerations & Risks

**Documented risks and the mitigations baked into the design:**

1. **Silent semantic loss.** The skill's validation is syntactic
   (`kustomize build` passes). A module migrated with TODO stubs can be
   functionally incomplete — for example, if `server-snippet` path denies
   are stubbed, the new module is less secure than the old one until the
   user builds an equivalent Cloud Armor policy.
   **Mitigation:** report's Manual Review section is mandatory and loud;
   verdict escalates to `COMPLETED WITH MANUAL REVIEW REQUIRED` whenever
   any stubs exist; suggested commit message surfaces the count.

2. **Listener explosion.** Per-hostname listeners scale linearly with
   hostname count. A 12-hostname module produces a 24-listener Gateway.
   **Mitigation:** Consolidation Opportunities section in report; v2
   extension for wildcard consolidation.

3. **CORS one-to-many.** One Ingress-level CORS annotation expands into N
   `GCPBackendPolicy` resources, one per backend Service.
   **Mitigation:** analyzer summary shows the expansion count; report
   explains why.

4. **GKE lock-in.** v1 only generates GKE Gateway resources. A team that
   later moves off GCP has to re-do the migration.
   **Mitigation:** `GatewayClassStrategy` interface designed in from day
   one; v2 can add NGINX Gateway Fabric without touching the pipeline.

5. **Upstream drift.** `ingress2gateway` may change its CLI interface or
   output format; our diff normalization may go stale.
   **Mitigation:** second-opinion step is optional and soft-failing. Pin a
   known-good version in the install hint.

6. **State file staleness.** If a user manually edits `common.gateway/`
   after the migration but before committing, the state file no longer
   reflects reality.
   **Mitigation:** state file captures the migration *event*, not the
   ongoing state. Resume semantics only apply within a single migration
   run. After commit, the state file is historical audit.

7. **Two parallel ingress paths during cutover.** Both `common.ingress/`
   and `common.gateway/` exist at once. ArgoCD may reconcile both unless
   the user is careful with `Application` sync policies.
   **Mitigation:** runbook is explicit about syncing one and unsyncing
   the other; rollback procedure is symmetric.

8. **In-place kustomization.yaml edits are a new Zeus skill capability.**
   `*gateway-migrate` is the first skill to modify existing files, not
   just create new ones. A buggy `yq` edit could corrupt a kustomization
   file and break every overlay in `common.service/`.
   **Mitigation:** pre-edit hash captured in state YAML before every
   edit; post-edit `kustomize build` must succeed or the edit is reverted
   from the hash; edits are `yq eval -i` atomic (not text-based); edits
   are idempotent so re-runs are safe; audit trail in state YAML records
   every modification.

9. **Cross-namespace parentRef depends on namespace labels the skill
   cannot apply.** The generated Gateway uses `allowedRoutes.namespaces.from:
   Selector` with label `gateway-access: ingress-nginx`. HTTPRoutes only
   attach if the target namespaces are labeled, and the skill does not
   `kubectl` anything — the user must label namespaces manually.
   **Mitigation:** runbook surfaces the exact `kubectl label` command
   with every target namespace filled in from state YAML; a
   "Pre-cutover setup" section makes it the first post-migration step;
   the report's Manual Review section lists the labeling as a required
   task if it hasn't been done.

10. **Master/minion detection heuristics can misclassify.** The rules in
    Section 6.3 use annotation + shape signals. A non-standard Ingress
    that happens to match the "host-only" shape could be misclassified as
    a master.
    **Mitigation:** the annotation signal
    (`mergeable-ingress-type: master`) is authoritative when present; the
    shape heuristic is only used as a fallback; Step 2 analyze shows the
    full classification to the user at the Proceed gate so any
    misclassification is caught before file generation starts.

11. **HTTPRoute namespace mismatch.** Each HTTPRoute lives in the
    backend Service's namespace (e.g., `argocd`), which is also where
    the skill writes the file. But the minion's namespace isn't always
    explicitly set in the minion Ingress — sometimes inherited from
    overlay kustomization.yaml.
    **Mitigation:** Step 2 analyze resolves each minion's effective
    namespace by reading the overlay's kustomization.yaml and any
    `namespace:` field, records it in state YAML; HALT if ambiguous.

12. **DNS-based cutover depends on TTL discipline.** If the user's DNS
    has long TTLs (hours), rollback during Phase 3 could leave clients
    on stale IPs.
    **Mitigation:** runbook explicitly recommends shortening DNS TTLs to
    60-300s *before* beginning Phase 3, and waiting for propagation
    before each hostname flip. This is a runbook instruction, not
    something the skill can enforce.

## 13. Open Items

None. All decisions locked via brainstorming session on 2026-04-13:

- Scope: C (full pipeline, not just advisor)
- Target: GKE Gateway (A), with v2 extension interface
- Cutover: side-by-side, never clobber master, never overwrite minions
- Annotation handling: best-effort + TODO stubs + Manual Review report (B)
- Invocation: interactive discovery (A) + module-path shortcut (B)
- `ingress2gateway`: optional, graceful-degradation, second-opinion only
- Row 9 split: auto-convert X-* headers, stub Set-Cookie + path denies
- Row 11 TLS: per-hostname listeners, flag wildcard consolidation in report
- Output: YAML state file + markdown report + generated module +
  HTTPRoutes in common.service/
- Step 3 clobber: HALT unless `--force`
- Reference to `kubernetes-sigs/ingress2gateway`: integrated into design
- **Topology:** master/minion as first-class; standalone as fallback
- **HTTPRoute placement:** Option A — next to the minion in
  `common.service/overlays/<env>/`, preserving Gateway API's role
  separation. Skill edits `common.service/overlays/<env>/kustomization.yaml`
  in-place (the first Zeus skill to do in-place edits)
- **Cross-namespace routing:** `allowedRoutes.namespaces.from: Selector`
  with label `gateway-access: ingress-nginx`; user labels target
  namespaces via runbook instructions
- **Cutover strategy:** per-hostname DNS flip, not big-bang ArgoCD sync
- **Delivery model:** Zeus agent command; no separate transfer/install
  step for target repos (Section 3.4)

## 14. Next Steps

1. Commit this spec.
2. Hand off to `superpowers:writing-plans` skill to produce a step-by-step
   implementation plan with checkpoints.
3. Execute plan via `superpowers:executing-plans` with review checkpoints.
4. Release as v1.7.0 following the standard release workflow.
