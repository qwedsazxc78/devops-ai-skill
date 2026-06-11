# retire-nginx Pipeline

Post-migration cleanup pipeline that retires the nginx ingress
**controller** (`common.ingress`) and all nginx **Ingress resources**
(`common.service`) for one environment or all environments, after the
Gateway API / Traefik migration is complete.

**Never applies anything to a cluster** — deletes the controller's
ArgoCD Application yaml from Git; app-of-apps `prune: true` removes the
Application, and its resources-finalizer cascades the controller
resources away. Base nginx Ingress files stay intact — the target env
excludes them via `$patch: delete` in its overlay kustomization.

Delegates all logic to the `nginx-ingress-retire` skill v1.17.0.

## When to use

After every service in the target env has an active HTTPRoute or
Traefik Ingress, DNS has been cut over to the Traefik/Gateway LB, and
nginx is confirmed idle (no live traffic). This is the per-env "remove
the dead nginx layer" step — it complements `*decommission-nginx`,
which archives the whole controller module repo-wide.

## Pipeline Steps

### Step 1: Parse Arguments

- `dev` | `stg` | `prd` — retire one environment
- `all` — retire sequentially (dev → stg → prd), validating each before the next
- No argument — interactive: detect envs from `common.ingress/overlays/` + `common.service/overlays/`, ask which to retire

### Step 2: Pre-flight Safety Check (per env)

- `kustomize build common.service/overlays/<env>` must succeed — **HALT** if broken
- Inventory breakdown: nginx Ingresses (to retire) vs Traefik Ingresses + HTTPRoutes (replacements)
- Gate: **HALT** if nginx > 0 but zero replacements (retiring would cause an outage)
- Gate: **HALT** if nothing at all found (migration not done)
- Soft warn + confirm if nginx already 0 but replacements exist (cleanup-only rerun)
- Active nginx entries in the overlay kustomization are cross-checked against the
  rendered `ingress.class` — class-override patches (gce/alb) are kept, true nginx
  entries require confirmation

### Step 3: Discovery (per env)

- Controller artifacts: `common.ingress/argocd/<env>.yaml` + overlay dir
- Base nginx Ingress resources rendered into this env (exact `metadata.name` via `kustomize build`, not grep)
- Orphaned `*nginx*` files in the overlay not referenced by `kustomization.yaml`
- `archive/` migration-snapshot dir

### Step 4: Removal Plan + Confirm

- Print the full plan: DELETE / PATCH / KEEP per artifact, with the cascade chain explained
- Gate: **HALT** until the operator explicitly confirms

### Step 5: Execute (per env)

- Delete `common.ingress/argocd/<env>.yaml` (app-of-apps prune → Application finalizer cascades controller removal)
- Append `$patch: delete` entries to `common.service/overlays/<env>/kustomization.yaml`
  for each base nginx Ingress (un-prefixed names — patches run before `namePrefix`)
- Class-override patches (gce/alb) are **never** deleted — rename the file for clarity, keep the resource name
- Delete confirmed orphan files and the `archive/` dir

### Step 6: Validate (per env)

- nginx-class Ingress count must be **0** (NOT total Ingress count — Traefik Ingresses legitimately remain)
- Remaining Ingresses verified non-nginx class
- Regression: all **other** envs still `kustomize build` cleanly — **HALT** on any failure, do not commit

### Step 7: All-Env Cleanup Check (only after `all`)

- If `common.ingress/` has no overlays left, offer to archive or delete the whole module
- If no env renders base nginx files anymore, offer to remove them from `common.service/base/`

### Step 8: Summary Report

- Per-env table: controller / overlay / nginx count / Traefik kept / validation
- Files deleted, modified, kept; regression results; commit message + post-merge verification steps

## Invocation Reference

```
*retire-nginx                # interactive — detect envs, ask
*retire-nginx dev            # retire dev only
*retire-nginx stg            # retire stg only
*retire-nginx prd            # retire prd only
*retire-nginx all            # all envs sequentially (dev → stg → prd)
```

## Output

- Modified `common.service/overlays/<env>/kustomization.yaml` (+ `$patch: delete` entries)
- Deleted `common.ingress/argocd/<env>.yaml`, orphan files, `archive/` dir
- Summary report with suggested commit message:
  `retire(nginx/<env>): remove controller app + exclude base nginx Ingress resources`
- Never auto-commits; never touches the cluster

## Safety gates recap

| Gate | Outcome |
|------|---------|
| Broken overlay build | **Hard abort** |
| nginx > 0 with zero replacements | **Hard abort** — migration not complete |
| Zero nginx + zero replacements | **Hard abort** — nothing migrated |
| Already retired (replacements exist) | Soft warn + confirm |
| Class-override patch (gce/alb) | Keep — never `$patch: delete` |
| Other env regression failure | **Halt** — do not commit |
