# ⚡ DevOps AI Skill Pack

[![npm version](https://img.shields.io/npm/v/devops-ai-skill?style=flat-square&color=cb3837)](https://www.npmjs.com/package/devops-ai-skill)
[![GitHub Release](https://img.shields.io/github/v/release/qwedsazxc78/devops-ai-skill?style=flat-square&color=2ea44f)](https://github.com/qwedsazxc78/devops-ai-skill/releases)
[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#專案結構)
[![SKILLS](https://img.shields.io/badge/SKILLS-8-blueviolet?style=flat-square)](#技能模組)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-14-ff6f61?style=flat-square)](#horus-流水線iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agent-代理)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-3-teal?style=flat-square)](#平台支援)

> 跨平台 DevOps AI 技能包 — 兩個 AI 驅動的 DevOps Agent 與共用流水線工作流，支援 **Claude Code**、**OpenAI Codex CLI** 和 **Google Gemini CLI**。

🚀 [快速開始](#快速開始) · 🤖 [Agent](#agent-代理) · 🔧 [工具安裝](#工具安裝) · 🛠️ [技能模組](#技能模組) · 📖 [安裝指南](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

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
/plugin install devops@devops-ai-skill
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

> **注意**：`npx skills add` 僅安裝 8 個 Skills（SKILL.md）。如需完整體驗（Horus/Zeus Agent + 14 條流水線），請使用 **Git Clone** 或 **Marketplace** 方式安裝。

</details>

## 平台支援

| 功能 | Claude Code | OpenAI Codex | Gemini CLI |
|------|-------------|--------------|------------|
| 入口檔 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目錄 | `.claude/skills/` | `.codex/skills/` | extensions |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | gemini-extension.json |
| Agent 定義 | `.claude/agents/*.md` | 透過 AGENTS.md | `.gemini/agents/*.md` |
| Bash 執行 | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

## 工具安裝

一鍵安裝所有必要工具，支援 macOS (Homebrew)、Linux (apt/snap)、Python (pip)：

```bash
# 互動模式：檢查 + 提示安裝
./scripts/install-tools.sh

# 僅檢查工具狀態
./scripts/install-tools.sh check

# 安裝全部缺少的工具
./scripts/install-tools.sh install

# 僅安裝特定 Agent 的工具
./scripts/install-tools.sh install horus   # IaC 工具
./scripts/install-tools.sh install zeus    # GitOps 工具
```

### 共用工具

| 工具 | 等級 | macOS (brew) | Linux (apt/snap) | 說明 |
|------|------|-------------|-------------------|------|
| git | 必要 | `brew install git` | `apt-get install git` | 版本控制 |
| kubectl | 必要 | `brew install kubectl` | `snap install kubectl` | K8s CLI |
| jq | 必要 | `brew install jq` | `apt-get install jq` | JSON 處理 |
| yq | 建議 | `brew install yq` | `snap install yq` | YAML 處理 |

### Horus 工具（IaC）

| 工具 | 等級 | macOS (brew) | pip | 說明 |
|------|------|-------------|-----|------|
| terraform | 必要 | `brew install terraform` | — | IaC 引擎 |
| tflint | 建議 | `brew install tflint` | — | Terraform Lint |
| tfsec | 建議 | `brew install tfsec` | — | Terraform 安全掃描 |
| pre-commit | 建議 | — | `pip install pre-commit` | Git Hook 管理 |

### Zeus 工具（GitOps）

| 工具 | 等級 | macOS (brew) | pip | 說明 |
|------|------|-------------|-----|------|
| kustomize | 必要 | `brew install kustomize` | — | Kustomize 建置 |
| yamllint | 建議 | — | `pip install yamllint` | YAML Lint |
| kubeconform | 建議 | `brew install kubeconform` | — | K8s 資源驗證 |
| kube-score | 建議 | `brew install kube-score` | — | K8s 最佳實踐 |
| kube-linter | 建議 | `brew install kube-linter` | — | K8s Lint |
| polaris | 建議 | `brew install FairwindsOps/tap/polaris` | — | K8s 政策檢查 |
| pluto | 建議 | `brew install FairwindsOps/tap/pluto` | — | 廢棄 API 偵測 |
| conftest | 建議 | `brew install conftest` | — | 政策測試 |
| checkov | 建議 | — | `pip install checkov` | IaC 安全掃描 |
| trivy | 建議 | `brew install trivy` | — | 漏洞掃描 |
| gitleaks | 建議 | `brew install gitleaks` | — | 機密偵測 |

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

🚀 [Quick Start](#quick-start) · 🤖 [Agents](#agents) · 🔧 [Tool Installation](#tool-installation) · 🛠️ [Skills](#skills) · 📖 [Setup Guide](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

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
/plugin install devops@devops-ai-skill
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

> **Note**: `npx skills add` installs the 8 skills (SKILL.md) only. For the full experience (Horus/Zeus agents + 14 pipelines), use **Git Clone** or **Marketplace** install.

</details>

### Platform Support

| Feature | Claude Code | OpenAI Codex | Gemini CLI |
|---------|-------------|--------------|------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills directory | `.claude/skills/` | `.codex/skills/` | via extensions |
| Skills format | SKILL.md (native) | SKILL.md (native) | gemini-extension.json |
| Agent definitions | `.claude/agents/*.md` | via AGENTS.md | `.gemini/agents/*.md` |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

### Tool Installation

One-command installer supporting macOS (Homebrew), Linux (apt/snap), and Python (pip):

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

#### Shared Tools

| Tool | Tier | macOS (brew) | Linux (apt/snap) | Purpose |
|------|------|-------------|-------------------|---------|
| git | Required | `brew install git` | `apt-get install git` | Version control |
| kubectl | Required | `brew install kubectl` | `snap install kubectl` | K8s CLI |
| jq | Required | `brew install jq` | `apt-get install jq` | JSON processor |
| yq | Recommended | `brew install yq` | `snap install yq` | YAML processor |

#### Horus Tools (IaC)

| Tool | Tier | macOS (brew) | pip | Purpose |
|------|------|-------------|-----|---------|
| terraform | Required | `brew install terraform` | — | IaC engine |
| tflint | Recommended | `brew install tflint` | — | Terraform linter |
| tfsec | Recommended | `brew install tfsec` | — | Terraform security scanner |
| pre-commit | Recommended | — | `pip install pre-commit` | Git hook manager |

#### Zeus Tools (GitOps)

| Tool | Tier | macOS (brew) | pip | Purpose |
|------|------|-------------|-----|---------|
| kustomize | Required | `brew install kustomize` | — | Kustomize build |
| yamllint | Recommended | — | `pip install yamllint` | YAML linter |
| kubeconform | Recommended | `brew install kubeconform` | — | K8s resource validation |
| kube-score | Recommended | `brew install kube-score` | — | K8s best practices |
| kube-linter | Recommended | `brew install kube-linter` | — | K8s linter |
| polaris | Recommended | `brew install FairwindsOps/tap/polaris` | — | K8s policy check |
| pluto | Recommended | `brew install FairwindsOps/tap/pluto` | — | Deprecated API detection |
| conftest | Recommended | `brew install conftest` | — | Policy testing |
| checkov | Recommended | — | `pip install checkov` | IaC security scanner |
| trivy | Recommended | `brew install trivy` | — | Vulnerability scanner |
| gitleaks | Recommended | `brew install gitleaks` | — | Secret detection |

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

🚀 [快速开始](#快速开始-1) · 🤖 [Agent](#agent-代理-1) · 🔧 [工具安装](#工具安装) · 🛠️ [技能模块](#技能模块) · 📖 [安装指南](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

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
/plugin install devops@devops-ai-skill
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

> **注意**：`npx skills add` 仅安装 8 个 Skills（SKILL.md）。如需完整体验（Horus/Zeus Agent + 14 条流水线），请使用 **Git Clone** 或 **Marketplace** 方式安装。

</details>

### 平台支持

| 功能 | Claude Code | OpenAI Codex | Gemini CLI |
|------|-------------|--------------|------------|
| 入口文件 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目录 | `.claude/skills/` | `.codex/skills/` | extensions |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | gemini-extension.json |
| Agent 定义 | `.claude/agents/*.md` | 通过 AGENTS.md | `.gemini/agents/*.md` |
| Bash 执行 | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |

### 工具安装

一键安装所有必要工具，支持 macOS (Homebrew)、Linux (apt/snap)、Python (pip)：

```bash
# 交互模式：检查 + 提示安装
./scripts/install-tools.sh

# 仅检查工具状态
./scripts/install-tools.sh check

# 安装全部缺少的工具
./scripts/install-tools.sh install

# 仅安装特定 Agent 的工具
./scripts/install-tools.sh install horus   # IaC 工具
./scripts/install-tools.sh install zeus    # GitOps 工具
```

#### 共用工具

| 工具 | 等级 | macOS (brew) | Linux (apt/snap) | 说明 |
|------|------|-------------|-------------------|------|
| git | 必要 | `brew install git` | `apt-get install git` | 版本控制 |
| kubectl | 必要 | `brew install kubectl` | `snap install kubectl` | K8s CLI |
| jq | 必要 | `brew install jq` | `apt-get install jq` | JSON 处理 |
| yq | 建议 | `brew install yq` | `snap install yq` | YAML 处理 |

#### Horus 工具（IaC）

| 工具 | 等级 | macOS (brew) | pip | 说明 |
|------|------|-------------|-----|------|
| terraform | 必要 | `brew install terraform` | — | IaC 引擎 |
| tflint | 建议 | `brew install tflint` | — | Terraform Lint |
| tfsec | 建议 | `brew install tfsec` | — | Terraform 安全扫描 |
| pre-commit | 建议 | — | `pip install pre-commit` | Git Hook 管理 |

#### Zeus 工具（GitOps）

| 工具 | 等级 | macOS (brew) | pip | 说明 |
|------|------|-------------|-----|------|
| kustomize | 必要 | `brew install kustomize` | — | Kustomize 构建 |
| yamllint | 建议 | — | `pip install yamllint` | YAML Lint |
| kubeconform | 建议 | `brew install kubeconform` | — | K8s 资源验证 |
| kube-score | 建议 | `brew install kube-score` | — | K8s 最佳实践 |
| kube-linter | 建议 | `brew install kube-linter` | — | K8s Lint |
| polaris | 建议 | `brew install FairwindsOps/tap/polaris` | — | K8s 策略检查 |
| pluto | 建议 | `brew install FairwindsOps/tap/pluto` | — | 废弃 API 检测 |
| conftest | 建议 | `brew install conftest` | — | 策略测试 |
| checkov | 建议 | — | `pip install checkov` | IaC 安全扫描 |
| trivy | 建议 | `brew install trivy` | — | 漏洞扫描 |
| gitleaks | 建议 | `brew install gitleaks` | — | 机密检测 |

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
