# gateway-api-migration — NGINX Ingress → Gateway API

The `*gateway-migrate` Zeus command (skill: `devops:gateway-api-migration`, v1.2.0) turns an
NGINX Ingress footprint (master/minion or standalone) into a side-by-side Gateway API
deployment so a per-hostname DNS cutover can proceed at the operator's pace. It is
dual-target — default Traefik (`GatewayClass=traefik`), opt-in GKE Gateway via
`--gateway-class gke-l7-*` — and every deterministic step is delegated to a bundled script
while the model interprets output and writes the report.

```mermaid
flowchart TD
  A["*gateway-migrate &lt;module-path&gt;"] --> B{"Step 0 · Tool check<br/>kustomize · yq · jq · kubectl · python3"}
  B -- "required tool missing" --> X1["⛔ HALT"]
  B -- "ok (kubeconform / ingress2gateway optional)" --> C{"Step 0b · Cluster preflight<br/>check_cluster_preflight.sh"}
  C -- "halts[] non-empty" --> X2["⛔ HALT — fix cluster, re-run"]
  C -- "warnings[] → risk register S2" --> D
  C -- "pass (or --offline)" --> D["Step 1 · Discover<br/>kustomize build each overlay →<br/>classify_ingress.py → pair_minions.py"]
  D -- "orphan minion / ambiguous pairing" --> X3["⛔ HALT — fix source config"]
  D -- "topology + pairs → state.yaml" --> E["Step 2 · Analyze<br/>inventory_annotations.py (3 buckets) ·<br/>backend resolution · overlay variance"]
  E --> F{"Proceed with conversion? [y/N]"}
  F -- "decline" --> X4["HALT — status: aborted"]
  F -- "confirm" --> G["Step 3A · Generate common.gateway/<br/>(write to .tmp dir → atomic rename)"]
  G -- "any failure → rm -rf tmp, repo clean" --> X5["⛔ HALT"]
  G --> H["Step 3B · HTTPRoutes + in-place<br/>kustomization.yaml edits<br/>(full-content backups first)"]
  H -- "kustomize build fails → restore backup,<br/>remove new files" --> X6["⛔ HALT — fix + --resume"]
  H --> I{"Step 4 · Validate<br/>4a build both modules · 4b kubeconform ·<br/>4c ingress2gateway diff · 4d 11 semantic checks"}
  I -- "4a or 4d fail" --> X7["⛔ HALT — files left in place,<br/>fix + --resume"]
  I -- "pass / warn (warns → risk register)" --> J["Step 5 · build_report.py<br/>state.yaml → report.md + verdict"]
  J --> K["Step 6 · Emit runbook<br/>common.gateway/MIGRATION.md"]
  K --> L["Step 7 · Pre-commit hints<br/>commit message + git add list —<br/>never auto-commit"]
```

**Key invariants:**

- **The master source is never modified.** `common.ingress/` is read-only; the skill only
  adds `*-httproute.yaml` files and makes idempotent in-place edits to
  `common.service/overlays/<env>/kustomization.yaml`.
- **Failures are recoverable.** Phase 3A writes to a temp dir and renames atomically;
  Phase 3B rollback restores from **full-content backups** under
  `docs/reports/gateway-migration/<slug>/backups/` (the SHA256 is tamper detection only).
- **Nothing is committed automatically.** The skill prints the commit message and file
  list; the operator drives git.
- **What Kustomize applies is what the skill analyzes.** Step 1 classifies
  `kustomize build` output, not raw files — avoiding false-positive orphan-minion halts
  from base-template placeholder hostnames and auto-excluding dead files.
- **Dual-target without magic.** Switching Traefik → GKE Gateway is a one-argument change
  (`--gateway-class`); provider policy CRDs (`Middleware` vs `GCPBackendPolicy`) are
  emitted only for target families the skill knows.

See [`skills/gateway-api-migration/SKILL.md`](../../skills/gateway-api-migration/SKILL.md)
and the [HTML drill-down](html/gateway-api-migration/diagram.html).
