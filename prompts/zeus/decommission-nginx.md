# decommission-nginx Pipeline

GitOps-flavored final-stage pipeline for the nginx → traefik migration
arc. Verifies the cluster + repo are free of `ingressClassName: nginx`
(precedence-aware), confirms the DNS bake period elapsed, then
generates a **print-only** archive + ArgoCD-disable + LB cleanup plan.

**Never runs `helm uninstall` or `kubectl delete`** — ArgoCD prunes
resources via its sync mechanism when the module is archived and the
Application is removed.

Delegates all logic to the `traefik-controller-decommission` skill v2.0.0.

## When to use

After every Ingress has been migrated to Traefik (or Gateway API) AND a
bake period has elapsed during which the Traefik LB served 100% of
traffic. This is the "kill the old controller" final step.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git`, `jq` (required)
- Verify `kubectl`, `gcloud` (WARN-only — used for richer plan, not blocking)

### Step 2: Discover ingress-nginx Module

- Invoke skill Step 1 via `scripts/discover_nginx_module.sh`
- Returns module path + list of ArgoCD Application manifests + namespace
- Gate: HALT if zero modules found OR multiple modules (ambiguous — operator passes `--module <path>`)

### Step 3: Operator Inputs

- Date, operator handle, migration cycle slug
- Optional GCP project for LB IP / IAM cleanup section
- Gate: HALT if required inputs missing

### Step 4: Verify Zero Active nginx Ingresses

- Invoke skill Step 3 via `scripts/verify_no_nginx_class.sh --all`
- Dual scan: cluster (`kubectl get ingress -A`) + repo (`kustomize build` across `common.*/overlays/*/`)
- **Precedence-aware**: an Ingress is nginx-class if `spec.ingressClassName == "nginx"` OR (`spec.ingressClassName == null` AND legacy `kubernetes.io/ingress.class == "nginx"`)
- Gate: HALT on exit 1 (BLOCKED) — at least one nginx Ingress still active

### Step 5: DNS Bake Confirmation

- Interactive prompt: bake period elapsed + monitored hostnames healthy on Traefik LB
- Gate: HALT on any answer other than `yes` (use `--skip-dns-bake` to bypass with NEEDS_REVIEW verdict)

### Step 6: Generate Decommission Plan

- Invoke skill Step 5 via `scripts/generate_decommission_plan.sh`
- Three sections rendered into `plan.md` + `commands.sh`:
  - **5a. Archive the Kustomize module**: `git mv common.ingress-nginx/ archive/` → ArgoCD will see the deleted manifests on next sync and prune the live resources
  - **5b. Disable + delete the ArgoCD Application**: `kubectl patch application` to disable auto-sync, trigger prune, then `kubectl delete -f` the Application manifest
  - **5c. (Optional) LB IP release + IAM cleanup**: GKE LB cleanup commands; skipped with `--no-lb-cleanup`

### Step 7: Render State + Print Summary

- Write `state.yaml`, `verify.json` to report dir
- Print verdict + next-step instructions
- Never auto-commit; never execute `commands.sh`

## Invocation Reference

```
*decommission-nginx                              # interactive
*decommission-nginx --cycle prod-batch-3         # named cycle
*decommission-nginx --module common.ingress-nginx  # explicit when ambiguous
*decommission-nginx --skip-dns-bake              # NEEDS_REVIEW verdict
*decommission-nginx --no-lb-cleanup              # skip section 5c
*decommission-nginx --resume <state-path>        # re-render from existing state
```

## Output Artifacts

Under `docs/reports/traefik-controller-decommission/<date>/`:

- `state.yaml` — machine-readable state (discovery, verifications, plan, verdict)
- `verify.json` — raw cluster + repo scan results
- `plan.md` — operator-readable plan (3 sections)
- `commands.sh` — copy-paste-ready bash (NEVER auto-executed)

## Verdict outcomes

- `READY` — all gates passed; `commands.sh` written
- `BLOCKED` — any verification gate failed; `commands.sh` NOT written
- `NEEDS_REVIEW` — discovery ambiguous or `--skip-dns-bake` was used; plan written but explicit operator sign-off required
- `DEGRADED` — at least one scan couldn't run (e.g., kubectl unreachable); proceed with caution
