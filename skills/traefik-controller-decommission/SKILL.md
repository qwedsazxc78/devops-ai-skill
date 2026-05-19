---
name: traefik-controller-decommission
description: >
  SAFE uninstall of the `ingress-nginx` controller after every Ingress has been
  migrated to Traefik (or Gateway API) and DNS has been cut over. Verifies
  cluster + repo are free of `ingressClassName: nginx`, confirms the DNS bake
  period elapsed, then generates a print-only Helm uninstall + LB IP release +
  IAM cleanup plan. Use when retiring nginx-ingress after migrations complete.
version: "1.0.0"
---

# Traefik Controller Decommission Skill

## Purpose

Final-stage skill for the nginx-to-traefik migration arc. After every
`Ingress` has been re-classed (or replaced with a Gateway API `HTTPRoute`) and
the operator has held a bake period on the new LB, this skill performs the
**decommission checklist**: it proves nginx has no remaining consumers in
either the live cluster or the GitOps source tree, then **prints** the exact
commands the operator must run to remove the controller.

This is a **read-mostly verification + plan-generation** skill, modeled on
`terraform-security` (audit) and `helm-version-upgrade` (plan-then-apply). It
never invokes `helm uninstall`, never deletes a Kubernetes resource, never
releases a cloud LB. Every destructive action is rendered as a copy-paste
block in `commands.sh` for the operator.

## Activation

This skill activates when the user requests:
- Decommissioning the `ingress-nginx` controller
- Removing the old nginx LB IP after a Traefik cutover
- A final pre-uninstall safety check before `helm uninstall nginx-ingress`
- The `*decommission-nginx` Horus pipeline

## Inputs

The pipeline driver (`prompts/horus/decommission-nginx-controller.md`)
collects these inputs and passes them as a state object:

| Field | Source | Notes |
|---|---|---|
| `date` | operator confirm | ISO date (`YYYY-MM-DD`) — names the report dir |
| `operator` | operator confirm | Free text (name / handle) for audit trail |
| `migrationCycle` | operator confirm | Slug of the migration this completes, e.g. `prod-batch-3` |
| `helmRelease` | discovered | `helm list -A` row for the nginx controller |
| `helmNamespace` | discovered | Namespace of the release (typically `ingress-nginx`) |
| `nginxLbIp` | discovered | LB IP currently bound to the nginx Service |
| `gcpProject` | operator confirm | Required for LB / IAM cleanup plan rendering |

If `kubectl` / `helm` / `gcloud` are unavailable, the skill MUST still produce
a plan — falling back to placeholder values surrounded by `<TODO:...>`
markers that the operator fills in before running `commands.sh`.

## Step 0: Discover Repository Layout

**Do NOT assume any hardcoded file names or paths.** Discover the relevant
files at runtime so the skill works across `gitops-*` repos:

### 0a: Find Kustomize Overlay Roots
```bash
find . -name 'kustomization.yaml' -not -path '*/archive/*' -not -path '*/.git/*'
```
Each match is an overlay candidate for the `kustomize-build` scan in Step 1b.

### 0b: Find Any nginx Ingress Source Files
```bash
grep -rl 'ingressClassName:[[:space:]]*nginx\|kubernetes.io/ingress.class:[[:space:]]*"\?nginx' \
  --include='*.yaml' --include='*.yml' . | grep -v '/.git/'
```
Store as `<nginx-source-files>`. Each path is then classified in Step 2 as
either `archived` (under any `archive/` directory) or `active` (anywhere else).

### 0c: Find Helm Release Definitions for nginx
```bash
helm list -A -o json 2>/dev/null \
  | jq -r '.[] | select(.chart | test("ingress-nginx")) | "\(.namespace)\t\(.name)\t\(.chart)"'
```
If `helm` is unreachable, fall back to:
```bash
grep -rl 'chart:[[:space:]]*ingress-nginx\|repository:.*kubernetes.github.io/ingress-nginx' \
  --include='*.tf' --include='*.yaml' .
```
The Terraform variant matters when the controller is owned by the IaC
repo rather than ArgoCD.

## Workflow

### Step 1: Verify Zero Active nginx Ingresses

This is the hardest gate. We scan from **both directions**: live cluster and
source repo. Both must be empty for the verdict to advance.

#### Step 1a: Cluster scan (`scripts/verify_no_nginx_class.sh --cluster`)
```bash
kubectl get ingress -A -o json \
  | jq -r '.items[] | select(.spec.ingressClassName=="nginx" or
           (.metadata.annotations["kubernetes.io/ingress.class"]=="nginx"))
           | "\(.metadata.namespace)/\(.metadata.name)"'
```
- **0 rows** → cluster gate passes.
- **>0 rows** → verdict is `BLOCKED`. Report each Ingress with namespace/name
  and HALT. The operator must either re-migrate the leftover or delete the
  stale Ingress before retrying.

