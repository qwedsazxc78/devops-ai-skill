# Ingress Migration Advisor Skill — Design Spec

**Status:** ready-for-implementation (TODOs resolved 2026-05-19)
**Date:** 2026-05-19
**Owner:** Awoo Platform Team
**Repos affected:** `devops-ai-skill` (plugin)
**Related:** [2026-05-14-traefik-and-gateway-skills-design.md](2026-05-14-traefik-and-gateway-skills-design.md)

## 1. Problem and motivation

The NGINX Ingress Controller (`ingress-nginx`) upstream project is scheduled to
reach end-of-life in late 2025. Awoo platforms running on `ingress-nginx` must
plan a coordinated migration off it. Three migration skills exist today:

- `nginx-to-traefik` — class-swap (NGINX Ingress → Traefik Ingress)
- `gateway-api-migration` — resource-swap (Ingress → Gateway API; `--source-class nginx|traefik`)
- `nginx-to-gateway` — orchestrator that chains the two phases

They each describe **how** to migrate one batch. None of them answer the
question operators actually face when looking at a repo with 30+ Ingress
resources across 3 envs:

> *Given an EOL deadline, which services do I migrate first, which path do I
> use per service, and how do I batch the work to fit the calendar?*

Today operators answer this with spreadsheets and tribal knowledge. This skill
formalizes that decision as a **read-only, recommendation-only** planner that
reads the repo, scores each service, picks a migration path per service, and
emits a phased plan with ready-to-paste Zeus commands for each batch.

## 2. Goals

- Inventory every Ingress in the repo (nginx, traefik, foreign) across all envs.
- Score each service on a fixed set of migration-readiness dimensions.
- Recommend one of four paths per service: `direct-gateway`, `two-step`,
  `swap-only`, `defer`.
- Group recommended migrations into batches with an explicit deadline schedule.
- Emit a single `plan.md` and a machine-readable `state.yaml` that operators
  can re-read to drive subsequent runs of A/B/C skills.
- Stay **read-only**: no file mutation, no `kustomize build` side-effects, no
  git operations, no DNS edits.

## 3. Non-goals

- No new conversion logic — every recommended action maps to an existing skill.
- No cluster-side queries (the planner runs offline against the repo).
- No automated execution of the recommended commands — operator runs each
  batch through Zeus manually.
- No tracking of in-flight migrations — that lives in the per-batch state files
  written by skills A/B/C.
- No re-running A/B/C scripts in dry-run mode; their classifiers may be reused
  read-only but their conversion paths are out of scope.

## 4. Architecture

The advisor sits **upstream** of the three existing skills. It does not
invoke them — it produces recommendations, and the operator runs each
recommended skill on the suggested batch.

```
devops-ai-skill/
├── skills/
│   ├── ingress-migration-advisor/   ← NEW
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   ├── scoring-model.md     ← TODO: operator-defined weights
│   │   │   ├── decision-matrix.md   ← TODO: path tier thresholds
│   │   │   └── plan-template.md     ← Mermaid Gantt + per-service rows
│   │   └── scripts/
│   │       ├── inventory_all_ingresses.py
│   │       ├── score_services.py
│   │       └── render_plan.py
│   ├── nginx-to-traefik/            ← existing, unchanged
│   ├── gateway-api-migration/       ← existing, unchanged
│   └── nginx-to-gateway/            ← existing, unchanged
│
└── prompts/zeus/
    └── ingress-migration-advisor.md ← NEW
```

**Reuse**: `inventory_all_ingresses.py` reuses
`gateway-api-migration/scripts/classify_ingress.py` as a library (imported,
not shelled out) to avoid re-implementing the classifier. The scoring and
decision logic is new.

**Report directory**: `docs/reports/ingress-migration-advisor/<slug>/` where
`<slug>` is `<isodate>-<ulid>`. Each invocation produces a fresh report —
plans are point-in-time snapshots.

## 5. Invocation

Activated explicitly by Zeus pipeline `*ingress-migration-advisor`.
Auto-triggered also by keywords from `description:` (EOL, migration plan,
ingress-nginx, end-of-life).

