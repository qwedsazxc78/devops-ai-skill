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
| *install-traefik | Install/upgrade Traefik controller with ingress-nginx coexistence checks (plan-only) |
| *decommission-nginx | Safe uninstall plan for ingress-nginx after migrations + DNS bake |

### Horus Skills

- `$helm-version-upgrade` — Helm chart version management
- `$terraform-validate` — Validation and linting
- `$terraform-security` — Security scanning
- `$cicd-enhancer` — CI/CD pipeline improvement
- `$helm-scaffold` — New module generation
- `$ingress-controller-install` — Plan-only Traefik Helm install with coexistence checks
- `$traefik-controller-decommission` — Plan-only ingress-nginx uninstall after migration

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

### Zeus Skills

- `$kustomize-resource-validation` — Kustomize build + validation
- `$yaml-fix-suggestions` — YAML formatting and validation
- `$repo-detect` — Repository type detection
- `$gateway-api-migration` — NGINX/Traefik Ingress → Gateway API migration
- `$nginx-to-traefik` — Class-swap NGINX Ingress to Traefik Ingress
- `$nginx-to-gateway` — Chained NGINX → Traefik → Gateway API migration
- `$ingress-migration-advisor` — Read-only planner for ingress-nginx EOL migration

### Shared Skills

- `$release-validate` — Release readiness validation (versions, cross-platform links, setup smoke tests)
