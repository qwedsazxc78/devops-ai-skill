# install-traefik Pipeline

GitOps-flavored Traefik Ingress Controller bootstrap, env addition, or
chart upgrade in a Kustomize + ArgoCD repo. Operates exclusively on
files under `common.traefik/`. **Never runs `helm install` or
`helm upgrade`** — those would conflict with ArgoCD reconciling the
same release.

Delegates all logic to the `ingress-controller-install` skill v2.0.0.

## When to use

- **Bootstrap**: cluster has neither Traefik nor `common.traefik/`.
  Skill scaffolds the module from a template.
- **New env**: `common.traefik/base/` exists but `overlays/<env>/` does
  not. Skill copies an existing overlay and prompts for env-specific
  overrides.
- **Upgrade**: bump the Traefik Helm chart version in
  `helmCharts[0].version` across base + every overlay (atomic, with
  pre-commit consistency check).

Mode is auto-detected; override with `--mode <bootstrap|new-env|upgrade>`.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize`, `yq`, `git`, `jq` (all required)
- Gate: HALT on missing

### Step 2: Detect Mode

- Invoke skill Step 1 via `scripts/detect_mode.sh`
- Returns `{mode, moduleExists, baseExists, targetEnvExists, existingOverlays, currentChartVersion}`
- Gate: HALT if `--mode` is forced but incompatible with detected state (e.g., `--mode bootstrap` when module already exists, no `--force`)

### Step 3: Branch on Mode

- **bootstrap**: scaffold `common.traefik/{base,overlays/<env>,argocd}/` from template; substitute `${LB_IP}`, `${INGRESS_CLASS_NAME}`, `${GATEWAY_API_ENABLED}` (operator-supplied)
- **new-env**: copy `overlays/<source-env>/` → `overlays/<target-env>/`; prompt for env-specific overrides
- **upgrade**: no structural changes (version bump happens in Step 5)

### Step 4: Validate Coexistence

- Invoke skill Step 3 via `scripts/validate_coexistence_kustomize.sh`
- Read-only Kustomize-build inspection across `common.*/overlays/<env>/`
- Three checks: IngressClass collision, LB IP collision, port 80/443 collision in target namespace
- Gate: HALT on any collision; plan files NOT written

### Step 5: Apply Edits (with backups)

- **bootstrap** / **new-env**: write the planned files directly
- **upgrade**: invoke `scripts/upgrade_chart_version.sh --target <version>` — atomic bump across base + all overlays, with full-file backups
- Build sanity-check: `kustomize build --enable-helm common.traefik/overlays/<env>` must exit 0
- Gate: on build failure, restore from backups; HALT

### Step 6: Render Plan + Commit Message

- Write `plan.md`, `diff.patch`, `state.yaml` to report dir
- Print the exact git commands the operator runs next:

```bash
git add common.traefik/
git commit -m "<message from plan.md>"
git push
# For bootstrap / new-env only:
kubectl apply -f common.traefik/argocd/<env>.yaml
```

- Never auto-commit; never run `helm install/upgrade`; never run `kubectl apply`

## Invocation Reference

```
*install-traefik                                # interactive
*install-traefik --env dev                      # explicit target env
*install-traefik --env new-region --mode new-env
*install-traefik --upgrade-to 40.1.0            # upgrade every overlay's chart version
*install-traefik --resume <state-path>          # continue from state.yaml
```

## Output Artifacts

Under `docs/reports/ingress-controller-install/<isodate>/`:

- `state.yaml` — machine-readable plan state
- `plan.md` — operator-readable summary + git commands
- `diff.patch` — unified diff of all proposed file edits (preview before staging)

## Verdict outcomes

- `READY` — coexistence passed, plan written; operator runs git + (for bootstrap/new-env) `kubectl apply`
- `BLOCKED` — class / LB IP / port collision detected; plan NOT written
- `NEEDS_REVIEW` — kustomize build degraded; operator must inspect manually
