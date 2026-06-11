# nginx-ingress-retire — Post-Migration Nginx Retirement

The `*retire-nginx` Zeus command (skill: `devops:nginx-ingress-retire`, v1.17.0) removes
the nginx controller ArgoCD app and excludes base nginx Ingress resources per env —
**after** Gateway API / Traefik migration is complete. Safety-gated: it refuses to run
when no replacement routing (HTTPRoute / Traefik Ingress) exists.

```mermaid
flowchart TD
  A["*retire-nginx dev|stg|prd|all"] --> B{"Step 2 · Pre-flight<br/>kustomize build + inventory"}
  B -- "build fails" --> X1["⛔ Hard abort"]
  B -- "nginx > 0 · no replacements" --> X1
  B -- "nginx = 0 · no replacements" --> X1
  B -- "already retired<br/>(replacements exist)" --> W["⚠ Soft warn + confirm"]
  B -- "OK" --> C["Step 3 · Discovery<br/>controller app · base Ingress names · orphans · archive/"]
  W --> C
  C --> D{"Step 4 · Removal plan<br/>+ operator confirm"}
  D -- "no" --> X2["Abort — nothing touched"]
  D -- "yes" --> E["Step 5 · Execute"]
  E --> E1["rm common.ingress/argocd/&lt;env&gt;.yaml<br/>(app-of-apps prune → finalizer cascade)"]
  E --> E2["$patch: delete in overlay kustomization<br/>(base files stay for other envs)"]
  E --> E3["rm orphans + archive/"]
  E1 & E2 & E3 --> F{"Step 6 · Validate"}
  F -- "nginx-class > 0" --> X3["🛑 Halt — no commit"]
  F -- "other env build fails" --> X3
  F -- "pass" --> G["Step 8 · Summary report<br/>+ commit message"]
  G -- "after 'all'" --> H["Step 7 · Module cleanup check<br/>archive common.ingress/ entirely"]
```

**Key invariants:**

- Validates `ingress.class: nginx` count = 0, **not** total `kind: Ingress` count —
  Traefik Ingresses legitimately remain.
- `$patch: delete` targets the **un-prefixed** resource name (Kustomize applies
  patches before `namePrefix`).
- Class-override patches (e.g. `ingress.class: gce`) are detected via rendered-manifest
  cross-check and **never** deleted — only the file is renamed, never `metadata.name`
  (renaming the resource would reprovision the cloud LB).

See [`skills/nginx-ingress-retire/SKILL.md`](../../skills/nginx-ingress-retire/SKILL.md),
the [HTML drill-down](html/retire-nginx/diagram.html), and the
[mindmap explainer](html/retire-nginx/mindmap.html).
