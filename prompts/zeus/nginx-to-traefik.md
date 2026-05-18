# nginx-to-traefik Pipeline

Class-swap migration from NGINX Ingress to Traefik Ingress
(`ingressClassName: traefik`). Both controllers run in parallel;
DNS A-records are the only cutover lever. Delegates all logic to the
`nginx-to-traefik` skill.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git` (required)
- Gate: HALT on missing required tools with install hints

### Step 2: Env Config

- Invoke `nginx-to-traefik` skill Step 0b
- Prompt operator for LB IPs and cert issuer if not in `state.yaml.envConfig`
- Gate: HALT on decline

### Step 3: Inventory & Batch Plan

- Invoke skill Step 1 (inventory) + Step 2 (batch plan)
- Present summary with host + service + namespace counts per batch
- Gate: interactive `y/N` confirmation (HALT on decline)

### Step 4: Generate Traefik Ingresses

- Invoke skill Step 3 per service
- Surface WARN-level annotation translations to operator
- Gate: HALT on script exit != 0

### Step 5: Archive nginx + Edit kustomization + Managed-cert

- Invoke skill Steps 4 + 5 + 6 atomically
- Backup originals before any edit (recorded in `state.yaml.backups[]`)
- Gate: HALT on schema mismatch

### Step 6: Build & Cross-consistency

- Invoke skill Step 7 + 7b
- Gate: HALT on `kustomize build` failure or stale-host detection
  (rollback via `git restore` of state.yaml.backups[])

### Step 7: Update DNS + Verify Scripts

- Invoke skill Steps 8 + 9
- Gate: WARN if dns-create-traefik.sh missing (operator must own the script)

### Step 8: Print Commit Message and Cutover Runbook

- Invoke skill Step 10
- Print suggested commit message + pointer to dns-cutover-runbook.md
- Never auto-commit

## Output Artifacts

- `docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/state.yaml`
- `docs/reports/nginx-to-traefik/<env>-<batch>-<isodate>/report.md`
- Modified files in `common.service/overlays/<env>/`
- Modified `common.traefik/overlays/<env>/app.ingress.yaml`
- Modified `scripts/dns-create-traefik.sh` and `scripts/verify-traefik-<env>.sh`
