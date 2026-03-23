# ⚡ DevOps AI Skill Pack

[![npm version](https://img.shields.io/npm/v/devops-ai-skill?style=flat-square&color=cb3837)](https://www.npmjs.com/package/devops-ai-skill)
[![GitHub Release](https://img.shields.io/github/v/release/qwedsazxc78/devops-ai-skill?style=flat-square&color=2ea44f)](https://github.com/qwedsazxc78/devops-ai-skill/releases)
[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#專案結構)
[![SKILLS](https://img.shields.io/badge/SKILLS-8-blueviolet?style=flat-square)](#技能模組)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-14-ff6f61?style=flat-square)](#horus-流水線iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agent-代理)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-4-teal?style=flat-square)](#平台支援)

> 跨平台 DevOps AI 技能包 — 兩個 AI 驅動的 DevOps Agent 與共用流水線工作流，支援 **Claude Code**、**OpenAI Codex CLI**、**Google Gemini CLI** 和 **Google Antigravity**。

🚀 [5 分鐘快速上手](docs/quick-start.md) · 🤖 [Agent](#agent-代理) · 🔧 [工具安裝](#工具安裝) · 🛠️ [技能模組](#技能模組) · 📖 [安裝指南](docs/setup.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

繁體中文 | [English](docs/README.en.md) | [简体中文](docs/README.zh-CN.md)

---

## Agent 代理

| Agent | 專注領域 | 平台 |
|-------|---------|------|
| **Horus** — IaC 營運工程師 | Terraform + Helm + GKE | 全平台 |
| **Zeus** — GitOps 工程師 | Kustomize + ArgoCD | 全平台 |

## 快速開始

### 全域安裝（推薦）

一次安裝，所有專案共用，無需 per-repo 設定：

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh          # 自動偵測已安裝的 CLI
```

自動偵測 Claude Code / Codex CLI / Gemini CLI / Antigravity，安裝至對應全域路徑。

> 🆕 **新手？** 請看 [5 分鐘快速上手指南](docs/quick-start.md)，零基礎也能立刻開始！

<details>
<summary><strong>全域安裝選項</strong></summary>

```bash
bash scripts/install-global.sh --all          # 強制安裝全部平台
bash scripts/install-global.sh --claude       # 僅 Claude Code
bash scripts/install-global.sh --gemini       # 僅 Gemini CLI
bash scripts/install-global.sh --status       # 查看安裝狀態
bash scripts/install-global.sh --uninstall    # 移除全域安裝
```

</details>

<details>
<summary><strong>更新已安裝的 Skills</strong></summary>

```bash
cd devops-ai-skill
git pull origin main                          # 拉取最新版本
bash scripts/install-global.sh                # 重跑安裝（自動跳過未變動檔案）
```

> 更新 source 後需重跑 `install-global.sh`，以同步變更至所有平台。

</details>

<details>
<summary><strong>Per-repo 安裝（傳統方式）</strong></summary>

在你的專案根目錄執行：

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
bash devops-ai-skill/scripts/setup.sh --all    # 安裝全部平台
bash devops-ai-skill/scripts/setup.sh          # 或互動選擇平台
```

```bash
# 僅安裝特定平台
bash devops-ai-skill/scripts/setup.sh --claude
bash devops-ai-skill/scripts/setup.sh --codex
bash devops-ai-skill/scripts/setup.sh --gemini
bash devops-ai-skill/scripts/setup.sh --antigravity

# 移除所有安裝
bash devops-ai-skill/scripts/setup.sh --uninstall
```

</details>

<details>
<summary><strong>Marketplace（僅 Claude Code）</strong></summary>

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
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

> **注意**：`npx skills add` 僅安裝 8 個 Skills（SKILL.md）。如需完整體驗（Horus/Zeus Agent + 14 條流水線），請使用**一鍵安裝**或 **Marketplace** 方式。

</details>

## 平台支援

| 功能 | Claude Code | OpenAI Codex | Gemini CLI | Antigravity |
|------|-------------|--------------|------------|-------------|
| 全域 Agents | `~/.claude/agents/` | `~/.codex/instructions.md` | `~/.gemini/agents/` | `~/.agents/skills/` |
| 全域 Skills | `~/.claude/skills/` | `~/.codex/skills/` | `~/.gemini/skills/` | 共用 `~/.gemini/skills/` |
| 命令面板 | — | — | `~/.gemini/commands/devops/` | — |
| 工作流 | — | — | — | `~/.agents/workflows/` |
| 入口檔 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `.agents/rules/` |
| Skills 格式 | SKILL.md（原生） | SKILL.md（原生） | SKILL.md（原生） | SKILL.md（原生） |
| 流水線觸發 | `*cmd` | `*cmd` | 命令面板 `devops:` | `/workflow-name` |
| Bash 執行 | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) | Yes |

## 工具安裝

一鍵安裝所有必要工具，支援 macOS (Homebrew)、Linux (apt/snap)、Windows (winget/choco/scoop)、Python (uv/pip)：

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

| 工具 | 等級 | macOS (brew) | Linux (apt/snap) | Windows (winget) | 說明 |
|------|------|-------------|-------------------|------------------|------|
| node | 必要 | `brew install node` | `apt-get install nodejs` | `winget install OpenJS.NodeJS.LTS` | postinstall 執行環境 |
| git | 必要 | `brew install git` | `apt-get install git` | `winget install Git.Git` | 版本控制 |
| kubectl | 必要 | `brew install kubectl` | `snap install kubectl` | `winget install Kubernetes.kubectl` | K8s CLI |
| jq | 必要 | `brew install jq` | `apt-get install jq` | `winget install jqlang.jq` | JSON 處理 |
| yq | 建議 | `brew install yq` | `snap install yq` | `winget install MikeFarah.yq` | YAML 處理 |
| python3 | 建議 | `brew install python3` | `apt-get install python3` | `winget install Python.Python.3.12` | 版本驗證腳本 |
| curl | 建議 | `brew install curl` | `apt-get install curl` | `winget install cURL.cURL` | 遠端版本檢查 |

### Horus 工具（IaC）

| 工具 | 等級 | macOS (brew) | Windows (winget/choco) | pip | 說明 |
|------|------|-------------|------------------------|-----|------|
| terraform | 必要 | `brew install terraform` | `winget install Hashicorp.Terraform` | — | IaC 引擎 |
| helm | 必要 | `brew install helm` | `winget install Helm.Helm` | — | Helm Chart 管理 |
| tflint | 建議 | `brew install tflint` | `choco install tflint` | — | Terraform Lint |
| tfsec | 建議 | `brew install tfsec` | `choco install tfsec` | — | Terraform 安全掃描 |
| pre-commit | 建議 | — | — | `pip install pre-commit` | Git Hook 管理 |

### Zeus 工具（GitOps）

| 工具 | 等級 | macOS (brew) | Windows (choco/scoop) | pip | 說明 |
|------|------|-------------|------------------------|-----|------|
| kustomize | 必要 | `brew install kustomize` | `scoop install kustomize` | — | Kustomize 建置 |
| yamllint | 建議 | — | — | `pip install yamllint` | YAML Lint |
| kubeconform | 建議 | `brew install kubeconform` | `scoop install kubeconform` | — | K8s 資源驗證 |
| kube-score | 建議 | `brew install kube-score` | — | — | K8s 最佳實踐 |
| kube-linter | 建議 | `brew install kube-linter` | — | — | K8s Lint |
| polaris | 建議 | `brew install FairwindsOps/tap/polaris` | — | — | K8s 政策檢查 |
| pluto | 建議 | `brew install FairwindsOps/tap/pluto` | — | — | 廢棄 API 偵測 |
| conftest | 建議 | `brew install conftest` | — | — | 政策測試 |
| checkov | 建議 | — | — | `pip install checkov` | IaC 安全掃描 |
| trivy | 建議 | `brew install trivy` | `choco install trivy` | — | 漏洞掃描 |
| gitleaks | 建議 | `brew install gitleaks` | `choco install gitleaks` | — | 機密偵測 |
| d2 | 建議 | `brew install d2` | `scoop install d2` | — | 架構圖生成 |

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
│   ├── commands/devops/          # 命令面板 TOML 檔
│   │   ├── agents/               # 2 agent 啟動命令
│   │   └── pipelines/            # 16 pipeline 命令
│   └── extensions/devops/
│       └── gemini-extension.json
│
├── .agents/                     # Google Antigravity 平台
│   ├── rules/devops.md
│   ├── skills/
│   │   ├── horus/SKILL.md
│   │   ├── zeus/SKILL.md
│   │   └── (8 skill symlinks)
│   └── workflows/               # symlinks → prompts/
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
│   ├── setup.sh                    # 統一安裝腳本（推薦）
│   ├── install-tools.sh
│   ├── version-check.sh
│   └── setup/
│       ├── setup-claude.sh         # 平台專用（內部安裝）
│       ├── setup-codex.sh
│       ├── setup-gemini.sh
│       └── setup-antigravity.sh
│
├── .claude-plugin/              # Claude Code marketplace
│   ├── plugin.json
│   └── marketplace.json
│
└── docs/
    ├── quick-start.md           # 5 分鐘快速上手
    ├── setup.md                 # 詳細安裝指南
    └── guide/                   # 教學截圖
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
git checkout v<version>

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
