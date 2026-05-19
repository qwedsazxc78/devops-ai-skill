# install-traefik-controller Pipeline

Idempotent install OR upgrade of the Traefik Ingress Controller via Helm,
with safe coexistence checks against `ingress-nginx` (no class collision,
no LB IP collision, no port 80/443 conflict).

Delegates all logic to the `ingress-controller-install` skill. Generates
a print-only `install.sh`; the operator runs `helm install/upgrade`
manually.

## When to use

- Standing up Traefik on a cluster that currently serves traffic via
  ingress-nginx, before any service migration runs (prerequisite for
  *nginx-to-traefik / *gateway-migrate).
- Bumping the Traefik chart version on an existing install.
- Validating coexistence after an external change to the cluster.

## Pipeline Steps

### Step 1: Tool Check

- Verify `helm`, `kubectl`, `yq`, `jq`, `curl` (last for ArtifactHub)
- Gate: HALT on `helm`, `kubectl`, or `yq` missing

### Step 2: Detect Existing Install

- Invoke skill Step 1 via `scripts/detect_existing_install.sh`
- Branch: install vs upgrade based on `existingInstall`
- Gate: HALT if `--upgrade-only` was passed but no install found

### Step 3: Operator Inputs

- Invoke skill Step 2a (new install) or Step 2b (upgrade)
- Prompts: env, namespace, ingressClassName, lbIp (operator-declared —
  NEVER auto-derive), chartVersion, gatewayApiEnabled
- Gate: HALT if operator declines required prompts

### Step 4: Resolve Chart Version

- Invoke skill Step 3
- Query ArtifactHub for latest Traefik chart
- For upgrades: present diff with current; WARN loudly on major bump
- Gate: WARN if ArtifactHub unreachable (verdict will be NEEDS_REVIEW)

### Step 5: Validate Coexistence

- Invoke skill Step 4 via `scripts/validate_coexistence.sh`
- Asserts: classCollision=false, ipCollision=false, portCollision=false
- Gate: HALT on ANY collision; print remediation from
  `references/coexistence-checklist.md`

### Step 6: Render values.yaml + install.sh

- Invoke skill Step 5 + 6
- Substitute `references/values-template.yaml` placeholders
- Emit `install.sh` with the exact `helm install` (or `helm upgrade`)
  command

### Step 7: Verdict + Summary

- Invoke skill Step 7
- Write `state.yaml`, print verdict (READY/BLOCKED/NEEDS_REVIEW)
- Print: "Run `bash docs/reports/ingress-controller-install/<date>/install.sh`"
- Never auto-commit; never execute `helm install`

## Invocation Reference

```
*install-traefik                                 # interactive
*install-traefik --env <dev|stg|prd>             # render plan for one env
*install-traefik --upgrade-only                  # require existing install
*install-traefik --resume                        # continue from state.yaml
```

## Output Artifacts

Under `docs/reports/ingress-controller-install/<date>/`:

- `state.yaml` — machine-readable plan state
- `values.yaml` — rendered Traefik Helm values (parameterized per env)
- `install.sh` — the exact `helm install`/`upgrade` command (operator runs manually)

## Verdict outcomes

- `READY` — coexistence validated, plan written
- `BLOCKED` — class/IP/port collision detected; plan files NOT written
- `NEEDS_REVIEW` — major version bump, unfamiliar existing classes, or
  ArtifactHub unreachable; plan written but explicit operator sign-off
  required
