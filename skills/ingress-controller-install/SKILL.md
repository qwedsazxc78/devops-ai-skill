---
name: ingress-controller-install
description: >
  Idempotent install or upgrade of the Traefik Ingress Controller via Helm,
  configured for safe coexistence with an existing `ingress-nginx` controller
  (distinct IngressClass, distinct LoadBalancer IP, no port collision). Use
  when standing up Traefik on a cluster that already serves traffic through
  `ingress-nginx`, when bumping a Traefik chart version, or when validating
  controller coexistence before a migration. Plan-only — never executes
  `helm install`, `helm upgrade`, or `kubectl apply`.
version: "1.0.0"
---

# ingress-controller-install Skill

Invoked by Horus pipeline `*install-traefik`.

This skill produces an **install plan** for Traefik that an operator runs
manually. It detects whether Traefik is already deployed, branches into
either an install or upgrade flow, validates coexistence with
`ingress-nginx`, renders a parameterized `values.yaml`, and emits a
ready-to-run `install.sh` containing the exact `helm` command. The skill
never invokes `helm`, `kubectl`, or any state-mutating command itself.

## Canonical references

| File | When to read |
|---|---|
| `references/coexistence-checklist.md` | Step 0, Step 4 — pre/post-install cluster checks |
| `references/values-template.yaml` | Step 5 — base Helm values, parameterized per env |

## Bundled scripts

| Script | Used by | Purpose |
|---|---|---|
| `scripts/detect_existing_install.sh` | Step 1 | helm + kubectl probes for existing Traefik |
| `scripts/validate_coexistence.sh` | Step 4 | Class, LB IP, and port collision checks |

## Activation

Triggered explicitly by `*install-traefik` from Horus. Not auto-triggered.

## Invocation forms

```
*install-traefik                                 # interactive: detect + prompt
*install-traefik --env <dev|stg|prd>             # render plan for one env
*install-traefik --upgrade-only                  # only run if already installed
*install-traefik --resume                        # continue from state.yaml
```

## Output location

All artifacts land under:

```
docs/reports/ingress-controller-install/<ISO_DATE>/
  state.yaml         # machine-readable plan + verdict
  values.yaml        # rendered Traefik Helm values
  install.sh         # exact `helm` command to run manually
```

`<ISO_DATE>` is the current `YYYY-MM-DD` UTC date.

## Step Flow

| Step | Action | Script |
|---|---|---|
| 0 | Tool check (`helm`, `kubectl`, `yq`) | inline `command -v` |
| 1 | Detect existing Traefik install | `detect_existing_install.sh` |
| 2 | Gather operator inputs (install OR upgrade branch) | inline prompts |
| 3 | Resolve target chart version (ArtifactHub) | inline curl |
| 4 | Validate coexistence with `ingress-nginx` | `validate_coexistence.sh` |
| 5 | Render `values.yaml` from `references/values-template.yaml` | inline templating |
| 6 | Emit `install.sh` with the exact `helm` command | inline |
| 7 | Write `state.yaml`, print verdict, HALT (plan-only) | inline |

### Step 0 — Tool check

Run `command -v helm kubectl yq`. HALT on any missing. Print actionable
install hints (`brew install helm`, `gcloud components install kubectl`,
`brew install yq`).

### Step 1 — Detect existing install

Invoke `scripts/detect_existing_install.sh`. It runs two probes:

1. `helm list -A -o json -f '^traefik$'` — match release name `traefik`.
2. `kubectl get ingressclass -o json` — enumerate registered classes.

Write to `state.yaml.detection`:

```yaml
detection:
  existingInstall: <bool>
  currentVersion: "<chart-version or null>"
  currentNamespace: "<namespace or null>"
  existingClasses: ["nginx", "traefik?", ...]
```

Branch:
- `existingInstall: false` → **NEW INSTALL** flow (Step 2a).
- `existingInstall: true`  → **UPGRADE** flow (Step 2b).
- `--upgrade-only` was passed and `existingInstall: false` → HALT with
  verdict `BLOCKED` and message "no existing Traefik release found".