#### Step 1b: Repo scan (`scripts/verify_no_nginx_class.sh --repo`)
For every overlay discovered in Step 0a, run:
```bash
kustomize build "$overlay" 2>/dev/null \
  | yq -r 'select(.kind=="Ingress") | .spec.ingressClassName' \
  | grep -cx 'nginx'
```
Sum across overlays. Any count >0 means the GitOps source still emits an
nginx Ingress that ArgoCD will recreate after the controller is removed —
verdict is `BLOCKED`.

### Step 2: Verify nginx YAML Files Are Archived

For each file from Step 0b, classify it:

| Path pattern | Status |
|---|---|
| `**/archive/**` | OK — file is parked, no overlay references it |
| Anywhere else | BAD — file is still active in the tree |

For every BAD file, additionally verify it is **NOT** listed in any
`kustomization.resources[]`:
```bash
grep -rE "(^|/)$(basename "$f")$" \
  --include='kustomization.yaml' .
```
Any match means the overlay still composes this file. Verdict is `BLOCKED`
and the operator must move the file under `archive/` first.

### Step 3: DNS Bake-Period Confirmation

There is no programmatic way to prove "all caches have flushed". This step
is an **interactive operator confirmation**, recorded in the state YAML:

```
Did the DNS cutover for cycle <migrationCycle> happen at least 72h ago?
Has every monitored hostname returned HTTP 200 via the Traefik LB for that
window with zero traffic on the nginx LB?
[yes/no]
```

- `yes` → set `verification.dnsBakeConfirmed: true`, record operator + ISO
  timestamp, continue.
- `no` (or any other input) → verdict is `BLOCKED`. Print the suggested
  hold time and exit. Do not write `commands.sh`.

### Step 4: Generate Decommission Plan

Run `scripts/generate_uninstall_plan.sh` with the inputs from Steps 0–3.
The script emits three sections, each rendered into `plan.md` AND into
`commands.sh` as commented, copy-paste-ready blocks.

#### 4a: Helm Uninstall Plan (`plan.helmUninstall`)
```bash
# Confirm release still present (idempotency guard)
helm status <release> -n <namespace>

# Take a values snapshot for audit trail
helm get values <release> -n <namespace> -o yaml \
  > docs/reports/traefik-controller-decommission/<date>/nginx-values-snapshot.yaml

# Uninstall (--wait blocks until resources are reaped)
helm uninstall <release> -n <namespace> --wait

# Drop the namespace if no other workloads occupy it
kubectl get all -n <namespace>
kubectl delete namespace <namespace>   # only after confirming the above is empty
```

#### 4b: LB IP Release Plan (`plan.lbRelease`)
GKE-specific cleanup of the L4 backend the nginx Service used:
```bash
# Static address (if reserved) — only release once no forwarding rule references it
gcloud compute addresses list --project <gcpProject> \
  --filter="address=<nginxLbIp>"
gcloud compute addresses delete <address-name> \
  --region <region> --project <gcpProject>

# Orphaned forwarding rule / target pool (Service type=LoadBalancer remnants)
gcloud compute forwarding-rules list --project <gcpProject> \
  --filter="IPAddress=<nginxLbIp>"
gcloud compute target-pools list --project <gcpProject>
```
The plan stays **discovery-first**: it lists, then optionally deletes. Every
`delete` is preceded by the `list` that proves the resource is orphaned.

#### 4c: IAM Cleanup Plan (`plan.iamCleanup`)
The nginx controller typically runs under a dedicated Workload-Identity
service account. The plan enumerates SAs that match common naming patterns
and prints `gcloud` removal commands:
```bash
# Find candidates
gcloud iam service-accounts list --project <gcpProject> \
  --filter="email~ingress-nginx"

# For each candidate, list bindings before deletion
gcloud projects get-iam-policy <gcpProject> \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:<sa-email>"

# Remove bindings, then the SA itself
gcloud projects remove-iam-policy-binding <gcpProject> \
  --member=serviceAccount:<sa-email> --role=<role>
gcloud iam service-accounts delete <sa-email> --project <gcpProject>
```

### Step 5: Render Output Artifacts

Write all three artifacts to
`docs/reports/traefik-controller-decommission/<date>/`:

| File | Purpose |
|---|---|
| `verify.json` | Machine-readable verification results from Steps 1–3 |
| `plan.md` | Operator-readable decommission plan (Steps 4a–4c) |
| `commands.sh` | Bash script the operator runs **manually** |
| `state.yaml` | Full state object (see schema below) |

