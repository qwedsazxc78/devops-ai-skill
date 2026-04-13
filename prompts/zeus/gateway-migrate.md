# Gateway API Migration Pipeline

End-to-end migration from NGINX Ingress (master/minion or standalone) to
GKE Gateway API. Delegates all logic to the `gateway-api-migration` skill.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize` and `yq` (required)
- Check `kubeconform` and `ingress2gateway` (optional, graceful degradation)
- Gate: HALT on missing required tools with install hints

### Step 2: Topology Discovery

- Invoke `gateway-api-migration` skill Step 1
- Detect master/minion or standalone topology
- Pair minions with masters by hostname
- Gate: HALT on no Ingress found, orphan minions, or ambiguous pairings

### Step 3: Annotation Analysis

- Invoke skill Step 2
- Classify annotations per `references/annotation-map.md`
- Present summary with annotation category counts
- Gate: interactive user confirmation (HALT on decline)

### Step 4: Two-Phase Conversion

- Invoke skill Step 3 (Phase 3A: common.gateway/ module)
- Invoke skill Step 3 (Phase 3B: HTTPRoutes + in-place kustomization.yaml edits)
- Gate: HALT on write failure, target-exists-without-force, or post-edit
  build failure (with automatic rollback of in-place edits)

### Step 5: Validation

- Step 4a kustomize build (required) — HALT on failure
- Step 4b kubeconform (optional) — WARN on unknown CRDs
- Step 4c ingress2gateway second opinion (optional) — record diff, never halt
- Gate: HALT on 4a failure; WARN on 4b/4c

### Step 6: Report Rendering

- Invoke skill Step 5
- Write state.yaml + report.md under docs/reports/gateway-migration/<slug>/
- Gate: WARN on write failure, print report to stdout as fallback

### Step 7: Runbook Output

- Invoke skill Step 6
- Print per-hostname DNS cutover runbook to session
- Also written to common.gateway/MIGRATION.md
- Gate: informational

### Step 8: Pre-commit Hints

- Invoke skill Step 7
- Print suggested commit message and `git add` commands
- Never auto-commit
- Gate: informational

## Invocation forms

- `*gateway-migrate` — interactive discovery mode
- `*gateway-migrate <module-path>` — explicit target
- `*gateway-migrate <module-path> --resume` — resume from state.yaml
- `*gateway-migrate <module-path> --force` — bypass never-clobber

See `skills/gateway-api-migration/SKILL.md` for full halt/resume semantics
and state YAML schema.
