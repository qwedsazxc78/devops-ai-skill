# ⚡ DevOps AI Skill Pack

[![npm version](https://img.shields.io/npm/v/devops-ai-skill?style=flat-square&color=cb3837)](https://www.npmjs.com/package/devops-ai-skill)
[![GitHub Release](https://img.shields.io/github/v/release/qwedsazxc78/devops-ai-skill?style=flat-square&color=2ea44f)](https://github.com/qwedsazxc78/devops-ai-skill/releases)
[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#project-structure)
[![SKILLS](https://img.shields.io/badge/SKILLS-8-blueviolet?style=flat-square)](#skills)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-14-ff6f61?style=flat-square)](#horus-pipelines-iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agents)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-4-teal?style=flat-square)](#platform-support)

> Cross-platform DevOps AI Skill Pack — two AI-powered DevOps agents and shared pipeline workflows for **Claude Code**, **OpenAI Codex CLI**, **Google Gemini CLI**, and **Google Antigravity**.

🚀 [Quick Start](#quick-start) · 🤖 [Agents](#agents) · 🔧 [Tool Installation](#tool-installation) · 🛠️ [Skills](#skills) · 📖 [Setup Guide](setup.md) · ⚡ [5-Min Guide](quick-start.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

[繁體中文](../README.md) | [English](README.en.md) | [简体中文](README.zh-CN.md)

---

## Agents

| Agent | Focus | Platforms |
|-------|-------|-----------|
| **Horus** — IaC Operations Engineer | Terraform + Helm + GKE | All |
| **Zeus** — GitOps Engineer | Kustomize + ArgoCD | All |

## Quick Start

### Global Install (recommended)

Install once, available across ALL projects:

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh          # Auto-detect installed CLIs
```

Auto-detects Claude Code / Codex CLI / Gemini CLI / Antigravity and installs to their global config paths.

> 🆕 **New here?** Check out the [5-minute quick start guide](quick-start.md) — zero prior knowledge required!

<details>
<summary><strong>Global Install Options</strong></summary>

```bash
bash scripts/install-global.sh --all          # Force all platforms
bash scripts/install-global.sh --claude       # Claude Code only
bash scripts/install-global.sh --gemini       # Gemini CLI only
bash scripts/install-global.sh --status       # Check install status
bash scripts/install-global.sh --uninstall    # Remove global installs
```

</details>

<details>
<summary><strong>Updating Installed Skills</strong></summary>

```bash
cd devops-ai-skill
git pull origin main                          # Pull latest
bash scripts/install-global.sh                # Re-run (skips unchanged files)
```

> Re-run `install-global.sh` after updating source files to sync changes to all platforms.

</details>

<details>
<summary><strong>Per-repo Install (legacy)</strong></summary>

Run from your project root:

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
bash devops-ai-skill/scripts/setup.sh --all    # Install all platforms
bash devops-ai-skill/scripts/setup.sh          # Or interactive selection
```

```bash
bash devops-ai-skill/scripts/setup.sh --claude
bash devops-ai-skill/scripts/setup.sh --codex
bash devops-ai-skill/scripts/setup.sh --gemini
bash devops-ai-skill/scripts/setup.sh --antigravity
bash devops-ai-skill/scripts/setup.sh --uninstall
```

</details>

<details>
<summary><strong>Marketplace (Claude Code only)</strong></summary>

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
```

</details>

<details>
<summary><strong>Cross-Platform (npx skills) — Skills only</strong></summary>

```bash
# Auto-detects installed AI agents and routes skills accordingly
npx skills add qwedsazxc78/devops-ai-skill

# Update
npx skills update
```

> **⚠️ Note: This method installs only the 8 Skills (SKILL.md), not the full pack:**
>
> | Feature | npx skills | Global Install |
> |---------|:----------:|:--------------:|
> | 8 Skills (SKILL.md) | ✅ | ✅ |
> | 2 Agents (Horus / Zeus) | ❌ | ✅ |
> | 14 Pipelines (`*full`, `*security`, etc.) | ❌ | ✅ |
> | Command palette (Gemini CLI) | ❌ | ✅ |
> | Workflows (Antigravity) | ❌ | ✅ |
>
> For the full experience, use **Global Install** or **Marketplace** above.

</details>

## Platform Support

| Feature | Claude Code | OpenAI Codex | Gemini CLI | Antigravity |
|---------|-------------|--------------|------------|-------------|
| Global Agents | `~/.claude/agents/` | `~/.codex/instructions.md` | `~/.gemini/agents/` | `~/.agents/skills/` |
| Global Skills | `~/.claude/skills/` | `~/.codex/skills/` | `~/.gemini/skills/` | shared `~/.gemini/skills/` |
| Command palette | — | — | `~/.gemini/commands/devops/` | — |
| Workflows | — | — | — | `~/.agents/workflows/` |
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `.agents/rules/` |
| Skills format | SKILL.md (native) | SKILL.md (native) | SKILL.md (native) | SKILL.md (native) |
| Pipeline trigger | `*cmd` | `*cmd` | command palette `devops:` | `/workflow-name` |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) | Yes |

## Tool Installation

One-command installer supporting macOS (Homebrew), Linux (apt/snap), Windows (winget/choco/scoop), and Python (uv/pip):

```bash
# Interactive: check + prompt install
./scripts/install-tools.sh

# Check tool status only
./scripts/install-tools.sh check

# Install all missing tools
./scripts/install-tools.sh install

# Install tools for a specific agent
./scripts/install-tools.sh install horus   # IaC tools
./scripts/install-tools.sh install zeus    # GitOps tools
```

> **Windows users**: Run via Git Bash, WSL, or MSYS2. The script auto-detects your package manager (winget / Chocolatey / Scoop):
>
> ```powershell
> # Git Bash (recommended)
> bash scripts/install-tools.sh
>
> # WSL
> wsl bash scripts/install-tools.sh
> ```

### Shared Tools

| Tool | Tier | macOS (brew) | Linux (apt/snap) | Windows (winget) | Purpose |
|------|------|-------------|-------------------|------------------|---------|
| node | Required | `brew install node` | `apt-get install nodejs` | `winget install OpenJS.NodeJS.LTS` | postinstall runtime |
| git | Required | `brew install git` | `apt-get install git` | `winget install Git.Git` | Version control |
| kubectl | Required | `brew install kubectl` | `snap install kubectl` | `winget install Kubernetes.kubectl` | K8s CLI |
| jq | Required | `brew install jq` | `apt-get install jq` | `winget install jqlang.jq` | JSON processor |
| yq | Recommended | `brew install yq` | `snap install yq` | `winget install MikeFarah.yq` | YAML processor |
| python3 | Recommended | `brew install python3` | `apt-get install python3` | `winget install Python.Python.3.12` | Version check scripts |
| curl | Recommended | `brew install curl` | `apt-get install curl` | `winget install cURL.cURL` | Remote version check |

### Horus Tools (IaC)

| Tool | Tier | macOS (brew) | Windows (winget/choco) | pip | Purpose |
|------|------|-------------|------------------------|-----|---------|
| terraform | Required | `brew install terraform` | `winget install Hashicorp.Terraform` | — | IaC engine |
| helm | Required | `brew install helm` | `winget install Helm.Helm` | — | Helm chart management |
| tflint | Recommended | `brew install tflint` | `choco install tflint` | — | Terraform linter |
| tfsec | Recommended | `brew install tfsec` | `choco install tfsec` | — | Terraform security scanner |
| pre-commit | Recommended | — | — | `pip install pre-commit` | Git hook manager |

### Zeus Tools (GitOps)

| Tool | Tier | macOS (brew) | Windows (choco/scoop) | pip | Purpose |
|------|------|-------------|------------------------|-----|---------|
| kustomize | Required | `brew install kustomize` | `scoop install kustomize` | — | Kustomize build |
| yamllint | Recommended | — | — | `pip install yamllint` | YAML linter |
| kubeconform | Recommended | `brew install kubeconform` | `scoop install kubeconform` | — | K8s resource validation |
| kube-score | Recommended | `brew install kube-score` | — | — | K8s best practices |
| kube-linter | Recommended | `brew install kube-linter` | — | — | K8s linter |
| polaris | Recommended | `brew install FairwindsOps/tap/polaris` | — | — | K8s policy check |
| pluto | Recommended | `brew install FairwindsOps/tap/pluto` | — | — | Deprecated API detection |
| conftest | Recommended | `brew install conftest` | — | — | Policy testing |
| checkov | Recommended | — | — | `pip install checkov` | IaC security scanner |
| trivy | Recommended | `brew install trivy` | `choco install trivy` | — | Vulnerability scanner |
| gitleaks | Recommended | `brew install gitleaks` | `choco install gitleaks` | — | Secret detection |
| d2 | Recommended | `brew install d2` | `scoop install d2` | — | Architecture diagrams |

## Horus Pipelines (IaC)

| Pipeline | Description |
|----------|-------------|
| `*full` | Full check (RUNS CLI tools) + report |
| `*upgrade` | Upgrade Helm chart versions |
| `*security` | Security audit (file analysis) |
| `*validate` | Validation (fmt + file analysis) |
| `*new-module` | Scaffold new Helm module |
| `*cicd` | Improve CI/CD pipeline |
| `*health` | Platform health check |

## Zeus Pipelines (GitOps)

| Pipeline | Description |
|----------|-------------|
| `*full` | Full pipeline + YAML/MD reports |
| `*pre-merge` | Pre-MR essential checks |
| `*health-check` | Repository health assessment |
| `*review` | MR review pipeline |
| `*onboard` | Service onboarding (interactive) |
| `*diagram` | Generate architecture diagrams |
| `*status` | Tool installation check |

## Skills

All skills follow the [Open Agent Skills](https://agentskills.io/specification) standard (SKILL.md with YAML frontmatter):

| Skill | Used By | Purpose |
|-------|---------|---------|
| terraform-validate | Horus | Validation and linting |
| terraform-security | Horus | Security scanning |
| helm-version-upgrade | Horus | Helm chart version management |
| helm-scaffold | Horus | New module generation |
| cicd-enhancer | Horus | CI/CD pipeline improvement |
| kustomize-resource-validation | Zeus | Kustomize build + validation |
| yaml-fix-suggestions | Zeus | YAML formatting |
| repo-detect | Both | Repository type detection |

## Project Structure

```
devops-ai-skill/
├── CLAUDE.md                    # Claude Code entry
├── AGENTS.md                    # OpenAI Codex entry
├── GEMINI.md                    # Gemini CLI entry
├── VERSION                      # Version source
│
├── .claude/                     # Claude Code platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   └── skills/ → symlink to skills/
│
├── .codex/                      # OpenAI Codex platform
│   ├── config.toml
│   └── skills/ → symlink to skills/
│
├── .gemini/                     # Google Gemini platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   ├── commands/devops/          # Command palette TOML
│   │   ├── agents/               # 2 agent start commands
│   │   └── pipelines/            # 16 pipeline commands
│   └── extensions/devops/
│       └── gemini-extension.json
│
├── .agents/                     # Google Antigravity platform
│   ├── rules/devops.md
│   ├── skills/
│   │   ├── horus/SKILL.md
│   │   ├── zeus/SKILL.md
│   │   └── (8 skill symlinks)
│   └── workflows/               # symlinks → prompts/
│
├── skills/                      # Shared skills (Open Agent Skills standard)
│   ├── terraform-validate/
│   ├── terraform-security/
│   ├── helm-version-upgrade/
│   ├── helm-scaffold/
│   ├── cicd-enhancer/
│   ├── kustomize-resource-validation/
│   ├── yaml-fix-suggestions/
│   └── repo-detect/
│
├── prompts/                     # Platform-neutral pipeline definitions
│   ├── horus/                   # 7 pipelines
│   ├── zeus/                    # 7 pipelines
│   └── shared/                  # repo-detect, report-format, tool-check
│
├── scripts/
│   ├── setup.sh                    # Unified install script (recommended)
│   ├── install-tools.sh
│   ├── version-check.sh
│   └── setup/
│       ├── setup-claude.sh         # Platform-specific (internal)
│       ├── setup-codex.sh
│       ├── setup-gemini.sh
│       └── setup-antigravity.sh
│
├── .claude-plugin/              # Claude Code marketplace
│   ├── plugin.json
│   └── marketplace.json
│
└── docs/
    ├── quick-start.md           # 5-minute quick start
    ├── setup.md                 # Detailed setup guide
    └── guide/                   # Tutorial images (coming soon)
```

## Version Check

```bash
bash scripts/version-check.sh
```

## Update

```bash
# Git
git pull origin main

# Or specific version
git checkout v<version>

# Or npx skills
npx skills update
```

## Design Principles

- **No hardcoded paths** — Both agents discover directories dynamically
- **Graceful degradation** — Missing tools skip the check and show install commands
- **User-controlled** — Critical operations (e.g., terraform init) always ask the user
- **Dynamic discovery** — Each skill defines "Step 0: Discover Repository Layout"

## License

MIT
