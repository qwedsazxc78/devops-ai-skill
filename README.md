# ⚡ DevOps AI Skill Pack

[![npm version](https://img.shields.io/npm/v/devops-ai-skill?style=flat-square&color=cb3837)](https://www.npmjs.com/package/devops-ai-skill)
[![GitHub Release](https://img.shields.io/github/v/release/qwedsazxc78/devops-ai-skill?style=flat-square&color=2ea44f)](https://github.com/qwedsazxc78/devops-ai-skill/releases)
[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#project-structure)
[![SKILLS](https://img.shields.io/badge/SKILLS-10-blueviolet?style=flat-square)](#skills)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-15-ff6f61?style=flat-square)](#horus-pipelines-iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agents)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-4-teal?style=flat-square)](#platform-support)

> Cross-platform DevOps AI Skill Pack — two AI-powered DevOps agents and shared pipeline workflows for **Claude Code**, **OpenAI Codex CLI**, **Google Gemini CLI**, and **Google Antigravity**.

🚀 [Quick Start](#quick-start) · 🤖 [Agents](#agents) · 🔧 [Tool Installation](#tool-installation) · 🛠️ [Skills](#skills) · 📖 [Setup Guide](docs/setup.md) · ⚡ [5-Min Guide](docs/quick-start.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

English | [繁體中文](docs/README.zh-TW.md) | [简体中文](docs/README.zh-CN.md)

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

![Global Install](docs/guide/01-install-global-run.png)

> 🆕 **New here?** Check out the [5-minute quick start guide](docs/quick-start.md) — zero prior knowledge required!

<details>
<summary><strong>Global Install Options</strong></summary>

```bash
bash scripts/install-global.sh --all            # Force all platforms
bash scripts/install-global.sh --claude         # Claude Code only
bash scripts/install-global.sh --codex          # Codex CLI only
bash scripts/install-global.sh --gemini         # Gemini CLI only
bash scripts/install-global.sh --antigravity    # Antigravity only
bash scripts/install-global.sh --status         # Check install status
bash scripts/install-global.sh --uninstall      # Remove global installs
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

> **⚠️ Note: This method installs only the 9 Skills (SKILL.md), not the full pack:**
>
> | Feature | npx skills | Global Install |
> |---------|:----------:|:--------------:|
> | 9 Skills (SKILL.md) | ✅ | ✅ |
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
| `*help` | Show available pipelines |
| `*full` | Full check (RUNS CLI tools) + report |
| `*upgrade` | Upgrade Helm chart versions |
| `*security` | Security audit (file analysis) |
| `*validate` | Validation (fmt + file analysis) |
| `*scaffold` | Scaffold new Helm module |
| `*cicd` | Improve CI/CD pipeline |
| `*health` | Platform health check |

## Zeus Pipelines (GitOps)

| Pipeline | Description |
|----------|-------------|
| `*help` | Show available pipelines |
| `*full` | Full pipeline + YAML/MD reports |
| `*pre-merge` | Pre-MR essential checks |
| `*health` | Repository health assessment |
| `*review` | MR review pipeline |
| `*scaffold` | Service scaffold (interactive) |
| `*diagram` | Generate architecture diagrams |
| `*status` | Tool installation check |
| `*gateway-migrate` | NGINX Ingress → GKE Gateway API migration (master/minion or standalone) |

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
| gateway-api-migration | Zeus | NGINX Ingress → GKE Gateway API migration with state tracking |
| repo-detect | Both | Repository type detection |
| release-validate | Shared | Release readiness validation |

## Example: NGINX → Gateway API Migration

The `*gateway-migrate` pipeline migrates an NGINX Ingress GitOps repo to GKE Gateway API resources. It handles the common **master/minion** topology where:

- `common.ingress/` declares hosts + TLS (the "master")
- `common.service/overlays/<env>/<svc>-nginx-ingress.yaml` declares paths + backends per service (the "minions")

This pattern maps cleanly onto Gateway API's persona model: the master becomes a `Gateway` resource, each minion becomes an `HTTPRoute`.

### Workflow

```bash
# 1. cd into your GitOps repo
cd /path/to/your-gitops-repo
claude    # or gemini / codex / antigravity

# 2. Run the pipeline (interactive)
> *gateway-migrate

# Zeus will:
#   - Detect master/minion or standalone topology
#   - Show annotation classification (portable / convertible / manual review)
#   - Ask for confirmation before generating any files
#   - Create a new `common.gateway/` Kustomize module (Gateway resource)
#   - Add HTTPRoutes alongside existing minions in `common.service/overlays/`
#   - Run `kustomize build` validation
#   - Write a state YAML + markdown report under `docs/reports/gateway-migration/`
#   - Print a per-hostname DNS cutover runbook

# 3. Review the generated module
ls common.gateway/
cat docs/reports/gateway-migration/<module>/report.md

# 4. Stage and commit
git add common.gateway/ common.service/overlays/ docs/reports/gateway-migration/
git commit
```

### Invocation forms

| Form | What it does |
|------|--------------|
| `*gateway-migrate` | Interactive discovery — Zeus finds Ingress modules and asks which to migrate |
| `*gateway-migrate <module-path>` | Skip discovery, target a known module directly |
| `*gateway-migrate <module-path> --resume` | Resume from a previously failed run via the state YAML |
| `*gateway-migrate <module-path> --force` | Bypass the never-clobber check on the target module |

### What gets generated

- **`common.gateway/`** — new Kustomize module with the Gateway resource, per-env overlays, ArgoCD `Application` manifests
- **`common.service/overlays/<env>/<svc>-httproute.yaml`** — one HTTPRoute per minion, side-by-side with existing minion files
- **`common.service/overlays/<env>/kustomization.yaml`** — idempotent in-place edit registering the new HTTPRoute resources
- **`docs/reports/gateway-migration/<module>/state.yaml`** — resumable migration state (audit trail)
- **`docs/reports/gateway-migration/<module>/report.md`** — human report with cutover runbook + manual-review TODO list

### Cutover strategy

The skill never modifies the master Ingress and never overwrites minion Ingress files — both stacks coexist. The runbook walks through a **per-hostname DNS cutover**: deploy the new Gateway, deploy HTTPRoutes alongside minions, then flip DNS one hostname at a time. Rollback is a DNS flip back; old stack remains live throughout.

### Reference docs

- [`docs/gateway/annotation-map.md`](docs/gateway/annotation-map.md) — Canonical 13-row Ingress → Gateway API translation table
- [`docs/gateway/master-minion-topology.md`](docs/gateway/master-minion-topology.md) — Detection rules and pairing algorithm
- [`docs/gateway/gke-gateway-notes.md`](docs/gateway/gke-gateway-notes.md) — GKE GatewayClasses, GCPBackendPolicy, ManagedCertificate
- [`docs/gateway/http-routing-guide.md`](docs/gateway/http-routing-guide.md) — HTTPRoute reference
- [`docs/gateway/migrate-from-ingress.md`](docs/gateway/migrate-from-ingress.md) — Concepts and worked example
- [`docs/gateway/ingress2gateway-integration.md`](docs/gateway/ingress2gateway-integration.md) — Optional second-opinion tool
- [`docs/gateway/ingress-nginx-welcome.md`](docs/gateway/ingress-nginx-welcome.md) — Migration welcome page

### Optional second opinion

Install the upstream [`kubernetes-sigs/ingress2gateway`](https://github.com/kubernetes-sigs/ingress2gateway) tool and the skill will run it as a cross-check during validation, surfacing any divergence between its output and the skill's output in the report:

```bash
brew install ingress2gateway
```

Without it, the skill still works fine — the second-opinion check is just skipped (graceful degradation).

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
│   │   └── pipelines/            # 17 pipeline commands
│   └── extensions/devops/
│       └── gemini-extension.json
│
├── .agents/                     # Google Antigravity platform
│   ├── rules/devops.md
│   ├── skills/
│   │   ├── horus/SKILL.md
│   │   ├── zeus/SKILL.md
│   │   └── (10 skill symlinks)
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
│   ├── gateway-api-migration/
│   └── repo-detect/
│
├── prompts/                     # Platform-neutral pipeline definitions
│   ├── horus/                   # 7 pipelines
│   ├── zeus/                    # 8 pipelines
│   └── shared/                  # repo-detect, report-format, tool-check, help
│
├── docs/
│   ├── quick-start.md           # 5-minute quick start
│   ├── setup.md                 # Detailed setup guide
│   ├── gateway/                 # NGINX → Gateway API migration reference
│   ├── guide/                   # Tutorial screenshots
│   ├── reports/                 # Generated pipeline reports (*full output)
│   └── diagrams/                # Generated architecture diagrams (*diagram output)
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
└── tests/
    └── test-structure.sh        # 334 structure + parity tests
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