```
*ingress-migration-advisor                          # interactive — prompts for deadline + tier metadata
*ingress-migration-advisor --deadline 2025-10-31    # explicit deadline (ISO date)
*ingress-migration-advisor --deadline 2025-10-31 --target-path two-step
*ingress-migration-advisor --no-cluster             # confirm read-only (default; flag is explicit no-op)
*ingress-migration-advisor --resume <state-path>    # re-render plan from existing state without re-scoring
```

`--target-path` overrides per-service path decisions; useful when an org
decides to standardize on a single migration path regardless of risk. Valid
values: `direct-gateway`, `two-step`, `swap-only`.

## 6. Step flow

| Step | Action | Script |
|---|---|---|
| 0 | Tool check (`kustomize`, `yq`, `git`, `python3`) | inline `command -v` |
| 0b | Prompt operator for: EOL deadline, traffic-tier map (file or inline), batch-size cap | inline |
| 1 | Inventory all Ingresses across all `common.*/overlays/*` (reuse `classify_ingress.py`) | `inventory_all_ingresses.py` |
| 2 | Score each service on the five dimensions (see §7) | `score_services.py` |
| 3 | Map total score → path tier → recommended command (see §8) | inline |
| 4 | Batch services by env + deadline pressure + batch-size cap | inline |
| 5 | Render `plan.md` (Mermaid Gantt + per-service decision table + ready-to-paste commands) | `render_plan.py` |
| 6 | Print summary to session; never auto-commit | inline |

### Step 0 — Tool check

Halt on missing `kustomize`, `yq`, `git`, `python3`. No cluster tools required —
this skill is offline.

### Step 0b — Operator inputs

Two prompts + one required file:

1. **EOL deadline (ISO date)** — e.g. `2025-10-31`. Defaults: if `--deadline`
   is set, skip prompt. If a previous `state.yaml` exists in the same repo
   under `docs/reports/ingress-migration-advisor/`, suggest the prior value.
2. **Tier map file** — read `docs/ingress-tier-map.yaml` from the consumer
   repo root. **HALT** if missing with the message:

   > `docs/ingress-tier-map.yaml not found. The advisor requires an explicit
   > tier map so critical services are never auto-scheduled. Create the file
   > with the format documented in spec §13, then re-run.`

   Validate: every service in the map must exist in `state.yaml.inventory[]`
   (no orphan entries — surface as WARN, not HALT). Every service in
   inventory should appear in the map; missing services default to
   `standard` with a per-service WARN recorded in `state.yaml.warnings[]`.

3. **Batch size cap** — max services per migration batch. Default `5`.
   Override via `--batch-size <n>` on the command line.

Persist all three to `state.yaml.inputs`.

### Step 1 — Inventory

Discover every overlay (`find common.* -path "*/overlays/*" -name kustomization.yaml`),
build it with `kustomize build`, and classify the rendered Ingress documents
using the existing `classify_ingress.py`. Group by service name (deduplicate
across envs — one service can appear in dev/stg/prd).

Output `state.yaml.inventory[]`:

```yaml
inventory:
  - service: argocd-server
    namespace: argocd
    sourceClass: nginx     # nginx | traefik | foreign
    envs: [dev, stg, prd]
    hostsPerEnv:
      dev:  [argocd.dev.awoo.org]
      stg:  [argocd.stg.awoo.org]
      prd:  [argocd.awoo.org]
    annotations:
      total: 12
      cors: false
      authPresent: false
      stubbedLikely: 0   # rough heuristic from annotation-map.md
      unknownLikely: 1
    tlsMode: secret      # secret | managed-cert | none
    pathTypes: [Prefix]
    backendResolved: true
```

### Step 2 — Score

Apply the scoring model from `references/scoring-model.md` (see §7) to each
service. Emit per-dimension scores and a total per service.

### Step 3 — Decide

For each service, look up `total → tier → path` in
`references/decision-matrix.md` (see §8). Override if `--target-path` is set.