### Step 2a — Inputs (NEW INSTALL)

Prompt the operator (use defaults aggressively, never invent LB IPs):

| Prompt | Default | Notes |
|---|---|---|
| `env` | (required) | One of `dev`, `stg`, `prd` |
| `namespace` | `traefik` | Will be created if missing |
| `ingressClassName` | `traefik` | MUST differ from any existing class |
| `lbIp` | (required) | Static IP. May be a GCP `compute address` name (e.g. `traefik-dev-ip`) — the operator resolves it — or a raw IPv4. Never auto-derive. |
| `chartVersion` | latest from ArtifactHub (Step 3) | Operator may pin |
| `gatewayApiEnabled` | `false` | Enables `providers.kubernetesGateway` |

Write to `state.yaml.inputs`.

### Step 2b — Inputs (UPGRADE)

Read `state.yaml.detection.currentVersion` as the **from** version. Prompt:

| Prompt | Default | Notes |
|---|---|---|
| `chartVersion` | latest from Step 3 | Show diff with current |
| `preserveExistingValues` | `true` | Recommend `helm get values traefik -n <ns>` and merge |
| `gatewayApiEnabled` | preserve current | Detect from existing values |

`namespace`, `ingressClassName`, and `lbIp` are read from the live release
and re-validated in Step 4, never re-prompted.

### Step 3 — Resolve target chart version

Query ArtifactHub for the canonical Traefik chart:

```
GET https://artifacthub.io/api/v1/packages/helm/traefik/traefik
```

Extract `version` and `app_version`. If the operator pinned a version in
Step 2, use that; otherwise default to the latest. Record both fields:

```yaml
inputs:
  chartVersion: "<resolved>"
  chartAppVersion: "<resolved>"
```

For upgrades, present a one-line diff (`<currentVersion> -> <chartVersion>`)
and a `Patch | Minor | Major` classification. Warn loudly on major.

### Step 4 — Validate coexistence

Invoke `scripts/validate_coexistence.sh` with:
- `--ingress-class <ingressClassName>`
- `--lb-ip <lbIp>`
- `--namespace <namespace>`

The script asserts three invariants and writes one boolean each to
`state.yaml.validation`:

| Check | Pass condition |
|---|---|
| `classCollision: false` | Chosen `ingressClassName` is **not** in the existing `kubectl get ingressclass` output (excluding any pre-existing `traefik` class on UPGRADE). |
| `ipCollision: false` | Chosen `lbIp` is **not** an IP currently bound to any `Service` of type `LoadBalancer` belonging to a different controller (specifically: not bound to any Service in the `ingress-nginx` namespace, and not in any Service annotated with `kubernetes.io/ingress.class: nginx`). |
| `portCollision: false` | The target namespace either does not exist yet, or contains no Service of `type: LoadBalancer` already exposing ports 80/443 under a different release. |

On **any** collision, HALT with verdict `BLOCKED` and print remediation
guidance from `references/coexistence-checklist.md`. Do not write
`values.yaml` or `install.sh`.

The reference checklist also documents the post-install verification
commands the operator should run after they execute `install.sh`.

### Step 5 — Render values.yaml

Read `references/values-template.yaml`. Substitute these placeholders:

| Placeholder | Source |
|---|---|
| `${ENV}` | `inputs.env` |
| `${NAMESPACE}` | `inputs.namespace` |
| `${INGRESS_CLASS_NAME}` | `inputs.ingressClassName` |
| `${LB_IP}` | `inputs.lbIp` |
| `${GATEWAY_API_ENABLED}` | `inputs.gatewayApiEnabled` (string `true`/`false`) |

Write the result to `docs/reports/ingress-controller-install/<ISO_DATE>/values.yaml`.

