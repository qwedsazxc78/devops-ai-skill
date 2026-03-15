# Setup Guide — DevOps AI Skill Pack

[English](#english) | [繁體中文](#繁體中文)

---

<a id="english"></a>

## English

### Prerequisites

- Git
- One of: Claude Code, OpenAI Codex CLI, Google Gemini CLI, or Google Antigravity
- DevOps tools (see Tool Check section below)

### One-Click Install (recommended)

Run from your project root:

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
bash devops-ai-skill/scripts/setup.sh --all
```

This creates symlinks from your project's platform directories (`.claude/skills/`, `.claude/agents/`, `.codex/skills/`, `.gemini/agents/`, `.agents/`) into the `devops-ai-skill/` subdirectory. It also appends a DevOps section to your existing entry files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`).

#### Interactive Mode

```bash
bash devops-ai-skill/scripts/setup.sh
```

Prompts you to select which platforms to install.

#### Platform-Specific

```bash
bash devops-ai-skill/scripts/setup.sh --claude
bash devops-ai-skill/scripts/setup.sh --codex
bash devops-ai-skill/scripts/setup.sh --gemini
bash devops-ai-skill/scripts/setup.sh --antigravity
```

#### Uninstall

```bash
bash devops-ai-skill/scripts/setup.sh --uninstall
```

Removes all symlinks. Entry file sections (marked with `<!-- devops-ai-skill -->`) must be removed manually.

### Marketplace (Claude Code only)

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
```

### Cross-Platform (npx skills)

```bash
npx skills add qwedsazxc78/devops-ai-skill
```

Auto-detects installed AI agents and copies skills to the appropriate directories.

> **Note**: `npx skills add` installs 8 skills only. For the full experience (agents + 14 pipelines), use the **One-Click Install**.

### Tool Check

After installation, verify DevOps tools:

**In Claude Code:**
Use the tool check pipeline or read `prompts/shared/tool-check.md`

**In any terminal:**
```bash
bash scripts/install-tools.sh
```

### Version Management

Check current version:
```bash
bash scripts/version-check.sh
```

Update to latest:
```bash
git pull origin main
```

Pin to specific version:
```bash
git checkout v1.0.0
```

List available versions:
```bash
git tag -l "v*" --sort=-version:refname
```

### Global Install (recommended for multi-repo teams)

Instead of per-repo symlinks, install skills and agents **globally** so they are available across ALL projects.

```bash
# Auto-detect installed CLIs and install
bash scripts/install-global.sh

# Or target specific platforms
bash scripts/install-global.sh --claude
bash scripts/install-global.sh --gemini
bash scripts/install-global.sh --all
```

#### Global paths per platform

| Platform | Agents | Skills |
|----------|--------|--------|
| Claude Code | `~/.claude/agents/` | `~/.claude/skills/` |
| Codex CLI | `~/.codex/instructions.md` | `~/.codex/skills/` |
| Gemini CLI | `~/.gemini/agents/` | `~/.gemini/skills/` |
| Antigravity | `~/.agents/skills/` | `~/.agents/skills/` |

#### Updating after changes

```bash
# 1. Update source (edit files or pull latest)
cd devops-ai-skill
git pull origin main

# 2. Re-run global install (auto-detects platforms, skips unchanged files)
bash scripts/install-global.sh
```

> **Note**: Re-run the installer after updating source files to sync changes to all platforms.

#### Status & Uninstall

```bash
bash scripts/install-global.sh --status     # Check what's installed where
bash scripts/install-global.sh --uninstall   # Remove all global installations
```

### As Git Submodule

```bash
git submodule add https://github.com/qwedsazxc78/devops-ai-skill.git .devops-ai-skill
git submodule update --remote    # Update to latest
```

---

<a id="繁體中文"></a>

## 繁體中文

### 先決條件

- Git
- 以下其一：Claude Code、OpenAI Codex CLI、Google Gemini CLI 或 Google Antigravity
- DevOps 工具（見下方工具檢查區段）

### 一鍵安裝（推薦）

在你的專案根目錄執行：

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
bash devops-ai-skill/scripts/setup.sh --all
```

此腳本會建立 symlink 從你專案的平台目錄指向 `devops-ai-skill/`，並在入口檔（`CLAUDE.md`、`AGENTS.md`、`GEMINI.md`）附加 DevOps 區段。

#### 互動模式

```bash
bash devops-ai-skill/scripts/setup.sh
```

#### 特定平台

```bash
bash devops-ai-skill/scripts/setup.sh --claude
bash devops-ai-skill/scripts/setup.sh --codex
bash devops-ai-skill/scripts/setup.sh --gemini
bash devops-ai-skill/scripts/setup.sh --antigravity
```

#### 移除安裝

```bash
bash devops-ai-skill/scripts/setup.sh --uninstall
```

### Marketplace（僅 Claude Code）

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
```

### 跨平台（npx skills）

```bash
npx skills add qwedsazxc78/devops-ai-skill
npx skills update
```

> **注意**：`npx skills add` 僅安裝 8 個 Skills。如需完整體驗（Agent + 14 條流水線），請使用**一鍵安裝**。

### 版本管理

```bash
# 檢查版本
bash scripts/version-check.sh

# 更新至最新
git pull origin main

# 固定特定版本
git checkout v1.0.0

# 列出所有版本
git tag -l "v*" --sort=-version:refname
```

### 全域安裝（推薦多 repo 團隊使用）

將 skills 和 agents 安裝至**全域**，所有專案共用，無需 per-repo symlinks。

```bash
# 自動偵測已安裝的 CLI 並安裝
bash scripts/install-global.sh

# 指定平台
bash scripts/install-global.sh --claude
bash scripts/install-global.sh --gemini
bash scripts/install-global.sh --all
```

#### 各平台全域路徑

| 平台 | Agents | Skills |
|------|--------|--------|
| Claude Code | `~/.claude/agents/` | `~/.claude/skills/` |
| Codex CLI | `~/.codex/instructions.md` | `~/.codex/skills/` |
| Gemini CLI | `~/.gemini/agents/` | `~/.gemini/skills/` |
| Antigravity | `~/.agents/skills/` | `~/.agents/skills/` |

#### 更新流程

```bash
# 1. 更新原始碼（修改或 pull 最新版本）
cd devops-ai-skill
git pull origin main

# 2. 重跑全域安裝（自動偵測平台，跳過未變動檔案）
bash scripts/install-global.sh
```

> **注意**：更新 source 後需重跑安裝腳本，以同步變更至所有平台。

#### 狀態查詢與移除

```bash
bash scripts/install-global.sh --status     # 查看各平台安裝狀態
bash scripts/install-global.sh --uninstall   # 移除所有全域安裝
```

### 作為 Git Submodule

```bash
git submodule add https://github.com/qwedsazxc78/devops-ai-skill.git .devops-ai-skill
git submodule update --remote
```