Path values:

| Path | Means | Generated Zeus command |
|---|---|---|
| `direct-gateway` | Skip Traefik Ingress; go straight to Gateway API. Only safe for low-risk services. | `*gateway-migrate <module> --source-class nginx --gateway-class traefik` |
| `two-step` | NGINX Ingress → Traefik Ingress → Gateway API. The path the user committed to as default. | `*nginx-to-gateway <env> --gateway-class traefik` |
| `swap-only` | NGINX Ingress → Traefik Ingress now; defer Gateway API migration to a later cycle. | `*nginx-to-traefik <env> <service>` |
| `defer` | Do not migrate this cycle. Flag for follow-up. Service stays on NGINX past the deadline — surfaces in risk register. | (none — manual review item) |

### Step 4 — Batch

Group services with the same path and similar risk profile. Constraints:

- Max `batchSizeCap` services per batch (from Step 0b).
- All envs of one service in the same batch (no split-brain).
- Higher-tier services later in the schedule.
- Total schedule must fit within `deadline - bakeBuffer` where `bakeBuffer`
  defaults to **30 days** (gives 1 month of soak time before EOL).

Emit `state.yaml.batches[]`:

```yaml
batches:
  - id: b1
    path: direct-gateway
    services: [grafana, kibana]
    targetWeek: 2025-07-07
    estimatedDuration: 1 week
  - id: b2
    path: two-step
    services: [argocd-server, harbor, chartmuseum]
    targetWeek: 2025-07-21
    estimatedDuration: 2 weeks
```

### Step 5 — Render plan

`render_plan.py` substitutes the template at `references/plan-template.md`
with state. The template includes:

