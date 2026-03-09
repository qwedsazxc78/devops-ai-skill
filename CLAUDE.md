# CLAUDE.md

This file provides guidance to Claude Code when working with this DevOps AI Skill Pack.

## What This Is

A **cross-platform DevOps AI Skill Pack** providing two AI-powered DevOps agents and shared pipeline workflows. Works with Claude Code, OpenAI Codex CLI, and Google Gemini CLI.

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
```

## Agent Selection

On activation, detect the repository type:

1. Read `prompts/shared/repo-detect.md` and execute the detection steps
2. If Terraform/Helm indicators found → activate Horus (`.claude/agents/horus.md`)
3. If Kustomize/ArgoCD indicators found → activate Zeus (`.claude/agents/zeus.md`)
4. If both found → present both options, let user choose
5. If neither found → show both agents as options

## Using Agents

### Horus (IaC)

When Horus is active, available pipelines are defined in `prompts/horus/`:

| Command | Pipeline File | Description |
|---------|--------------|-------------|
| *full | full-pipeline.md | Full check (RUNS CLI) + report |
| *upgrade | upgrade.md | Upgrade Helm chart versions |
| *security | security.md | Security audit (file analysis) |
| *validate | validate.md | Validation (fmt + file analysis) |
| *new-module | new-module.md | Scaffold new Helm module |
| *cicd | cicd.md | Improve CI/CD pipeline |
| *health | health.md | Platform health check |

### Zeus (GitOps)

When Zeus is active, available pipelines are defined in `prompts/zeus/`:

| Command | Pipeline File | Description |
|---------|--------------|-------------|
| *full | full-pipeline.md | Full pipeline + YAML/MD reports |
| *pre-merge | pre-merge.md | Pre-MR essential checks |
| *health-check | health-check.md | Repository health assessment |
| *review | review.md | MR review pipeline |
| *onboard | onboard.md | Service onboarding (interactive) |
| *diagram | diagram.md | Generate architecture diagrams |
| *status | status.md | Tool installation check |

## Key Design Constraints

- **No hardcoded paths**: Both agents discover directories dynamically. Never hardcode `application/` or specific module paths.
- **Graceful degradation**: Missing tools skip the check and show install commands. Only "required" tools block execution.
- **User-controlled terraform init**: Horus `*full` pipeline always asks the user (a/b/c options) because init behavior varies by project.
- **Dynamic discovery**: Each skill defines "Step 0: Discover Repository Layout" that must run first.

## Commit Message Convention

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`
Horus scopes: `helm`, `gke`, `ci`, `security`, `terraform`
Zeus scopes: `kustomize`, `argocd`, `ingress`, `service`, `security`, `ci`

## Report Format

See `prompts/shared/report-format.md` for the standard report format used by both agents.

## Tool Check

Run `prompts/shared/tool-check.md` to verify tool installations. Works standalone — no agent session needed.
