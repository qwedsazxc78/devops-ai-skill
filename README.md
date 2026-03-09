# DevOps AI Skill Pack

Cross-platform DevOps AI Skill Pack providing two AI-powered agents and shared pipeline workflows. Works with **Claude Code**, **OpenAI Codex CLI**, and **Google Gemini CLI**.

[English](#english) | [繁體中文](#繁體中文)

---

<a id="english"></a>

## Agents

| Agent | Focus | Platforms |
|-------|-------|-----------|
| **Horus** — IaC Operations Engineer | Terraform + Helm + GKE | All |
| **Zeus** — GitOps Engineer | Kustomize + ArgoCD | All |

## Quick Start

<details>
<summary><strong>Claude Code</strong> (recommended)</summary>

### Option A: Marketplace

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

### Option B: Git Clone

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-claude.sh
claude --plugin-dir ./devops-ai-skill
```

</details>

<details>
<summary><strong>OpenAI Codex CLI</strong></summary>

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-codex.sh
# AGENTS.md is auto-loaded by Codex CLI
```

</details>

<details>
<summary><strong>Google Gemini CLI</strong></summary>

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-gemini.sh
# GEMINI.md is auto-loaded by Gemini CLI
```

</details>

<details>
<summary><strong>Cross-Platform (npx skills)</strong></summary>

```bash
# Auto-detects installed AI agents and routes skills accordingly
npx skills add qwedsazxc78/devops-ai-skill

# Update
npx skills update
```

</details>

## Platform Support

| Feature | Claude Code | OpenAI Codex | Gemini CLI |
|---------|-------------|--------------|------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills directory | `.claude/skills/` | `.codex/skills/` | via extensions |
| Skills format | SKILL.md (native) | SKILL.md (native) | gemini-extension.json |
| Agent definitions | `.claude/agents/*.md` | via AGENTS.md | `.gemini/agents/*.md` |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

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
├── CLAUDE.md                    # Claude Code entry point
├── AGENTS.md                    # OpenAI Codex entry point
├── GEMINI.md                    # Gemini CLI entry point
├── VERSION                      # Version source of truth
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
│   └── extensions/devops/
│       └── gemini-extension.json
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
│   ├── install-tools.sh
│   ├── version-check.sh
│   └── setup/
│       ├── setup-claude.sh
│       ├── setup-codex.sh
│       └── setup-gemini.sh
│
├── .claude-plugin/              # Claude Code marketplace
│   ├── plugin.json
│   └── marketplace.json
│
└── docs/
    └── setup.md                 # Detailed setup guide
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
git checkout v1.0.0

# Or npx skills
npx skills update
```

## License

MIT

---

<a id="繁體中文"></a>

## 繁體中文

跨平台 DevOps AI 技能包，提供兩個 AI 驅動的 DevOps Agent 和共用流水線工作流。支援 **Claude Code**、**OpenAI Codex CLI** 和 **Google Gemini CLI**。

## Agent

| Agent | 專注領域 | 平台 |
|-------|---------|------|
| **Horus** — IaC 營運工程師 | Terraform + Helm + GKE | 全平台 |
| **Zeus** — GitOps 工程師 | Kustomize + ArgoCD | 全平台 |

## 快速開始

### Claude Code（推薦）

```bash
# Marketplace
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go

# 或 Git
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-claude.sh
```

### OpenAI Codex CLI

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-codex.sh
```

### Google Gemini CLI

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-gemini.sh
```

### 跨平台（npx skills）

```bash
npx skills add qwedsazxc78/devops-ai-skill
npx skills update
```

## 平台支援

| 功能 | Claude Code | OpenAI Codex | Gemini CLI |
|------|-------------|--------------|------------|
| 指令檔 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目錄 | `.claude/skills/` | `.codex/skills/` | extensions |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | gemini-extension.json |
| Agent 定義 | `.claude/agents/*.md` | 透過 AGENTS.md | `.gemini/agents/*.md` |

## 設計原則

- **無硬編碼路徑** — 兩個 Agent 都動態發現目錄
- **優雅降級** — 缺少工具時跳過檢查並顯示安裝指令
- **使用者控制** — 重大操作（如 terraform init）總是詢問使用者
- **動態發現** — 每個 skill 定義「Step 0: 發現 Repository 佈局」

## 授權

MIT