- Header (deadline, total services, # per path tier, # deferred)
- Mermaid Gantt chart (one row per batch, dated to `targetWeek`)
- Per-service decision table (service | source class | tier | total score |
  path | rationale)
- Per-batch Zeus command block (copy-paste ready)
- Deferred services & risk register
- Audit (operator inputs, schema version, run id)

Write to `docs/reports/ingress-migration-advisor/<slug>/plan.md`.

### Step 6 — Summary

Print:

```
Plan written to docs/reports/ingress-migration-advisor/<slug>/plan.md

  Total services:    18
  direct-gateway:     3  (1 batch, week of 2025-07-07)
  two-step:          12  (3 batches, weeks of 2025-07-21 → 2025-09-01)
  swap-only:          2  (1 batch, week of 2025-09-15)
  defer:              1  (kafka-proxy — manual review)

  Deadline:          2025-10-31
  Bake buffer:       30 days
  Final cutover by:  2025-10-01 (29 days margin)
```

No commit, no further side-effects.

## 7. Scoring model

The scoring model lives in `references/scoring-model.md` as plain markdown
tables so the weights are PR-reviewable like any policy change. Two parts:
a **veto rule** that short-circuits scoring, and a **dimensional rubric**
that runs only when the veto does not fire.

### 7.1 Veto rule — critical traffic tier

Any service marked `critical` in the tier map (see §13 resolved Q3) is
forced to `defer`, regardless of any other dimension scores. The planner
records `decision.path: defer` with `decision.vetoReason: "critical-tier"`
and surfaces the service in the plan's deferred / risk-register section.

Rationale: production-critical services must never be auto-scheduled by a
planner; the team makes the migration call by hand for each one. The
generated plan still contains a recommended path *as guidance* under
`decision.advisoryPath` so the operator can see what the planner *would*
have chosen — but the binding `decision.path` is `defer`.

There is **no `--force-critical` bypass flag.** If the team wants to
migrate a critical service in this cycle, they update the tier map (PR'd
change to `docs/ingress-tier-map.yaml`) and re-run the planner. This keeps
the policy in one place.

### 7.2 Dimensional rubric — applies to non-critical services

| Dimension | Score 1 (low risk) | Score 2 (med) | Score 3 (high) |
|---|---|---|---|
| Annotation complexity | ≤ 5 total, 0 unknown | 6–15, 1–2 unknown | > 15 or > 2 unknown |
| TLS mode | secret | managed-cert | mixed / none |
| Hostname count per env | 1 | 2–3 | ≥ 4 |
| Traffic tier (operator-supplied) | low | standard | (critical = veto, see §7.1) |
| Auth/CORS/security annotations | none | one type present | multiple types |

Total range: **4–14** (traffic tier capped at 2 because score-3 = critical = vetoed).

Weights are equal across dimensions (each contributes 1–3). The
implementation in `score_services.py` reads `references/scoring-model.md`
at runtime — a team that wants to reweight a dimension edits the markdown
table without touching code.

## 8. Decision matrix

The matrix lives in `references/decision-matrix.md`. Decision order:

1. **Veto first** — if §7.1 fires (`critical` tier), path = `defer`. Skip the rest.
2. **Source-class shortcut** — if `sourceClass == traefik`, path = `direct-gateway`
   regardless of score. Rationale: the Traefik Ingress phase is already
   complete; only the Gateway migration remains. Running `two-step` would
   either no-op the swap phase or attempt to re-swap an already-swapped
   resource. The shortcut prevents that.
3. **Score-based bands** — for non-vetoed, NGINX-source services:

| Total score | Path | Generated command |
|---|---|---|
| 4–7 | `direct-gateway` | `*gateway-migrate <module> --source-class nginx --gateway-class traefik` |
| 8–10 | `two-step` (default for medium-risk NGINX services) | `*nginx-to-gateway <env> --gateway-class traefik` |
| 11–13 | `swap-only` (Traefik Ingress now, defer Gateway phase) | `*nginx-to-traefik <env> <service>` |
| 14 | `defer` | (none — manual review) |

Generated commands per source class:

| Source class | Path | Command |
|---|---|---|
| nginx | direct-gateway | `*gateway-migrate <module> --source-class nginx --gateway-class traefik` |
| traefik | direct-gateway (via §8 step 2) | `*gateway-migrate <module> --source-class traefik --gateway-class traefik --no-redirect` |
| nginx | two-step | `*nginx-to-gateway <env> --gateway-class traefik` |
| nginx | swap-only | `*nginx-to-traefik <env> <service>` |
| traefik | swap-only / two-step / N/A | — (already on Traefik Ingress; if not vetoed, falls through to direct-gateway) |
| foreign | any | record-only; advisor surfaces in deferred section with note "non-nginx, non-traefik class — out of scope" |

The `--no-redirect` flag for the Traefik-source direct-gateway command
matches the existing `gateway-api-migration` v1.11.0 contract (Traefik's
EntryPoint already redirects HTTP→HTTPS, so the extra HTTPRoute would
conflict).

## 9. State YAML schema

```yaml
schemaVersion: 1
skillVersion: "1.0.0"
runId: <ulid>
createdAt: <iso>
inputs:
  deadline: 2025-10-31
  bakeBufferDays: 30
  batchSizeCap: 5
  targetPathOverride: null  # or "two-step" etc.
  tierMap:
    argocd-server: critical
    grafana: standard
    kibana: low
inventory:
  - service: ...
    sourceClass: nginx
    envs: [dev, stg, prd]
    ...
scores:
  - service: argocd-server
    dimensions:
      annotationComplexity: 2
      tlsMode: 1
      hostnameCount: 1
      trafficTier: 3
      securityAnnotations: 2
    total: 9
    rationale: "12 annotations, 1 unknown; secret-based TLS; 1 host per env; critical tier; CORS present"
decisions:
  - service: argocd-server
    path: two-step
    overrideReason: null
    suggestedCommand: "*nginx-to-gateway prd --gateway-class traefik"
batches:
  - id: b1
    path: two-step
    services: [...]
    targetWeek: 2025-07-21
    estimatedDuration: 2 weeks
deferred:
  - service: kafka-proxy
    reason: "Score 16 — manual review required"
verdict: PASS | WARN | FAIL
reportPath: docs/reports/ingress-migration-advisor/<slug>/plan.md
```

## 10. Halt conditions

| Step | Halt cause |
|---|---|
| 0 | Required tool missing |
| 0b | Deadline in the past |
| 0b | `docs/ingress-tier-map.yaml` missing (operator must create it before re-run) |
| 0b | Tier map references services not in inventory **and** `--strict-tier-map` flag is set (otherwise WARN) |
| 1 | Zero Ingresses found (nothing to plan) |
| 1 | `kustomize build` fails across all overlays |
| 2 | Scoring script crashes (treat as bug, not user error) |
| 5 | Template substitution leaves unresolved placeholders → WARN, not HALT |

WARN-not-HALT cases:
- Services in inventory missing from tier map → defaults to `standard` with
  a per-service WARN; advisor continues.
- Tier map references unknown services (orphan entries) → WARN unless
  `--strict-tier-map` is passed.
- Zero deferred services → no risk register section, plan still renders.
- Batch schedule overflows `deadline - bakeBuffer` → renders with a banner;
  operator must shrink scope, extend deadline, or shrink bake buffer.

## 11. Risks and tradeoffs

| Risk | Mitigation |
|---|---|
| Scoring is subjective; bad weights produce bad plans | Weights live in `references/scoring-model.md` as plain data — reviewable in PR, not hidden in code |
| Plan ages quickly as repo changes | Each run is a fresh snapshot; `--resume` only re-renders, doesn't refresh inventory. Re-run when repo shifts. |
| Operator skips the planner and migrates ad-hoc | Cheap to ignore; advisor is opt-in. Adoption depends on the plan.md being readable enough to share with the team. |
| Tier map drifts from reality | Surface in plan header; recommend storing tier map in `docs/ingress-tier-map.yaml` checked into the repo |
| `direct-gateway` path skips a safety net | Scoring model controls eligibility; default thresholds err toward `two-step` |

## 12. Release plan

- **v1.12.0** — `ingress-migration-advisor` skill ships standalone.
  - Add Zeus pipeline `prompts/zeus/ingress-migration-advisor.md`.
  - Update CLAUDE.md command table.
  - Add Gemini TOML command equivalent.
- Skill version bumped independently of A/B/C skills.
- No schema changes to existing skills.

## 13. Resolved decisions log

All five questions resolved on 2026-05-19. Recorded here so future readers
understand the rationale behind each design choice.

| # | Question | Decision | Where encoded |
|---|---|---|---|
| 1 | Scoring weights | Equal weights (1–3 per dimension); critical tier is a veto, not a score-3 entry | §7.1, §7.2 |
| 2 | Decision cutoffs | Bands 4–7 / 8–10 / 11–13 / 14 (score range adjusted to 4–14 because critical-tier is now veto, not score-3) | §8 |
| 3 | Tier map storage | `docs/ingress-tier-map.yaml` in consumer repo (PR-reviewed); inline-prompt fallback **dropped** to keep one source of truth | §6 step 0b, §9 `inputs.tierMap` |
| 4 | Mermaid Gantt granularity | Week-of (e.g., "week of 2025-07-21") — operator picks the exact day | §6 step 5, plan template |
| 5 | `sourceClass: traefik` shortcut | Source-class veto: traefik-source → `direct-gateway` always (skips the redundant Traefik Ingress phase) | §8 step 2 |

### Tier map file format (decision 3)

```yaml
# docs/ingress-tier-map.yaml — sibling of docs/PROJECT.md
# Reviewed via PR. Advisor reads this file at Step 0b.

schemaVersion: 1
services:
  argocd-server:   critical
  harbor:          critical
  grafana:         standard
  kibana:          standard
  chartmuseum:     standard
  mlflow:          low
  registry-mirror: low
# Services not listed default to "standard" with a WARN.
```

When `docs/ingress-tier-map.yaml` is missing entirely, the advisor halts
with a message telling the operator to create one. This is intentional:
the migration plan should not silently default 18 services to `standard`
and risk auto-scheduling a critical cutover. Bootstrapping the file is a
one-time cost.
