# traefik-controller-decommission — GitOps-Safe ingress-nginx Uninstall Planner

The `*decommission-nginx` Zeus command (skill: `devops:traefik-controller-decommission`) plans
the SAFE removal of the `ingress-nginx` controller in a Kustomize + ArgoCD repo. It verifies
cluster and repo are free of `ingressClassName: nginx` (precedence-aware: spec wins, legacy
annotation falls back), gates on a 72h DNS bake confirmation, then emits a **plan-only**
`commands.sh` — archive the module, disable the ArgoCD Application, wait for prune, optional
LB/IAM cleanup. It never runs `helm uninstall`; ArgoCD prunes the actual resources.

```mermaid
flowchart TD
  A["*decommission-nginx [--cycle|--module|--skip-dns-bake|--no-lb-cleanup|--resume]"] --> S0["Step 0 · Tool check<br/>kustomize · yq · git · jq required<br/>kubectl · gcloud optional (WARN)"]
  S0 -- "required tool missing" --> X0["⛔ HALT"]
  S0 --> S1{"Step 1 · Discover module<br/>discover_nginx_module.sh"}
  S1 -- "0 modules found" --> X1["⛔ HALT — nothing to decommission"]
  S1 -- ">1 modules found" --> X1b["⛔ HALT — ambiguous, use --module"]
  S1 -- "exactly 1" --> S2["Step 2 · Operator inputs<br/>date · operator · cycle slug · GCP project"]
  S2 --> S3{"Step 3 · Verify zero nginx Ingresses<br/>verify_no_nginx_class.sh --all<br/>cluster + repo scan"}
  S3 -- "exit 1 · nginx Ingress still active" --> X3["⛔ BLOCKED — commands.sh NOT written"]
  S3 -- "exit 2 · a scan could not run" --> W3["⚠ DEGRADED state recorded"]
  S3 -- "exit 0 · both scans clean" --> S4{"Step 4 · DNS bake gate<br/>cutover ≥ 72h ago? Traefik LB serving 200?<br/>zero traffic on nginx LB?"}
  W3 --> S4
  S4 -- "not yes" --> X4["⛔ BLOCKED"]
  S4 -- "--skip-dns-bake" --> N4["⚠ verdict becomes NEEDS_REVIEW"]
  S4 -- "yes" --> S5["Step 5 · Generate plan<br/>generate_decommission_plan.sh"]
  N4 --> S5
  S5 --> P1["5a · Archive module<br/>git mv common.ingress-nginx/ archive/"]
  S5 --> P2["5b · Disable ArgoCD app<br/>auto-sync off → prune sync → delete app"]
  S5 --> P3["5c · Optional LB IP release + IAM cleanup<br/>(skipped with --no-lb-cleanup)"]
  P1 & P2 & P3 --> S6["Step 6 · Render state.yaml + verify.json<br/>print verdict + next steps"]
  S6 --> V["Verdict: READY · BLOCKED · NEEDS_REVIEW · DEGRADED"]
```

**Key invariants:**

- **Never runs `helm uninstall` or `kubectl delete` directly** — ArgoCD prunes the
  controller's resources once the Application is disabled and the module is archived.
- **Plan-only output**: `commands.sh` is copy-paste-ready and NEVER auto-executed;
  the operator drives it block-by-block.
- **Precedence-aware nginx detection**: an Ingress counts as nginx when
  `spec.ingressClassName == "nginx"`, OR the spec field is null AND the legacy
  `kubernetes.io/ingress.class: nginx` annotation is present — spec always wins.
- **Touches only the ingress-nginx module** (`common.ingress-nginx/` or equivalent)
  plus its ArgoCD Application manifest; full-file backups before any edit.
- BLOCKED at Step 3 means `commands.sh` is not written at all — the operator must
  re-migrate or delete the stale nginx Ingress first.

See [`skills/traefik-controller-decommission/SKILL.md`](../../skills/traefik-controller-decommission/SKILL.md)
and the [HTML drill-down](html/traefik-controller-decommission/diagram.html).
