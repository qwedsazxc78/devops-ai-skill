# AGENTS.md (OpenAI Codex CLI)

Read `docs/PROJECT.md` first — it contains all shared project context.

## Codex Specifics

- Skills are in `skills/` directory — each has `SKILL.md` with workflow steps
- Pipelines are in `prompts/horus/` and `prompts/zeus/`
- Use `!cmd` for bash execution

## Agent Selection

Detect the repository type to choose the right agent:

- For **Terraform, Helm, GKE** → follow Horus workflows from `prompts/horus/`
- For **Kustomize, ArgoCD, GitOps** → follow Zeus workflows from `prompts/zeus/`
- **Unsure** → run detection logic from `prompts/shared/repo-detect.md`

## Horus Commands (IaC — Terraform + Helm + GKE)

| Command | Pipeline |
|---------|----------|
| *full | Full check (RUNS CLI) + report |
| *upgrade | Upgrade Helm chart versions |
| *security | Security audit (file analysis) |
| *validate | Validation (fmt + file analysis) |
| *scaffold | Scaffold new Helm module |
| *cicd | Improve CI/CD pipeline |
| *health | Platform health check |

### Horus Skills

- `$helm-version-upgrade` — Helm chart version management
- `$terraform-validate` — Validation and linting
- `$terraform-security` — Security scanning
- `$cicd-enhancer` — CI/CD pipeline improvement
- `$helm-scaffold` — New module generation

## Zeus Commands (GitOps — Kustomize + ArgoCD)

| Command | Pipeline |
|---------|----------|
| *full | Full pipeline + YAML/MD reports |
| *pre-merge | Pre-MR essential checks |
| *health | Repository health assessment |
| *review | MR review pipeline |
| *scaffold | Service scaffold (interactive) |
| *diagram | Generate architecture diagrams |
| *status | Tool installation check |
| *gateway-migrate | Migrate NGINX Ingress to Gateway API (default Traefik, opt-in GKE via `--gateway-class gke-l7-*`) — per-hostname DNS cutover |
| *nginx-to-traefik | `prompts/zeus/nginx-to-traefik.md` |
| *nginx-to-gateway | `prompts/zeus/nginx-to-gateway.md` |
| *ingress-to-gateway | Auto-detect source class (nginx/traefik) then migrate to Gateway API |
| *ingress-migration-advisor | Read-only EOL planner: scores services and recommends a migration path per service |
| *install-traefik | GitOps-flavored Traefik bootstrap/new-env/upgrade — edits common.traefik/, plan-only |
| *decommission-nginx | GitOps-flavored ingress-nginx decommission — archives module + ArgoCD prune, plan-only |
| *migration-quickstart | 30-second orientation: decision tree + 5-command table + sample invocations (no scan, no prompts) |

### Zeus Skills

- `$kustomize-resource-validation` — Kustomize build + validation
- `$yaml-fix-suggestions` — YAML formatting and validation
- `$repo-detect` — Repository type detection
- `$gateway-api-migration` — NGINX/Traefik Ingress → Gateway API migration
- `$nginx-to-traefik` — Class-swap NGINX Ingress to Traefik Ingress
- `$nginx-to-gateway` — Chained NGINX → Traefik → Gateway API migration
- `$ingress-migration-advisor` — Read-only planner for ingress-nginx EOL migration
- `$ingress-controller-install` — GitOps Traefik install/upgrade via Kustomize edits
- `$traefik-controller-decommission` — GitOps ingress-nginx decommission via module archive + ArgoCD prune

### Shared Skills

- `$release-validate` — Release readiness validation (versions, cross-platform links, setup smoke tests)
- `$painter` — Draw architecture/flow diagrams as a polished HTML artifact (blue-white tech style, card layout, SVG arrows). `--level basic|detailed` (clickable drill-down) + `--parallel` multi-agent scanning
