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

## Horus Skills

- `$helm-version-upgrade` — Helm chart version management
- `$terraform-validate` — Validation and linting
- `$terraform-security` — Security scanning
- `$cicd-enhancer` — CI/CD pipeline improvement
- `$helm-scaffold` — New module generation

## Zeus Skills

- `$kustomize-resource-validation` — Kustomize build + validation
- `$yaml-fix-suggestions` — YAML formatting and validation
- `$repo-detect` — Repository type detection
