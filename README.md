# ⚡ DevOps AI Skill Pack

[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#專案結構)
[![SKILLS](https://img.shields.io/badge/SKILLS-8-blueviolet?style=flat-square)](#技能模組)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-14-ff6f61?style=flat-square)](#horus-流水線iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agent-代理)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-3-teal?style=flat-square)](#平台支援)

> 跨平台 DevOps AI 技能包 — 兩個 AI 驅動的 DevOps Agent 與共用流水線工作流，支援 **Claude Code**、**OpenAI Codex CLI** 和 **Google Gemini CLI**。

🚀 [快速開始](#快速開始) · 🤖 [Agent](#agent-代理) · 🛠️ [技能模組](#技能模組) · 📖 [安裝指南](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

[繁體中文](#繁體中文) | [English](#english) | [简体中文](#简体中文)

---

<a id="繁體中文"></a>

## Agent 代理

| Agent | 專注領域 | 平台 |
|-------|---------|------|
| **Horus** — IaC 營運工程師 | Terraform + Helm + GKE | 全平台 |
| **Zeus** — GitOps 工程師 | Kustomize + ArgoCD | 全平台 |

## 快速開始

<details>
<summary><strong>Claude Code</strong>（推薦）</summary>

### 方式 A：Marketplace

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

### 方式 B：Git Clone

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
# AGENTS.md 會被 Codex CLI 自動載入
```

</details>

<details>
<summary><strong>Google Gemini CLI</strong></summary>

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-gemini.sh
# GEMINI.md 會被 Gemini CLI 自動載入
```

</details>

<details>
<summary><strong>跨平台（npx skills）</strong></summary>

```bash
# 自動偵測已安裝的 AI Agent 並路由 Skills
npx skills add qwedsazxc78/devops-ai-skill

# 更新
npx skills update
```

</details>

## 平台支援

| 功能 | Claude Code | OpenAI Codex | Gemini CLI |
|------|-------------|--------------|------------|
| 入口檔 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目錄 | `.claude/skills/` | `.codex/skills/` | extensions |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | gemini-extension.json |
| Agent 定義 | `.claude/agents/*.md` | 透過 AGENTS.md | `.gemini/agents/*.md` |
| Bash 執行 | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

## Horus 流水線（IaC）

| 流水線 | 說明 |
|--------|------|
| `*full` | 完整檢查（執行 CLI 工具）+ 報告 |
| `*upgrade` | 升級 Helm Chart 版本 |
| `*security` | 安全性稽核（檔案分析） |
| `*validate` | 驗證（fmt + 檔案分析） |
| `*new-module` | 建立新的 Helm 模組 |
| `*cicd` | 改善 CI/CD 流水線 |
| `*health` | 平台健康檢查 |

## Zeus 流水線（GitOps）

| 流水線 | 說明 |
|--------|------|
| `*full` | 完整流水線 + YAML/MD 報告 |
| `*pre-merge` | 合併前基本檢查 |
| `*health-check` | 儲存庫健康評估 |
| `*review` | MR 審查流水線 |
| `*onboard` | 服務上線（互動式） |
| `*diagram` | 產生架構圖 |
| `*status` | 工具安裝狀態檢查 |

## 技能模組

所有技能遵循 [Open Agent Skills](https://agentskills.io/specification) 標準（SKILL.md + YAML frontmatter）：

| 技能 | 使用者 | 用途 |
|------|--------|------|
| terraform-validate | Horus | 驗證與 Lint |
| terraform-security | Horus | 安全性掃描 |
| helm-version-upgrade | Horus | Helm Chart 版本管理 |
| helm-scaffold | Horus | 新模組產生 |
| cicd-enhancer | Horus | CI/CD 流水線改善 |
| kustomize-resource-validation | Zeus | Kustomize 建置 + 驗證 |
| yaml-fix-suggestions | Zeus | YAML 格式修正 |
| repo-detect | 共用 | 儲存庫類型偵測 |

## 專案結構

```
devops-ai-skill/
├── CLAUDE.md                    # Claude Code 入口
├── AGENTS.md                    # OpenAI Codex 入口
├── GEMINI.md                    # Gemini CLI 入口
├── VERSION                      # 版本來源
│
├── .claude/                     # Claude Code 平台
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   └── skills/ → symlink to skills/
│
├── .codex/                      # OpenAI Codex 平台
│   ├── config.toml
│   └── skills/ → symlink to skills/
│
├── .gemini/                     # Google Gemini 平台
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   └── extensions/devops/
│       └── gemini-extension.json
│
├── skills/                      # 共用技能（Open Agent Skills 標準）
│   ├── terraform-validate/
│   ├── terraform-security/
│   ├── helm-version-upgrade/
│   ├── helm-scaffold/
│   ├── cicd-enhancer/
│   ├── kustomize-resource-validation/
│   ├── yaml-fix-suggestions/
│   └── repo-detect/
│
├── prompts/                     # 平台中立的流水線定義
│   ├── horus/                   # 7 條流水線
│   ├── zeus/                    # 7 條流水線
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
    └── setup.md                 # 詳細安裝指南
```

## 版本檢查

```bash
bash scripts/version-check.sh
```

## 更新

```bash
# Git
git pull origin main

# 或指定版本
git checkout v1.0.0

# 或 npx skills
npx skills update
```

## 設計原則

- **無硬編碼路徑** — 兩個 Agent 都動態發現目錄
- **優雅降級** — 缺少工具時跳過檢查並顯示安裝指令
- **使用者控制** — 重大操作（如 terraform init）總是詢問使用者
- **動態發現** — 每個 skill 定義「Step 0: 發現 Repository 佈局」

## 授權

MIT

---

<a id="english"></a>

## English

> Cross-platform DevOps AI Skill Pack — two AI-powered agents and shared pipeline workflows for **Claude Code**, **OpenAI Codex CLI**, and **Google Gemini CLI**.

🚀 [Quick Start](#quick-start) · 🤖 [Agents](#agents) · 🛠️ [Skills](#skills) · 📖 [Setup Guide](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

### Agents

| Agent | Focus | Platforms |
|-------|-------|-----------|
| **Horus** — IaC Operations Engineer | Terraform + Helm + GKE | All |
| **Zeus** — GitOps Engineer | Kustomize + ArgoCD | All |

### Quick Start

<details>
<summary><strong>Claude Code</strong> (recommended)</summary>

#### Option A: Marketplace

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

#### Option B: Git Clone

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

### Platform Support

| Feature | Claude Code | OpenAI Codex | Gemini CLI |
|---------|-------------|--------------|------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills directory | `.claude/skills/` | `.codex/skills/` | via extensions |
| Skills format | SKILL.md (native) | SKILL.md (native) | gemini-extension.json |
| Agent definitions | `.claude/agents/*.md` | via AGENTS.md | `.gemini/agents/*.md` |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

### Horus Pipelines (IaC)

| Pipeline | Description |
|----------|-------------|
| `*full` | Full check (RUNS CLI tools) + report |
| `*upgrade` | Upgrade Helm chart versions |
| `*security` | Security audit (file analysis) |
| `*validate` | Validation (fmt + file analysis) |
| `*new-module` | Scaffold new Helm module |
| `*cicd` | Improve CI/CD pipeline |
| `*health` | Platform health check |

### Zeus Pipelines (GitOps)

| Pipeline | Description |
|----------|-------------|
| `*full` | Full pipeline + YAML/MD reports |
| `*pre-merge` | Pre-MR essential checks |
| `*health-check` | Repository health assessment |
| `*review` | MR review pipeline |
| `*onboard` | Service onboarding (interactive) |
| `*diagram` | Generate architecture diagrams |
| `*status` | Tool installation check |

### Skills

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

### Design Principles

- **No hardcoded paths** — Both agents discover directories dynamically
- **Graceful degradation** — Missing tools skip the check and show install commands
- **User-controlled** — Critical operations (e.g., terraform init) always ask the user
- **Dynamic discovery** — Each skill defines "Step 0: Discover Repository Layout"

### License

MIT

---

<a id="简体中文"></a>

## 简体中文

> 跨平台 DevOps AI 技能包 — 两个 AI 驱动的 DevOps Agent 与共用流水线工作流，支持 **Claude Code**、**OpenAI Codex CLI** 和 **Google Gemini CLI**。

🚀 [快速开始](#快速开始-1) · 🤖 [Agent](#agent-代理-1) · 🛠️ [技能模块](#技能模块) · 📖 [安装指南](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

### Agent 代理

| Agent | 专注领域 | 平台 |
|-------|---------|------|
| **Horus** — IaC 运维工程师 | Terraform + Helm + GKE | 全平台 |
| **Zeus** — GitOps 工程师 | Kustomize + ArgoCD | 全平台 |

### 快速开始

<details>
<summary><strong>Claude Code</strong>（推荐）</summary>

#### 方式 A：Marketplace

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

#### 方式 B：Git Clone

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
# AGENTS.md 会被 Codex CLI 自动加载
```

</details>

<details>
<summary><strong>Google Gemini CLI</strong></summary>

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-gemini.sh
# GEMINI.md 会被 Gemini CLI 自动加载
```

</details>

<details>
<summary><strong>跨平台（npx skills）</strong></summary>

```bash
# 自动检测已安装的 AI Agent 并路由 Skills
npx skills add qwedsazxc78/devops-ai-skill

# 更新
npx skills update
```

</details>

### 平台支持

| 功能 | Claude Code | OpenAI Codex | Gemini CLI |
|------|-------------|--------------|------------|
| 入口文件 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目录 | `.claude/skills/` | `.codex/skills/` | extensions |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | gemini-extension.json |
| Agent 定义 | `.claude/agents/*.md` | 通过 AGENTS.md | `.gemini/agents/*.md` |
| Bash 执行 | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

### Horus 流水线（IaC）

| 流水线 | 说明 |
|--------|------|
| `*full` | 完整检查（执行 CLI 工具）+ 报告 |
| `*upgrade` | 升级 Helm Chart 版本 |
| `*security` | 安全性审计（文件分析） |
| `*validate` | 验证（fmt + 文件分析） |
| `*new-module` | 创建新的 Helm 模块 |
| `*cicd` | 改善 CI/CD 流水线 |
| `*health` | 平台健康检查 |

### Zeus 流水线（GitOps）

| 流水线 | 说明 |
|--------|------|
| `*full` | 完整流水线 + YAML/MD 报告 |
| `*pre-merge` | 合并前基本检查 |
| `*health-check` | 仓库健康评估 |
| `*review` | MR 审查流水线 |
| `*onboard` | 服务上线（交互式） |
| `*diagram` | 生成架构图 |
| `*status` | 工具安装状态检查 |

### 技能模块

所有技能遵循 [Open Agent Skills](https://agentskills.io/specification) 标准（SKILL.md + YAML frontmatter）：

| 技能 | 使用者 | 用途 |
|------|--------|------|
| terraform-validate | Horus | 验证与 Lint |
| terraform-security | Horus | 安全性扫描 |
| helm-version-upgrade | Horus | Helm Chart 版本管理 |
| helm-scaffold | Horus | 新模块生成 |
| cicd-enhancer | Horus | CI/CD 流水线改善 |
| kustomize-resource-validation | Zeus | Kustomize 构建 + 验证 |
| yaml-fix-suggestions | Zeus | YAML 格式修正 |
| repo-detect | 共用 | 仓库类型检测 |

### 设计原则

- **无硬编码路径** — 两个 Agent 都动态发现目录
- **优雅降级** — 缺少工具时跳过检查并显示安装命令
- **用户控制** — 重大操作（如 terraform init）总是询问用户
- **动态发现** — 每个 skill 定义「Step 0: 发现 Repository 布局」

### 授权

MIT