`commands.sh` MUST start with:
```bash
#!/usr/bin/env bash
# Generated by traefik-controller-decommission skill on <date>
# Operator: <operator>   Cycle: <migrationCycle>
# THIS SCRIPT IS NOT AUTO-EXECUTED. Read every block, then run by hand.
set -euo pipefail
```
…and MUST NOT chain to a real uninstall in any branch. The skill is plan-only.

### Step 6: Print Commit Message + Manual Commands

Generate a Conventional Commits message for the report itself:
```
chore(decommission): record nginx-ingress decommission plan for <migrationCycle>

- Verified 0 active nginx Ingresses (cluster + repo)
- Verified all nginx YAML files archived
- DNS bake confirmed by <operator>
- Plan: docs/reports/traefik-controller-decommission/<date>/plan.md
```

Then echo the operator next steps:
```
1. Review docs/reports/traefik-controller-decommission/<date>/plan.md
2. Execute commands.sh block-by-block (NOT in one shot)
3. Commit the report directory once uninstall is complete
```

## State YAML Schema

```yaml
inputs:
  date: "2026-05-19"
  operator: "alex.hsieh"
  migrationCycle: "prod-batch-3"
verification:
  activeNginxIngresses:
    cluster: []        # list of "<namespace>/<name>"
    repo: []           # list of overlay paths still emitting nginx
  nonArchivedFiles: [] # list of file paths violating Step 2
  dnsBakeConfirmed:
    confirmed: true
    confirmedBy: "alex.hsieh"
    confirmedAt: "2026-05-19T10:14:00Z"
plan:
  helmUninstall:
    release: "nginx-ingress"
    namespace: "ingress-nginx"
    snapshotPath: "docs/reports/.../nginx-values-snapshot.yaml"
  lbRelease:
    nginxLbIp: "34.x.x.x"
    addressName: "ingress-nginx-lb"
    region: "asia-east1"
  iamCleanup:
    serviceAccounts:
      - email: "ingress-nginx@<project>.iam.gserviceaccount.com"
        bindings: ["roles/container.viewer"]
verdict: READY  # READY | BLOCKED | NEEDS_REVIEW
```

## Verdict Logic

- `READY` — all Step 1 checks return zero, all Step 2 files archived, Step 3
  confirmed `yes`. `commands.sh` is written.
- `BLOCKED` — any gate failed. `commands.sh` is **NOT** written. `verify.json`
  + `plan.md` are written with the blocking findings highlighted.
- `NEEDS_REVIEW` — discovery hit an ambiguous case (e.g. multiple Helm
  releases match `ingress-nginx`, or a YAML file is under `archive/` but a
  `kustomization.yaml` still references it). The plan is rendered but the
  operator must reconcile the ambiguity before running it.

## HALT Conditions (hard stops)

1. Any active `ingressClassName: nginx` Ingress in the live cluster.
2. Any active nginx Ingress in `kustomize build` output for any overlay.
3. Any non-archived `*-nginx-ingress.yaml` referenced from a
   `kustomization.resources[]`.
4. Operator declines (or skips) the DNS-bake confirmation.
5. `helm list` returns >1 release matching `ingress-nginx` (ambiguous — set
   verdict `NEEDS_REVIEW` and let the operator pick).

## Error Handling

### Discovery Failures
- **`kubectl` unavailable**: Cluster scan in Step 1a cannot run. Verdict is
  `NEEDS_REVIEW` — the repo gate alone is insufficient.
- **`helm` unavailable**: Fall back to grep-based discovery (Step 0c). Note
  in `state.yaml` that the Helm release was inferred from source.
- **No overlays found in Step 0a**: This is not a GitOps repo. Skill exits
  with verdict `NEEDS_REVIEW` and a note that the IaC-owned controller path
  is unsupported in v1.0.0.

### Tool Failures
- **`kustomize build` fails on one overlay**: Record the failure, continue
  with other overlays, mark `verdict: NEEDS_REVIEW` so the operator inspects
  the broken overlay before uninstalling.
- **`gcloud` unavailable**: Render the LB + IAM plans with the literal
  placeholder `<TODO: run from a host with gcloud>` so the operator knows to
  fill in real resource names later.

## Dry-Run Support

This skill is **plan-only by default** — there is no "live" mode. The only
mutation is writing the report directory. Every command in `commands.sh` is
executed by the operator, never by the skill.

## Rollback Strategy

The skill itself writes nothing destructive — rollback is a `git checkout`
of `docs/reports/traefik-controller-decommission/<date>/`.

For the operator-executed uninstall, the rollback path is documented in
`references/decommission-checklist.md` (re-install the chart from the values
snapshot captured in Step 4a).

## Dependencies

- `references/decommission-checklist.md` — Operator-facing manual checklist
- `scripts/verify_no_nginx_class.sh` — Cluster + repo nginx-class scanner
- `scripts/generate_uninstall_plan.sh` — Plan + commands.sh emitter
