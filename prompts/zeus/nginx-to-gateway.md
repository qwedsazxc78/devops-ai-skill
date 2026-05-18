# nginx-to-gateway Pipeline

Chained migration from NGINX Ingress → Traefik Ingress → Gateway API.
Thin orchestrator. Delegates all conversion logic to skills
`nginx-to-traefik` and `gateway-api-migration`.

## Pipeline Steps

### Step 1: Tool Check

- Merged superset of skill A and skill B tool requirements
- Gate: HALT on missing required tools

### Step 2: Create Chain Run-dir

- Invoke skill Step C.1
- Initialize `docs/reports/nginx-to-gateway/<slug>/index.yaml`
- Gate: HALT if dir exists without `--force`

### Step 3: Phase A — nginx-to-traefik

- Spawn `nginx-to-traefik` as subroutine (skip if `--skip-a`)
- Gate: HALT chain on phase-A halt; record `phaseB.status: blocked`

### Step 4: Hand-off

- Invoke skill Step C.3
- Read A's `outputs.traefikIngresses[]`; copy into chain index
- Gate: HALT on zero outputs

### Step 5: Phase B — gateway-api-migration

- Spawn `gateway-api-migration` with `--source-class traefik --no-redirect`
- Gate: HALT chain on phase-B halt

### Step 6: Render combined index

- Invoke skill Step C.5
- Substitute `chain-report-template.md` variables
- Gate: informational only

## Output Artifacts

- `docs/reports/nginx-to-gateway/<slug>/index.yaml`
- `docs/reports/nginx-to-gateway/<slug>/index.md`
- All phase-A and phase-B artifacts under their respective report dirs