The template is opinionated for coexistence:
- `ingressClass.name = ${INGRESS_CLASS_NAME}`, `isDefaultClass: false`
- `providers.kubernetesIngress.ingressClass = ${INGRESS_CLASS_NAME}`
- `providers.kubernetesIngress.publishedService.enabled: true`
- `providers.kubernetesGateway.enabled = ${GATEWAY_API_ENABLED}`
- `service.spec.loadBalancerIP = ${LB_IP}` (kept under a comment block
  noting the GCP `loadBalancerIP` deprecation; operators on newer clusters
  swap this for `service.annotations` instead)
- `ports.web` and `ports.websecure` keep upstream defaults (8000/8443
  internally, 80/443 externally — no conflict with ingress-nginx pods)

### Step 6 — Emit install.sh

Render the exact command. For NEW INSTALL:

```bash
#!/usr/bin/env bash
set -euo pipefail
helm repo add traefik https://traefik.github.io/charts
helm repo update traefik
helm install traefik traefik/traefik \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --version ${CHART_VERSION} \
  --values "$(dirname "$0")/values.yaml"
```

For UPGRADE:

```bash
#!/usr/bin/env bash
set -euo pipefail
helm repo update traefik
helm upgrade traefik traefik/traefik \
  --namespace ${NAMESPACE} \
  --version ${CHART_VERSION} \
  --reuse-values \
  --values "$(dirname "$0")/values.yaml"
```

Write to `docs/reports/ingress-controller-install/<ISO_DATE>/install.sh`
and `chmod +x` it. Record `plan.helmCommand` (the full one-liner) and
`plan.valuesPath` and `plan.postInstallChecks` in `state.yaml`.

### Step 7 — Verdict + HALT

Write `state.yaml.verdict`:

- `READY` — all validations passed, plan written. Print: "Run
  `bash docs/reports/ingress-controller-install/<ISO_DATE>/install.sh`
  when ready."
- `BLOCKED` — at least one validation failed. Plan files NOT written.
- `NEEDS_REVIEW` — major version bump, OR `existingClasses` includes
  unfamiliar entries, OR ArtifactHub was unreachable and operator pinned
  an unverified version. Plan files written, but require explicit
  operator sign-off.

**The skill never runs `helm` or `kubectl`.** Operator runs `install.sh`.

## State YAML schema

```yaml
inputs:
  env: dev | stg | prd
  namespace: "traefik"
  ingressClassName: "traefik"
  chartVersion: "<semver>"
  chartAppVersion: "<semver>"
  lbIp: "<ipv4 or gcp-address-name>"
  gatewayApiEnabled: false
detection:
  existingInstall: false
  currentVersion: null
  currentNamespace: null
  existingClasses: ["nginx"]
validation:
  classCollision: false
  ipCollision: false
  portCollision: false
plan:
  helmCommand: "helm install traefik traefik/traefik ..."
  valuesPath: "docs/reports/ingress-controller-install/<date>/values.yaml"
  postInstallChecks:
    - "kubectl -n traefik rollout status deploy/traefik"
    - "kubectl get ingressclass"
    - "kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
verdict: READY | BLOCKED | NEEDS_REVIEW
```

## Error Handling

- **Tool missing (Step 0)**: HALT. Verdict not written.
- **`helm list` fails (Step 1)**: Cannot determine install state. HALT with
  verdict `BLOCKED`, message "kubectl/helm context not reachable".
- **ArtifactHub unreachable (Step 3)**: Fall back to operator-provided
  version. Verdict becomes `NEEDS_REVIEW`.
- **Coexistence violation (Step 4)**: HALT. Verdict `BLOCKED`. Do not write
  `values.yaml` or `install.sh`. Print the specific failing check and the
  remediation row from `references/coexistence-checklist.md`.
- **Output directory already exists**: Append `-<HHMM>` suffix; never
  overwrite a prior run's `state.yaml`.

## Dry-Run Support

This skill is **inherently plan-only**. Every run is a dry run from the
cluster's perspective — no `helm` or `kubectl` mutations occur. The
operator chooses when (or whether) to execute `install.sh`.

## Dependencies

- `helm` ≥ 3.12
- `kubectl` with active context for the target cluster
- `yq` (Mike Farah's Go implementation) for the validation script
- `curl` for ArtifactHub queries
