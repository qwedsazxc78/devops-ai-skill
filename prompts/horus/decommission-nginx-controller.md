# decommission-nginx-controller Pipeline

Final-stage pipeline for the nginx → traefik migration arc. Verifies the
cluster + repo are free of `ingressClassName: nginx`, confirms the DNS
bake period elapsed, then generates a **print-only** Helm uninstall + LB
IP release + IAM cleanup plan. Never executes destructive commands.

Delegates all logic to the `traefik-controller-decommission` skill.

## When to use

After every Ingress has been migrated to Traefik (or Gateway API) AND a
bake period has elapsed during which the Traefik LB served 100% of
traffic. This pipeline is the "kill the old controller" final step.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kubectl`, `helm`, `kustomize`, `yq`, `jq`, `gcloud` (last is
  WARN-only — required for full LB/IAM plan, not for the verify gates)
- Gate: HALT on any of the first 5 missing

### Step 2: Operator Inputs

- Invoke skill Step 0 (discovery) + collect: ISO date, operator handle,
  migration cycle slug, GCP project, expected Helm release name
- Suggest defaults from `helm list -A`
- Gate: HALT if release name unresolved AND operator declines to type one

### Step 3: Verify Zero Active nginx Ingresses

- Invoke skill Step 1 via `scripts/verify_no_nginx_class.sh --all`
- Script exits 1 (BLOCKED) on ANY active nginx Ingress in cluster OR repo
- Gate: HALT on exit 1; record findings in `verify.json`

### Step 4: Verify nginx YAML Files Archived

- Invoke skill Step 2
- Scan repo for `*-nginx-ingress.yaml` files NOT under `archive/`
- For each non-archived file, check no `kustomization.resources[]`
  references it
- Gate: HALT on any active reference

### Step 5: DNS Bake Confirmation

- Invoke skill Step 3
- Interactive prompt: "Did the DNS cutover for <cycle> happen at least
  72h ago? Has every monitored hostname returned HTTP 200 via the Traefik
  LB during that window with zero traffic on the nginx LB? [yes/no]"
- Gate: HALT on any answer other than `yes`

### Step 6: Generate Decommission Plan

- Invoke skill Step 4 via `scripts/generate_uninstall_plan.sh`
- Set env vars: `HELM_RELEASE`, `HELM_NAMESPACE`, `NGINX_LB_IP`,
  `GCP_PROJECT`, `REPORT_DIR`
- Plan covers: Helm uninstall, LB IP release, IAM cleanup
- Writes `plan.md` + `commands.sh` to the report dir

### Step 7: Render State + Print Summary

- Invoke skill Step 5 + 6
- Write `state.yaml`, `verify.json` to report dir
- Print verdict + next-step instructions
- Never auto-commit; never execute `commands.sh`

## Invocation Reference

```
*decommission-nginx                              # interactive
*decommission-nginx --cycle prod-batch-3         # named cycle
*decommission-nginx --skip-dns-bake              # NOT recommended; emits NEEDS_REVIEW
*decommission-nginx --resume <state-path>        # re-render from existing state
```

## Output Artifacts

Under `docs/reports/traefik-controller-decommission/<date>/`:

- `state.yaml` — machine-readable state (verifications, plan, verdict)
- `verify.json` — Step 3/4 raw scan results
- `plan.md` — operator-readable plan (3 sections)
- `commands.sh` — copy-paste-ready bash (NEVER auto-executed)

## Verdict outcomes

- `READY` — all gates passed; `commands.sh` written
- `BLOCKED` — any verification gate failed; `commands.sh` **NOT** written
- `NEEDS_REVIEW` — discovery ambiguous (multi-release match, kubectl
  unreachable, kustomize build failures); plan written but explicit
  operator sign-off required
