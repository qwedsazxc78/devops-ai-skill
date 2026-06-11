# ingress-migration-advisor — Read-Only EOL Migration Planner

The `*ingress-migration-advisor` Zeus command (skill: `devops:ingress-migration-advisor`, v1.0.0)
inventories every Ingress in a Kustomize repo, scores each service on five migration-readiness
dimensions, and recommends one of four paths per service (direct-gateway, two-step, swap-only,
defer). It sits **upstream** of the three migration skills — it never invokes them and never
mutates the repo. Output is `plan.md` (Mermaid Gantt + per-service table + ready-to-paste Zeus
commands) plus `state.yaml` under `docs/reports/ingress-migration-advisor/<slug>/`.

```mermaid
flowchart TD
  A["*ingress-migration-advisor<br/>--deadline · --batch-size · --target-path"] --> B{"Step 0 · Tool check<br/>kustomize · yq · git · python3"}
  B -- "missing" --> X1["⛔ HALT — install hints"]
  B -- "ok" --> C{"Step 0b · Inputs<br/>deadline + batch size +<br/>docs/ingress-tier-map.yaml"}
  C -- "tier map missing<br/>or deadline in past" --> X1
  C -- "ok" --> D{"Step 1 · Inventory<br/>kustomize build every overlay<br/>classify rendered Ingresses"}
  D -- "zero Ingresses or<br/>all builds fail" --> X1
  D -- "ok" --> E["Step 2 · Score<br/>5 dimensions · total 4–14"]
  E --> F{"Step 3 · Decide path"}
  F -- "tier = critical" --> V["defer<br/>(critical-tier veto — no bypass flag)"]
  F -- "sourceClass = traefik" --> P1["direct-gateway<br/>(shortcut, score ignored)"]
  F -- "sourceClass = foreign<br/>(e.g. gce)" --> V2["defer<br/>(foreign-class)"]
  F -- "nginx · score 4–7" --> P1b["direct-gateway"]
  F -- "nginx · score 8–10" --> P2["two-step"]
  F -- "nginx · score 11–13" --> P3["swap-only"]
  F -- "nginx · score 14" --> V3["defer<br/>(very high risk)"]
  P1 & P1b & P2 & P3 --> G["Step 4 · Batch<br/>group by path + score ±2<br/>weekly cadence, fit deadline − bake buffer"]
  V & V2 & V3 --> H
  G --> I["Step 5 · Render plan.md<br/>Mermaid Gantt + decision table<br/>+ per-batch Zeus commands"]
  I --> H["state.yaml<br/>inputs · inventory · scores ·<br/>decisions · batches · deferred"]
  I --> J["Step 6 · Print summary<br/>never auto-commit"]
```

**Key invariants:**

- **Read-only.** No file mutations, no git operations, no DNS edits; `kustomize build`
  side-effects stay in `/tmp`. Re-running is always safe.
- **Critical-tier veto is policy, not a flag.** There is no `--force-critical` bypass —
  to migrate a critical service, the team PRs `docs/ingress-tier-map.yaml` first.
- **Recommendations, not commands.** The plan suggests copy-paste Zeus commands
  (`*gateway-migrate`, `*nginx-to-gateway`, `*nginx-to-traefik`); the operator runs each
  batch manually. The advisor never invokes the migration skills directly.
- **Plans age.** `--resume` only re-renders the report from existing state; it does NOT
  refresh inventory or scores. Re-run from scratch when the repo shifts.

See [`skills/ingress-migration-advisor/SKILL.md`](../../skills/ingress-migration-advisor/SKILL.md)
and the [HTML drill-down](html/ingress-migration-advisor/diagram.html).
