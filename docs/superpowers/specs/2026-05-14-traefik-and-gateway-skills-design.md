# Traefik + Gateway API Migration Skills — Design Spec

**Status:** implemented — v1.11.0 (2026-05-18)
**Date:** 2026-05-14
**Owner:** Awoo Platform Team
**Repos affected:** `devops-ai-skill` (plugin), `eye-of-horus-gitops` (consumer)

## 1. Problem and motivation

Two migration workflows exist in disconnected forms:

- `eye-of-horus-gitops/.claude/commands/gitops/nginx-to-traefik.md` — a slash command that ports services from NGINX Ingress to Traefik Ingress using a parallel-run / DNS-cutover safety model. Tightly coupled to that repo's layout (`archive/` dir, `dns-create-traefik.sh`, `verify-traefik-<env>.sh`, batched `app.ingress.yaml`).
- `devops-ai-skill/skills/gateway-api-migration/` — a generic SKILL.md that converts NGINX Ingress to Gateway API (Traefik or GKE GatewayClass). Master/minion topology aware, validates with `ingress2gateway` second opinion.

Operators today choose between class-swap (stay on Ingress API, change controller) and resource-swap (move to Gateway API). They sometimes want to do both — first move off NGINX onto Traefik Ingress for stability, then later move to Gateway API. There is no skill that handles the chained workflow, and the class-swap skill only exists as a repo-bound slash command.

This spec adds two skills and enhances one existing skill so that all three workflows are first-class and composable.

## 2. Goals

- Promote the `nginx-to-traefik` slash command into a reusable SKILL.md with eye-of-horus-gitops conventions baked in as defaults.
- Enhance the existing `gateway-api-migration` skill to accept `ingressClassName: traefik` as input (in addition to nginx), enabling chained workflows.
- Add a thin orchestrator skill that runs both phases against the same module in one operator session, producing a single combined index document.
- Keep all three skills independently invocable and independently testable.

## 3. Non-goals

- No new GatewayClass targets beyond Traefik and GKE Gateway (no `istio`, `cilium`, etc.).
- No automated DNS cutover or cluster-side apply. DNS is operator-controlled, per the existing safety model.
- No state-schema-breaking change to the existing skill. Field additions are additive on v2.
- No performance or scale work.

## 4. Architecture

Three skills, three Zeus pipelines. Skill C owns no conversion logic — it invokes A and B as subroutines.

> **Note on naming:** The diagram below shows the **final (v2.0.0+) state**. In v1.11.0 the existing skill keeps its current name `gateway-api-migration` (directory, pipeline, trigger, and report dir all unchanged) and only gains the four enhancements. The rename to `ingress-to-gateway` ships in v2.0.0. See Section 8 for the release split.

```
devops-ai-skill/
├── skills/
│   ├── nginx-to-traefik/          ← NEW (skill A)
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   ├── nginx-to-traefik-env-config.md
│   │   │   ├── annotation-translation.md
│   │   │   └── dns-cutover-runbook.md
│   │   └── scripts/
│   │       ├── inventory_nginx_ingresses.py
│   │       ├── generate_traefik_ingress.py
│   │       ├── update_kustomization.py
│   │       └── validate_cross_consistency.sh
│   │
│   ├── ingress-to-gateway/        ← RENAMED from gateway-api-migration (in v2.0.0)
│   │   ├── SKILL.md               (existing logic + enhancements 1–4)
│   │   ├── references/
│   │   └── scripts/
│   │
│   └── nginx-to-gateway/          ← NEW (skill C — thin orchestrator)
│       ├── SKILL.md
│       └── references/
│           └── chain-report-template.md
│
└── prompts/zeus/
    ├── nginx-to-traefik.md
    ├── ingress-to-gateway.md      (was gateway-migrate.md)
    └── nginx-to-gateway.md
```

State and report directory convention:

| Skill | Run directory |
|---|---|
| A | `docs/reports/nginx-to-traefik/<slug>/` |
| B | `docs/reports/ingress-to-gateway/<slug>/` (was `gateway-migration/<slug>/`) |
| C | `docs/reports/nginx-to-gateway/<slug>/` (links to both sub-reports) |

The slash command at `eye-of-horus-gitops/.claude/commands/gitops/nginx-to-traefik.md` is deleted; its keywords are covered by the new SKILL.md's auto-trigger description.

## 5. Skill A — `nginx-to-traefik`

### 5.1 Invocation

```
*nginx-to-traefik                              # interactive: inventory + propose batches
*nginx-to-traefik <env>                        # process all services in one env
*nginx-to-traefik <env> <batch>                # named batch (b1 | b2)
*nginx-to-traefik <env> <service>              # single service
*nginx-to-traefik --resume                     # continue from state.yaml
```

### 5.2 Step flow

| Step | Action | Script |
|---|---|---|
| 0 | Tool check (`kustomize`, `yq`, `git`) | inline `command -v` |
| 0b | Load `references/nginx-to-traefik-env-config.md`; **prompt operator for Traefik + nginx LB IPs if missing**, write to config, then continue | inline |
| 1 | Inventory active nginx ingresses per env | `inventory_nginx_ingresses.py` |
| 2 | Propose batch plan, wait for `y/N` confirmation | inline |
| 3 | Generate `<service>-traefik-ingress.yaml` per service | `generate_traefik_ingress.py` |
| 4 | `git mv` nginx file to `archive/` | inline |
| 5 | Edit `kustomization.yaml`: add Traefik file to `resources:`, drop nginx from `patches:` | `update_kustomization.py` |
| 6 | Update `common.traefik/overlays/<env>/app.ingress.yaml` managed-cert host list | `update_kustomization.py` |
| 7 | `kustomize build` both modules for the env | inline |
| 7b | 4-way consistency check (DNS script ↔ verify script ↔ service Traefik Ingress ↔ managed-cert hosts) | `validate_cross_consistency.sh` |
| 8 | Update `scripts/dns-create-traefik.sh` batch list | inline |
| 9 | Update `scripts/verify-traefik-<env>.sh` URL list | inline |
| 10 | Print commit message + file list (never auto-commit) | inline |

### 5.3 Invariants (carried from the existing slash command)

- nginx files go to `archive/`, never deleted.
- DNS A-record is the only cutover lever — no LB IP changes, no nginx Ingress deletions.
- Traefik Ingresses go in `kustomization.resources:`, never `patches:`.
- `secretName` and `backend.service.name` are written full (Kustomize `namePrefix` does not touch them).
- Backend Service must be confirmed before generating a Traefik Ingress; no placeholder backends.
- **Operator-declared LB IPs only.** IPs come from the operator's keyboard via the env-config file. Never derived from `common.ingress/overlays/<env>/app.service.yaml` or `common.traefik/overlays/<env>/app.service.yaml`.

### 5.4 State YAML records

- env-config snapshot (IPs the operator declared, with timestamp)
- inventoried hosts, batch plan
- per-service generation results with SHA256
- pre-edit backups of `kustomization.yaml` and `app.ingress.yaml`
- `kustomize build` results
- 4-way cross-check verdict
- **`outputs.traefikIngresses[]`** — list of `{file, host, namespace, backend, port}` for every generated Traefik Ingress. Skill C reads this list as its hand-off contract.

## 6. Skill B — `ingress-to-gateway` (enhanced)

### 6.1 Rename (v2.0.0)

| Item | Change |
|---|---|
| Directory | `skills/gateway-api-migration/` → `skills/ingress-to-gateway/` (git mv) |
| Frontmatter `name:` | `gateway-api-migration` → `ingress-to-gateway` |
| Zeus pipeline | `prompts/zeus/gateway-migrate.md` → `prompts/zeus/ingress-to-gateway.md` |
| Trigger | `*gateway-migrate` → `*ingress-to-gateway` |
| Report dir | `docs/reports/gateway-migration/` → `docs/reports/ingress-to-gateway/` |

