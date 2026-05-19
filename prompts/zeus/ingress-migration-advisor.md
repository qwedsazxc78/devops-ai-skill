# ingress-migration-advisor Pipeline

Read-only migration planner. Inventories every Ingress in the repo,
scores each service on five migration-readiness dimensions, recommends
a path per service (`direct-gateway` | `two-step` | `swap-only` |
`defer`), and emits a phased plan with ready-to-paste Zeus commands.

Delegates all logic to the `ingress-migration-advisor` skill. Never
mutates the repo. Never invokes the migration skills (A/B/C) — only
recommends commands the operator runs manually.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git`, `python3` (all required)
- Gate: HALT on missing required tools with install hints

### Step 2: Operator Inputs

- Invoke skill Step 0b
- Read `docs/ingress-tier-map.yaml` from the consumer repo
- Prompt operator for EOL deadline + batch size cap (unless passed as flags)
- Gate: HALT on missing tier map; WARN on missing-per-service tier entries

### Step 3: Inventory

- Invoke skill Step 1
- Build every overlay matching `common.*/overlays/<env>/`
- Classify rendered Ingresses (nginx | traefik | foreign)
- Gate: HALT if zero Ingresses found or all `kustomize build` failed

### Step 4: Score + Decide

- Invoke skill Steps 2 + 3
- Apply critical-tier veto, sourceClass shortcut, score bands
- Surface per-service decisions to operator (verbose summary in terminal)
- Gate: WARN-only at this stage; HALT only on script crash

### Step 5: Batch + Render Plan

- Invoke skill Steps 4 + 5
- Group decisions into batches sized to `--batch-size` (default 5)
- Schedule batches at weekly cadence; flag overflow if schedule exceeds
  `deadline - bakeBufferDays`
- Render `plan.md` from `references/plan-template.md`
- Gate: WARN-only

### Step 6: Print Summary

- Invoke skill Step 6
- Print path counts + deadline + final cutover date + plan path
- Never auto-commit; never invoke A/B/C skills

## Invocation Reference

```
*ingress-migration-advisor
*ingress-migration-advisor --deadline 2025-10-31
*ingress-migration-advisor --deadline 2025-10-31 --batch-size 5
*ingress-migration-advisor --target-path two-step
*ingress-migration-advisor --strict-tier-map
*ingress-migration-advisor --bake-buffer-days 30
*ingress-migration-advisor --resume <state-path>
```

## Output Artifacts

- `docs/reports/ingress-migration-advisor/<isodate>-<ulid>/state.yaml`
  — machine-readable plan state
- `docs/reports/ingress-migration-advisor/<isodate>-<ulid>/plan.md`
  — Mermaid Gantt + per-service decision table + per-batch commands

## Consumer prerequisites

The consumer repo must provide:

- `docs/ingress-tier-map.yaml` — service → tier (`critical|standard|low`)
- At least one `common.*/overlays/<env>/kustomization.yaml` building
  successfully with `kustomize build`

If either is missing the pipeline halts at Step 2 / Step 3 with an
actionable error message.
