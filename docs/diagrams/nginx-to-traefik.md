# nginx-to-traefik — Class-Swap Migration to Traefik Ingress

The `*nginx-to-traefik` Zeus command (skill: `devops:nginx-to-traefik`, v1.0.0) ports a
batch of services from NGINX Ingress to Traefik Ingress (`ingressClassName: traefik`)
while **both controllers keep running in parallel** — DNS A-records are the only cutover
lever. It is the first half of the chained NGINX → Traefik → Gateway API migration: its
`state.yaml.outputs.traefikIngresses[]` is the hand-off contract consumed by
`nginx-to-gateway` / `gateway-api-migration --source-class traefik`.

```mermaid
flowchart TD
  A["*nginx-to-traefik [env] [batch|service] · --resume"] --> S0{"Step 0 · Tool check<br/>kustomize · yq · git"}
  S0 -- "tool missing" --> H["⛔ HALT — state.yaml verdict: HALTED<br/>(--resume re-runs from failed step)"]
  S0 --> S0b{"Step 0b · Env-config<br/>operator-declared LB IPs (5 prompts)"}
  S0b -- "operator declines" --> H
  S0b --> S1{"Step 1 · Inventory<br/>inventory_nginx_ingresses.py · ingressClass == nginx"}
  S1 -- "zero nginx Ingresses" --> H
  S1 --> S2{"Step 2 · Batch plan + y/N<br/>b1 read-mostly · b2 write-heavy"}
  S2 -- "operator declines" --> H
  S2 --> S3["Step 3 · Generate<br/>&lt;service&gt;-traefik-ingress.yaml + SHA256"]
  S3 -- "generator exit != 0" --> H
  S3 --> S4["Step 4 · git mv nginx file → archive/<br/>(never deleted)"]
  S4 -- "already under archive/" --> H
  S4 --> S5["Step 5 · kustomization.yaml<br/>add Traefik file to resources: · drop nginx from patches:"]
  S5 -- "schema mismatch" --> H
  S5 --> S6["Step 6 · common.traefik app.ingress.yaml<br/>managed-cert host list"]
  S6 --> S7{"Step 7 · kustomize build ×2<br/>common.service + common.traefik"}
  S7 -- "non-zero → git restore steps 4–6" --> H
  S7 --> S7b{"Step 7b · 4-way consistency<br/>DNS ↔ verify ↔ ingress ↔ cert"}
  S7b -- "non-zero exit" --> H
  S7b --> S8["Step 8 · dns-create-traefik.sh<br/>HOSTS_&lt;ENV&gt;_&lt;BATCH&gt; array (idempotent)"]
  S8 --> S9["Step 9 · verify-traefik-&lt;env&gt;.sh<br/>URLS_&lt;ENV&gt;_&lt;BATCH&gt; · https://&lt;host&gt;/"]
  S9 --> S10["Step 10 · Print file list + commit message<br/>never auto-commit"]
  S10 --> R["Operator: commit, then follow<br/>references/dns-cutover-runbook.md"]
```

**Key invariants:**

- Traefik Ingresses live in `kustomization.resources` — **never** patches; nginx files
  are `git mv`'d to `archive/` — **never** deleted.
- Backend Service names and `secretName` are written **verbatim** — Kustomize
  `namePrefix` does not touch them.
- LB IPs are **operator-declared only** (spec invariant §5.3) — never derived from any
  cluster resource. DNS A-records are the only cutover lever.
- The skill never auto-commits; state lives in
  `docs/reports/nginx-to-traefik/<slug>/state.yaml` (`<slug>` = `<env>-<batch>-<isodate>`),
  and `outputs.traefikIngresses[]` is the hand-off contract for `nginx-to-gateway`.

See [`skills/nginx-to-traefik/SKILL.md`](../../skills/nginx-to-traefik/SKILL.md) and the
[HTML drill-down](html/nginx-to-traefik/diagram.html).
