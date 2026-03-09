# Setup Guide — DevOps AI Skill Pack

[English](#english) | [繁體中文](#繁體中文)

---

<a id="english"></a>

## English

### Prerequisites

- Git
- One of: Claude Code, OpenAI Codex CLI, or Google Gemini CLI
- DevOps tools (see Tool Check section below)

### Claude Code Setup

#### Marketplace Install (recommended)

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

The plugin is auto-loaded. Skills are available immediately.

#### Git Install

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-claude.sh
```

The setup script creates symlinks from `.claude/skills/` to the shared `skills/` directory.

To use: `claude --plugin-dir ./devops-ai-skill`

#### Global Install

```bash
cp devops-ai-skill/CLAUDE.md ~/.claude/CLAUDE.md
```

### OpenAI Codex CLI Setup

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-codex.sh
```

The setup script:
1. Creates `.codex/skills/` symlinks to shared `skills/`
2. `AGENTS.md` at project root is auto-loaded by Codex CLI

Skill scoping:
- Workspace: `.codex/skills/` (this project)
- User: `~/.codex/skills/` (all projects)

### Google Gemini CLI Setup

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-gemini.sh
```

The setup script verifies:
1. `GEMINI.md` entry point exists
2. `.gemini/agents/*.md` subagent definitions exist
3. `.gemini/extensions/devops/gemini-extension.json` exists

`GEMINI.md` is auto-loaded by Gemini CLI.

### Cross-Platform (npx skills)

```bash
npx skills add qwedsazxc78/devops-ai-skill
```

Auto-detects installed AI agents and copies skills to the appropriate directories.

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
- 以下其一：Claude Code、OpenAI Codex CLI 或 Google Gemini CLI
- DevOps 工具（見下方工具檢查區段）

### Claude Code 安裝

#### Marketplace 安裝（推薦）

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-go
```

外掛自動載入，skills 立即可用。

#### Git 安裝

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-claude.sh
```

使用方式：`claude --plugin-dir ./devops-ai-skill`

### OpenAI Codex CLI 安裝

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-codex.sh
```

### Google Gemini CLI 安裝

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/setup/setup-gemini.sh
```

### 跨平台（npx skills）

```bash
npx skills add qwedsazxc78/devops-ai-skill
npx skills update
```

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

### 作為 Git Submodule

```bash
git submodule add https://github.com/qwedsazxc78/devops-ai-skill.git .devops-ai-skill
git submodule update --remote
```
