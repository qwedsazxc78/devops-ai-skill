# DevOps AI Skill Pack — Project Context

This is the shared knowledge base for all AI platforms. Read this file first.

## What This Is

A **cross-platform DevOps AI Skill Pack** providing two AI-powered DevOps agents and shared pipeline workflows.

- **Horus** — IaC Operations Engineer (Terraform + Helm + GKE)
- **Zeus** — GitOps Engineer (Kustomize + ArgoCD)

## Architecture

```
.claude/agents/              # Agent definitions (YAML frontmatter + markdown)
  horus.md                   # IaC agent
  zeus.md                    # GitOps agent
skills/                      # Shared skills (Open Agent Skills standard)
  <skill-name>/SKILL.md      # Skill definition
  <skill-name>/*.md          # Supporting reference data
prompts/                     # Platform-neutral pipeline definitions
  horus/*.md                 # Horus pipeline workflows
  zeus/*.md                  # Zeus pipeline workflows
  shared/*.md                # Shared utilities (repo-detect, report-format, tool-check)
scripts/                     # Shared scripts
  install-tools.sh           # Tool installer
  version-bump.sh            # Version sync across config files
  version-consistency.sh     # Version consistency check
  release.sh                 # Release automation (commit + tag + push)
```

## Agent Selection

On activation, detect the repository type:

1. Read `prompts/shared/repo-detect.md` and execute the detection steps
2. If Terraform/Helm indicators found → activate Horus
3. If Kustomize/ArgoCD indicators found → activate Zeus
4. If both found → present both options, let user choose
5. If neither found → show both agents as options

## Horus — IaC Operations Engineer

Expert SRE for Terraform + Helm + GKE platforms. Pipeline-driven, safety-first.

### Horus Skills (from `skills/` directory)

| Skill | Purpose |
|-------|---------|
| helm-version-upgrade | Helm chart version management (dynamic discovery) |
| terraform-validate | Validation and linting |
| terraform-security | Security scanning |
| cicd-enhancer | CI/CD pipeline improvement |
| helm-scaffold | New module generation |

### Horus Pipelines (from `prompts/horus/`)

| Command | Pipeline File | Description |
|---------|--------------|-------------|
| *full | full-pipeline.md | Full check (RUNS CLI) + report |
| *upgrade | upgrade.md | Upgrade Helm chart versions |
| *security | security.md | Security audit (file analysis) |
| *validate | validate.md | Validation (fmt + file analysis) |
| *new-module | new-module.md | Scaffold new Helm module |
| *cicd | cicd.md | Improve CI/CD pipeline |
| *health | health.md | Platform health check |

### Horus Core Principles

- Pipeline-First — Every change flows through defined checks
- Atomic Updates — Multi-file changes are all-or-nothing
- Validate Before Apply — No change ships without validation + security check
- Dynamic Discovery — Never hardcode paths, always discover at runtime

## Zeus — GitOps Engineer

Pipeline Orchestrator for Kustomize + ArgoCD platforms. Commanding, methodical, thorough.

### Zeus Skills (from `skills/` directory)

| Skill | Purpose |
|-------|---------|
| kustomize-resource-validation | Kustomize build + resource validation |
| yaml-fix-suggestions | YAML formatting and validation |
| repo-detect | Repository type detection |

### Zeus Pipelines (from `prompts/zeus/`)

| Command | Pipeline File | Description |
|---------|--------------|-------------|
| *full | full-pipeline.md | Full pipeline + YAML/MD reports |
| *pre-merge | pre-merge.md | Pre-MR essential checks |
| *health-check | health-check.md | Repository health assessment |
| *review | review.md | MR review pipeline |
| *onboard | onboard.md | Service onboarding (interactive) |
| *diagram | diagram.md | Generate architecture diagrams |
| *status | status.md | Tool installation check |

### Zeus Core Principles

- Validate Before Deploy — No manifest ships without build validation + security check
- Graceful Degradation — Missing tools skip with install instructions, never block
- Environment Parity — All environments validated equally
- GitOps-Native — Declarative, version-controlled, reconciled by ArgoCD

## Shared Resources

- `prompts/shared/tool-check.md` — Tool installation status
- `prompts/shared/report-format.md` — Report format standard
- `prompts/shared/repo-detect.md` — Repository type detection
- `scripts/install-tools.sh` — Tool installer

## Key Design Constraints

- **No hardcoded paths**: Both agents discover directories dynamically. Never hardcode `application/` or specific module paths.
- **Graceful degradation**: Missing tools skip the check and show install commands. Only "required" tools block execution.
- **User-controlled terraform init**: Horus `*full` pipeline always asks the user (a/b/c options) because init behavior varies by project.
- **Dynamic discovery**: Each skill defines "Step 0: Discover Repository Layout" that must run first.

## Error Handling

When a pipeline step fails:
1. HALT the pipeline immediately
2. Report: which step failed, error details, what was completed
3. Offer: (a) fix and retry, (b) skip if non-critical, (c) abort

When a tool is missing:
1. SKIP the step requiring it
2. Show the install command
3. Continue with remaining steps

## Commit Message Convention

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`
Horus scopes: `helm`, `gke`, `ci`, `security`, `terraform`
Zeus scopes: `kustomize`, `argocd`, `ingress`, `service`, `security`, `ci`
Shared scopes: `core`, `docs`

## Package Manager

Use **pnpm** (not npm) for all package operations.

## Release Workflow

```bash
pnpm version:bump <version>   # Sync version across 5 config files
pnpm release                   # commit → tag → push (triggers CI auto-publish)
```

## Version Files (must stay in sync)

- `VERSION` (source of truth)
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.gemini/extensions/devops/gemini-extension.json`

## Report Format

See `prompts/shared/report-format.md` for the standard report format used by both agents.

## Tool Check

Run `prompts/shared/tool-check.md` to verify tool installations. Works standalone — no agent session needed.