### 6.2 Enhancement 1 — Accept Traefik Ingress as input

`scripts/classify_ingress.py`:
- Currently buckets as `master | minion | standalone | foreign | unknown`. `foreign` = `ingressClassName != nginx`.
- New: recognize `ingressClassName: traefik` as a first-class source class.
- New classification field: `sourceClass: nginx | traefik`.

`scripts/pair_minions.py`: no change — pairing is class-agnostic (host/path/backend-driven).

`references/annotation-map.md`: add Traefik annotation section:

| Traefik annotation | Gateway API equivalent | Notes |
|---|---|---|
| `router.middlewares: cors@kubernetescrd` | `HTTPRoute.filters[].extensionRef` → Middleware | Same Middleware reused, no regeneration |
| `router.middlewares: security-headers@kubernetescrd` | `HTTPRoute.filters[].extensionRef` → Middleware | Same |
| `router.tls.options: default@kubernetescrd` | listener-level TLSOption reference | Promoted to Gateway listener |
| `router.entrypoints: websecure` | implicit (HTTPS listener on 443) | Dropped, redundant in Gateway API |

When source is already Traefik, **reuse existing Middlewares in the `traefik` namespace** instead of regenerating.

### 6.3 Enhancement 2 — Source-class handoff for skill C

- New flag: `--source-class nginx | traefik` (default `nginx`).
- New flag: `--source-state <path>` (optional, set by skill C; points at A's state.yaml so B can record cross-references in its risk register).
- State additions (additive on v2): `inputs.sourceClass`, `inputs.sourceMiddlewareReuse[]`, `inputs.sourceStatePath`.
- No schema bump.

### 6.4 Enhancement 3 — `--no-redirect` flag

- New flag: `--no-redirect` skips emitting the `tls-redirect` HTTPRoute.
- Rationale: when source is Traefik, the EntryPoint config in `app.values.yaml` already handles HTTP→HTTPS. A redundant HTTPRoute would conflict.
- Default-on behavior unchanged for standalone use.

### 6.5 Enhancement 4 — New semantic checks

Added to `scripts/validate_generated.py`:

| # | Check | Trigger | Severity |
|---|---|---|---|
| 12 | `traefik-middleware-coverage` | Every `router.middlewares` reference on a source Traefik Ingress resolves to an `extensionRef` filter on the matching HTTPRoute | fail |
| 13 | `no-redundant-tls-redirect` | When `inputs.sourceClass == traefik` AND a `tls-redirect` HTTPRoute was emitted, fail (operator forgot `--no-redirect`) | warn |

## 7. Skill C — `nginx-to-gateway`

### 7.1 Size and scope

- SKILL.md target: ~200 lines.
- Owns no conversion logic. Invokes A and B as subroutines.

### 7.2 Invocation

```
*nginx-to-gateway                                  # interactive
*nginx-to-gateway <env>                            # full env, both phases
*nginx-to-gateway <env> --gateway-class traefik    # default
*nginx-to-gateway <env> --gateway-class gke-l7-global-external-managed
*nginx-to-gateway <env> --resume
*nginx-to-gateway <env> --skip-a                   # phase A already done
*nginx-to-gateway <env> --skip-b                   # only do phase A
```

### 7.3 Step flow

| Step | Action | Halt condition |
|---|---|---|
| C.0 | Merged tool check (A's Step 0 ∪ B's Step 0) | any required tool missing |
| C.1 | Create chain run-dir `docs/reports/nginx-to-gateway/<slug>/` with `index.yaml` | dir exists without `--force` |
| C.2 | Invoke skill A as a subroutine (writes its own state.yaml + report) | A's HALT |
| C.3 | Read A's `outputs.traefikIngresses[]`; record A's state path in chain `index.yaml.phaseA` | A produced zero outputs |
| C.4 | Invoke skill B with `--source-class traefik --no-redirect --gateway-class <chosen> --source-state <A's state.yaml>` | B's HALT |
| C.5 | Render combined `index.md` from `references/chain-report-template.md` | informational |

### 7.4 Chain state file (`index.yaml`)

```yaml
schemaVersion: 1
skillVersion: "1.0.0"
chainId: <ulid>
env: dev
gatewayClass: traefik
createdAt: <iso>
phaseA:
  status: completed | failed | skipped
  statePath: docs/reports/nginx-to-traefik/<slug-a>/state.yaml
  reportPath: docs/reports/nginx-to-traefik/<slug-a>/report.md
phaseB:
  status: completed | failed | skipped | blocked
  statePath: docs/reports/ingress-to-gateway/<slug-b>/state.yaml
  reportPath: docs/reports/ingress-to-gateway/<slug-b>/report.md
verdict: PASS | COMPLETED WITH MANUAL REVIEW | FAIL
```

### 7.5 Failure semantics

- A halts → C halts immediately; B is not invoked; `phaseB.status: blocked`.
- B halts after A completed → A's outputs intact; resume runs B only (`--skip-a`).
- C halts after B completed but before rendering index → resume re-runs C.5 only.

### 7.6 What C does NOT do

- No DNS scripts. No cluster apply. No auto-commit.
- No state merging — each sub-skill owns its own state file.
- No re-validation of A's outputs — B's classifier reads them fresh.

### 7.7 Combined runbook (`index.md` Cutover section)

1. Review A's report and its generated Traefik Ingress files.
2. Commit phase-A artifacts. ArgoCD reconciles → Traefik Ingresses live alongside nginx.
3. Run `verify-traefik-<env>.sh` to confirm Traefik serves traffic via `--resolve`.
4. Run `dns-create-traefik.sh <env>-b1 --force` to flip DNS to Traefik LB.
5. Run `verify-traefik-<env>.sh <env>-b1 --post-cutover`.
6. Soak period (operator-defined; suggested 24h+).
7. Review B's report. Commit phase-B artifacts. ArgoCD reconciles → Gateway + HTTPRoutes live.
8. Per-host: update DNS for that host to point at the new Gateway address (per B's existing runbook).
9. Bake, then archive or delete the Traefik Ingress files (now superseded by HTTPRoutes).

## 8. Release plan

Two releases, separating "add features" from "break names":

**v1.11.0 (this release):**
- Add `nginx-to-traefik` skill (skill A).
- Add `nginx-to-gateway` skill (skill C).
- Enhance `gateway-api-migration` skill with `--source-class`, `--no-redirect`, checks 12 + 13 — keep the existing name.

**v2.0.0 (next release):**
- Rename `gateway-api-migration` → `ingress-to-gateway` (directory + frontmatter + pipeline + trigger + report dir).
- Replace `prompts/zeus/gateway-migrate.md` with a 5-line stub that prints a deprecation note and forwards args to `*ingress-to-gateway`.

**Release after v2.0.0:**
- Remove the stub.
- Drop "formerly `gateway-api-migration`" line from SKILL.md description.

### 8.1 Files needing identifier updates (mechanical)

- `.claude-plugin/plugin.json` skill list
- `.claude-plugin/marketplace.json`
- `.gemini/extensions/devops/gemini-extension.json`
- `.gemini/commands/devops/*-gateway-migrate*.toml`
- `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` Zeus command tables
- `docs/PROJECT.md` skill inventory
- `README.md` en/zh-TW/zh-CN
- `VERSION`

### 8.2 eye-of-horus-gitops side-effects

- Delete `.claude/commands/gitops/nginx-to-traefik.md`.
- Add a one-line note to that repo's `CLAUDE.md` pointing at the plugin skill.
- Create `eye-of-horus-gitops/references/nginx-to-traefik-env-config.md` with the repo-specific defaults (LB IPs, cert patterns, batch contents) extracted from the deleted command.
- `scripts/dns-create-traefik.sh` and `scripts/verify-traefik-<env>.sh` stay in eye-of-horus-gitops unchanged; skill A invokes them via path, doesn't bundle copies.

## 9. Testing

Three levels, scaled to risk. No CI integration — operator runs tests on demand.

### 9.1 Level 1 — Structure tests (extend `pnpm test`)

| Test | Covers |
|---|---|
| `skills/nginx-to-traefik/SKILL.md` has valid frontmatter (`name`, `description`, `version`) | A registration |
| `skills/ingress-to-gateway/SKILL.md` exists with v2+ state schema reference | B rename |
| `skills/nginx-to-gateway/SKILL.md` exists and references A and B by current name | C registration |
| Each new `prompts/zeus/*.md` exists and references the matching skill name | Pipeline wiring |
| Plugin manifests list all three skills | Plugin discovery |
| README skill table includes all three skills in en + zh-TW + zh-CN | Docs sync |
| Version files match `VERSION` (existing `version:consistency`) | Release readiness |

### 9.2 Level 2 — Script unit tests (`tests/skills/<skill>/`)

**Skill A:**
- `inventory_nginx_ingresses.py` against a fixture with 3 services, one already on Traefik → returns only the 2 nginx ones.
- `generate_traefik_ingress.py` against fixtures with (a) Prefix path, (b) ImplementationSpecific path, (c) cert-manager DNS-01 annotation, (d) annotation that should NOT translate (drop with WARN).
- `update_kustomization.py` idempotency: run twice on same input → second run is a no-op.
- `validate_cross_consistency.sh` against a fixture with a stale DNS entry → exits non-zero, message names the stale host.

**Skill B (only new paths):**
- `classify_ingress.py` against a fixture with `ingressClassName: traefik` → `sourceClass: traefik`, not `foreign`.
- `validate_generated.py` check 12 fires when a Traefik source has `router.middlewares: cors@kubernetescrd` but the emitted HTTPRoute has no matching `extensionRef`.
- `validate_generated.py` check 13 fires when source is Traefik AND a `tls-redirect` HTTPRoute is also emitted.

**Skill C:**
- Chain dry-run on a synthetic 2-service env: invokes A's mock, then B's mock, produces complete `index.yaml` + `index.md`.
- Failure injection: A halts → `phaseB.status: blocked`, B never invoked.
- Resume after B-only failure: re-runs only B; A's outputs untouched.

### 9.3 Level 3 — End-to-end smoke test (manual, `docs/testing/`)

Against a copy of `eye-of-horus-gitops/common.service/overlays/dev/`:
1. `*nginx-to-traefik dev b1` → Traefik Ingress files generated, nginx archived, kustomization edited, DNS script updated. `kustomize build` succeeds.
2. `*ingress-to-gateway common.ingress --source-class traefik --no-redirect --gateway-class traefik` → Gateway + HTTPRoutes generated against A's output.
3. `*nginx-to-gateway dev` (fresh checkout) → chain runs both phases, single `index.md` links both reports.

E2E does not run DNS scripts or apply to a cluster — it only verifies the artifacts.

### 9.4 Regression guard for rename (v2.0.0)

- Test that asserts `*gateway-migrate` stub forwards to `*ingress-to-gateway` in v1.11.x.
- Test that asserts the stub is absent in v2.0.0.

## 10. Open follow-ups

- Decide whether eye-of-horus-gitops's `references/nginx-to-traefik-env-config.md` should be tracked in git or generated locally (current command treats it as tracked).
- After v2.0.0, evaluate whether `*gateway-migrate` deprecation logs should send a one-time telemetry signal (not in scope here).
