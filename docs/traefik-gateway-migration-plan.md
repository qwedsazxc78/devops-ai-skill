# Plan: Retarget `*gateway-migrate` to Traefik + Gateway API (dual-target)

**Status:** Draft — pending review
**Author:** Claude (opus-4.6) for @qwedsazxc78
**Created:** 2026-04-14
**Related:** `skills/gateway-api-migration/SKILL.md` v1.1.0 (current GKE default)

---

## 1. Context & motivation

The `*gateway-migrate` skill currently defaults to emitting
`gatewayClassName: gke-l7-global-external-managed`. This decision was made
when GKE Gateway was the only Gateway API controller target for the
awoo-platform clusters.

**Why retarget:**
- NGINX Ingress is going into maintenance-only mode; the upstream article
  [NGINX Ingress Retirement Analysis](https://sprucets.com/blog/nginx-ingress-retirement-analysis-astro)
  puts the deprecation deadline at **March 2026** — already overdue as of
  this plan's creation date (2026-04-14).
- The article recommends **Gateway API** as the long-term path. It lists
  several conforming controllers (Traefik, HAProxy Ingress, NGINX Inc.
  commercial, Kong, Contour, Cilium, Envoy Gateway) without declaring a
  winner.
- @qwedsazxc78 has selected **Traefik** as the preferred target for
  eye-of-horus-gitops based on Traefik's listed characteristics: modern
  design, auto service discovery, native Let's Encrypt, strong
  visualization UI, and support for both Ingress and Gateway API — well
  matched to "mid-size deployments and rapid onboarding".
- **Preserving GKE support** matters because other awoo platform clusters
  may remain on GKE Gateway, and re-doing GKE work if it's deleted is
  expensive. Hence the dual-target architecture (see §3).

**The article does NOT mandate Traefik.** Traefik is one of several
options. This plan is a design choice, not a compliance item.

---

## 2. Scope decisions

| # | Question | Decision | Status |
|---|---|---|---|
| Q1 | GKE becomes an alternative or gets deleted? | **(a) Dual-target.** Traefik default, GKE retained as opt-in via `--gateway-class gke-l7-*` | ✅ confirmed |
| Q2 | What Traefik GatewayClass name should be the default? | **`traefik`** (standard Helm chart default) | ✅ confirmed |
| Q3 | Default behavior for orphan-host listeners (master declares host but no minion attaches) | **Pending decision:** (a) keep emitting listeners for orphans, or (b) skip orphan-host listeners by default and add `--include-orphan-hosts` flag | ⏸ needs approval |

**My recommendation for Q3: (b).** Skip orphan listeners by default.
Cleaner output, validator WARN goes away, operator can still include
them with `--include-orphan-hosts`. The trade-off is that re-enabling a
service requires re-running the skill (not just adding an HTTPRoute) —
but that's a rare event.

---

## 3. Dual-target architecture

The skill stays **one pipeline** parameterized by a new `--gateway-class`
flag. The flag accepts any GatewayClass name; three internal branches
gate on the value:

```
flag value                          → code path taken
────────────────────────────────────── ──────────────────────────────────
traefik, traefik-*                  → Traefik branch:
                                       CRDs: Middleware, ServersTransport,
                                             TLSOption, TLSStore
                                       Cert kind: Secret (cert-manager)
                                       CORS: 1× Middleware (shared)
                                       Path denylist: 1× Middleware

gke-l7-global-external-managed,     → GKE branch (existing, unchanged):
gke-l7-regional-external-managed,     CRDs: GCPBackendPolicy, HealthCheckPolicy
gke-l7-rilb, gke-l7-*                 Cert kind: Secret or ManagedCertificate
                                       CORS: N× GCPBackendPolicy (per backend)
                                       Path denylist: Cloud Armor (manual)

anything else                       → Vanilla Gateway API only:
                                       No provider-specific policy CRDs
                                       WARN in risk register that policies
                                       were skipped
```

**No code duplication.** Same SKILL.md steps, same scripts, branching
lives in:

- SKILL.md Step 3A Phase A (which policy CRDs to emit)
- SKILL.md Step 0b preflight (which GatewayClass + CRDs to probe)
- `annotation-map.md` rows 3, 5–8, 9c, 10 (target column becomes matrix)

### What Traefik gives us for the "deferred under GKE" items

The validator's deferred items from the first dev migration all become
*tractable* under Traefik because Traefik's extension point is
`Middleware` attached via HTTPRoute `filters[].extensionRef`:

| Deferred item (GKE) | Traefik equivalent | Files emitted |
|---|---|---|
| **CORS → 11× `GCPBackendPolicy`** | **1× `Middleware` kind: headers** with `accessControlAllow*` fields — **shared across all HTTPRoutes** via `extensionRef`. | `common.gateway/overlays/<env>/middleware-cors.yaml` |
| **Path denylists (row 9c) → Cloud Armor** | **1× `Middleware` kind: plugin** pointing at a block-sensitive-paths plugin, OR `Middleware` kind: `redirectRegex` returning 404 for the matching patterns. Attached via `extensionRef` to every HTTPRoute. | `common.gateway/overlays/<env>/middleware-block-paths.yaml` |
| **proxy-\*-timeout (row 10) → `GCPBackendPolicy.timeoutSec`** | **`ServersTransport`** with `forwardingTimeouts.{dialTimeout, responseHeaderTimeout, idleConnTimeout}`. Still lossy same way as GKE — collapses 3 NGINX values into coarser Traefik settings. | Conditional (not present in eye-of-horus-gitops source) |
| **`ManagedCertificate` refs** | **N/A.** Traefik uses Secret-backed TLS only. `networking.gke.io/managed-certificates` becomes drop-info for Traefik targets. | None — reported in §4 of the report. |

**The big win:** under GKE we'd generate **11 GCPBackendPolicy files**
for CORS (one per backend Service). Under Traefik we generate **1
Middleware file** and reference it from every HTTPRoute. Smaller diff,
easier review, single source of truth for CORS policy.

---

## 4. File-level change list

### 4.1 `devops-ai-skill/skills/gateway-api-migration/` — 9 files

| File | Change | Notes |
|---|---|---|
| `SKILL.md` | edit | Add `--gateway-class` flag to "Invocation forms" section. Step 0b reference the parameterized preflight. Step 3A.3 split into "per-target policy generation" subsection with Traefik and GKE branches. No state schema change — `targetGatewayClass` field already exists. |
| `references/annotation-map.md` | edit | Convert "Category / Target" column into two sub-columns: **GKE target** and **Traefik target**. Row 3 Traefik = drop-info. Rows 5–8 Traefik = `Middleware kind: headers`. Row 9c Traefik = `Middleware kind: plugin` or `redirectRegex`. Row 10 Traefik = `ServersTransport`. |
| `references/gke-gateway-notes.md` | keep | Unchanged — canonical reference when `--gateway-class gke-l7-*`. |
| `references/traefik-gateway-notes.md` | **NEW** | ~150 lines. Contents: supported Traefik versions (v3.1+ required for `extensionRef`), CRDs (`middlewares.traefik.io`, `serverstransports.traefik.io`, `tlsoptions.traefik.io`, `tlsstores.traefik.io`), helm install one-liner, cert-manager integration (unchanged from GKE — still Secret-backed), what we do emit vs what we don't, known limitations, link to Traefik Middleware docs. |
| `references/preflight-checks.md` | edit | Check 3 parameterized on `--gateway-class`. Check 4 becomes: "if target is gke-l7-\*: probe `gcpbackendpolicies.networking.gke.io`; if target is traefik\*: probe `middlewares.traefik.io` + `serverstransports.traefik.io` + `tlsoptions.traefik.io`". |
| `scripts/check_cluster_preflight.sh` | edit | Add `--gateway-class <name>` arg (default `traefik`). Check 3 probes the passed class. Check 4 probes the CRD set based on the class prefix. Add `--traefik-version` probe as warning: if Traefik <3.1 detected, WARN about `extensionRef` support. |
| `scripts/validate_generated.py` | edit | Minor: add new check **#12 middleware-coverage**. If source has CORS annotations AND target is Traefik: verify a `Middleware` of kind `headers` exists in generated module AND is referenced by the generated HTTPRoutes via `extensionRef`. If any HTTPRoute is missing the reference → FAIL. Same pattern for path-denylist middleware if row 9c annotations present. |
| `references/runbook-template.md` | edit | Phase 0.2/0.3 branches on target. Traefik install: `helm repo add traefik https://traefik.github.io/charts` + `helm install traefik traefik/traefik -n traefik --create-namespace --set providers.kubernetesGateway.enabled=true --set gateway.enabled=true`. GKE install instructions unchanged. |
| `references/report-template.md` | edit | §6 (Manual Review) and §9 (Risk Register) language: remove hardcoded "Cloud Armor" references; the template reads `state.yaml.header.target_gateway_class` and substitutes the appropriate mitigation language per target. |

### 4.2 `eye-of-horus-gitops` dev migration regeneration

**Branch plan:** `git checkout feat/gateway-api-migration-dev` (branch
still exists with the old GKE commit `bb7aa6d`), then `git reset --hard
main` to drop the GKE commit, then regenerate with Traefik. Final state
is a single clean commit on the feature branch. Main stays untouched.

**Final file tree after regeneration:**

```
common.gateway/
├── base/
│   └── kustomization.yaml            # empty resources[] — placeholder
├── overlays/
│   └── dev/
│       ├── kustomization.yaml        # resources: base, gateway, redirect, middleware-cors, middleware-block-paths
│       ├── gateway.yaml              # gatewayClassName: traefik, 22 listeners (orphans dropped per Q3=b)
│       ├── redirect-httproute.yaml   # unchanged shape from GKE run
│       ├── middleware-cors.yaml      # NEW — Traefik headers Middleware
│       └── middleware-block-paths.yaml # NEW — Traefik redirectRegex Middleware for 9c path denylists
├── argocd/
│   └── dev.yaml                      # ArgoCD Application
└── MIGRATION.md                      # Updated: Traefik helm install

common.service/overlays/dev/
├── argocd-httproute.yaml             # + filters: [{extensionRef: {name: common-cors}}, {extensionRef: {name: block-paths}}]
├── airflow-httproute.yaml            # same pattern
├── grafana-httproute.yaml
├── thanos-httproute.yaml
├── alertmanager-httproute.yaml
├── prometheus-httproute.yaml
├── metabase-httproute.yaml
├── n8n-httproute.yaml
├── qdrant-httproute.yaml
├── thanos-receiver-httproute.yaml
├── uptime-dashboard-httproute.yaml
├── kustomization.yaml                # 11 HTTPRoute entries appended to resources[]
└── (rancher-nginx-ingress.yaml)      # DELETED via git rm — dead file cleanup

docs/reports/gateway-migration/common-ingress/
├── state.yaml                        # targetGatewayClass: traefik
├── report.md                         # §6/§9 rewritten for Traefik; S1 CORS + path-denylist now resolved
├── step4d.json                       # fresh validator output
└── backups/
    └── dev-kustomization.yaml.pre-edit
```

**Listener count change**: 28 → **22** (14 hostnames × 2 minus 6 for the
3 orphan hosts × 2). Q3 dependency.

**Expected validator output after regeneration**:

```json
{
  "overall": "warn",
  "summary": { "pass": 11, "warn": 1, "fail": 0, "checksRun": 12 }
}
```

- 11 pass: all structural + semantic + cross-authority checks
- 1 warn: `dead-file-safety` finds `mlflow-nginx-ingress.yaml` still
  intentionally commented out in source. Not blocking — it's a source
  state the operator wants to keep. Could be further resolved by either
  un-commenting the mlflow patch or `git rm`-ing the file, but that's a
  source-repo decision, not a migration decision.
- 0 fail

---

## 5. Execution sequence — 5 commits across 2 repos

Each commit has a review checkpoint. I do NOT auto-commit; user approves
each one by saying "next" or similar.

| # | Repo | Commit scope | Approval gate |
|---|---|---|---|
| 1 | `devops-ai-skill` | Skill dual-target core: `annotation-map.md` matrix, new `traefik-gateway-notes.md`, `SKILL.md` edit, `preflight-checks.md` parameterization | ⏸ review diff |
| 2 | `devops-ai-skill` | Script changes: `check_cluster_preflight.sh` (Traefik mode + version probe) + `validate_generated.py` (new middleware-coverage check #12) | ⏸ review diff |
| 3 | `devops-ai-skill` | Runbook + report template Traefik branches | ⏸ review diff |
| 4 | `eye-of-horus-gitops feat/gateway-api-migration-dev` | Reset branch to main. Regenerate 17 files + 2 new Middleware files. `git rm rancher`. | ⏸ review diff, run validator |
| 5 | `eye-of-horus-gitops feat/gateway-api-migration-dev` | state.yaml + report.md + step4d.json refresh with real validator output | ⏸ review |

If validator fails at step 4, fix and recommit before step 5.

---

## 6. Risks I've identified

### 6.1 Traefik GatewayClass name varies

The Helm chart defaults to `traefik`, but some installs use
`traefik-external` / `traefik-internal` when running multiple Traefik
instances for different exposure classes. If the target cluster uses a
non-default name, the generated `gatewayClassName` will be wrong and
HTTPRoutes won't attach.

**Mitigation:** `--gateway-class <name>` flag lets you override. Default
is `traefik` per Q2 confirmation.

### 6.2 Traefik v3.1+ required for `extensionRef` to resolve custom CRDs

The Traefik Middleware CRD was introduced much earlier but Gateway API
`extensionRef` filter support for custom CRDs was added in v3.1. If the
target cluster is running Traefik v2.x, `extensionRef` won't work and
we'd need a fallback pattern (annotation-based attachment on Ingress, or
pre-GA middleware chains).

**Mitigation:** Step 0b preflight adds a Traefik version probe. If
Traefik <3.1 → HALT with a clear install/upgrade instruction.

### 6.3 Plugin middleware for path denylist requires cluster-level setup

Traefik plugins are installed at the controller level (in the static
config), not per-resource. If the cluster doesn't have a `blockpath`-style
plugin pre-installed, a plugin-based `Middleware` resource applies but
has no effect.

**Mitigation:** The skill emits **two alternatives** and lets the operator
pick:

1. **Default path:** `Middleware` of kind `redirectRegex` with a
   negative-match pattern that returns 404 for paths matching the
   denylist regex. Works without any cluster-level plugin setup. Limited
   to regex-expressible patterns (fine for the eye-of-horus-gitops
   denylists — they're all regex already).
2. **Advanced path:** `Middleware` of kind `plugin` pointing at a Traefik
   Hub plugin like `blockpath`. Requires the plugin to be installed in
   the cluster's Traefik static config. Emitted as a commented-out
   alternative in the same file.

### 6.4 Dual-target adds complexity to tests

Every change to shared paths (Step 1, Step 2, Step 4, Step 5) now has to
work against both targets. We don't have automated tests for either
target today — validation is end-to-end via `validate_generated.py` + a
real target repo.

**Mitigation:** eye-of-horus-gitops stays the primary test bed for
Traefik. A follow-up could add a synthetic fixture repo for GKE so both
targets have regression coverage.

### 6.5 Rolling back the retarget

If we retarget to Traefik and the operator later wants GKE back, they
just pass `--gateway-class gke-l7-global-external-managed` on the next
`*gateway-migrate` run. Dual-target preserves this flexibility.
Zero cost to undo.

---

## 7. Validation criteria — how we know it's done

### 7.1 Skill side

- All 12 validator checks in the Python script are implemented and documented.
- `bash -n` and `python3 -m py_compile` pass on every changed script.
- `install-global.sh --claude` runs clean and the cache matches the source tree byte-for-byte (path-normalized).
- A manual dry run of Step 0b against a Traefik-enabled cluster successfully probes the GatewayClass and CRDs (needs a real cluster — the current dev machine has none, so this check is deferred until the user runs it).

### 7.2 eye-of-horus-gitops side

- `kustomize build common.gateway/overlays/dev` exits 0.
- `kustomize build common.service/overlays/dev` exits 0.
- `validate_generated.py` exits 0 with overall: `warn` or `pass`.
  - At most 1 expected warn: `dead-file-safety` for the mlflow commented-out patch (source state).
  - All other checks: `pass`.
- `ingress2gateway` second-opinion check passes with our output as a superset of i2g's hosts and backends.
- `main` branch on eye-of-horus-gitops is still at `4da34ef`, untouched.
- `feat/gateway-api-migration-dev` has exactly one commit on top of `4da34ef`, and that commit's diff matches the file tree in §4.2.

### 7.3 What we're NOT validating in this round

- **Cluster deployment** — the generated artifacts are validated offline
  (build + schema + cross-check). A real cluster deploy is a separate
  cutover concern covered by the runbook, not this plan.
- **stg/prd migration** — dev only. Staging and production follow after
  dev validates in the cluster.
- **Second-opinion diff categorisation detail** — the validator counts
  i2g hosts/backends as superset checks; it does NOT classify every
  structural divergence into expected/formatting/needs-review buckets.
  That's deferred to a v1.3 enhancement.

---

## 8. Open questions / approval gates

| # | Question | Status |
|---|---|---|
| Q3 | Orphan-host listener behavior: (a) keep emitting, or (b) skip by default + `--include-orphan-hosts` flag | ⏸ needs answer |
| Plan approval | Does §3-§7 look right overall? Anything missing, anything in scope that shouldn't be, anything out of scope that should be? | ⏸ needs answer |
| Commit sequence | Is the 5-commit breakdown in §5 OK, or do you want fewer/more checkpoints? | ⏸ needs answer |

---

## 9. Execution trigger

Once approved:

1. I re-read this plan, resolve Q3, then begin commit #1 from §5.
2. After each commit I pause and present the diff for approval.
3. If the validator fails at commit #4, I fix and re-commit before proceeding to #5.
4. Final state: 3 commits on `devops-ai-skill` main + 1 commit on `eye-of-horus-gitops feat/gateway-api-migration-dev`. (Commit #5 is a refresh on the same branch as #4 — may merge into one commit depending on diff size.)
