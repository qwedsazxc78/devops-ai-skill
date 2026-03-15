# DevOps AI Skill Pack — Cross-Platform Implementation Plan

[English](#english) | [繁體中文](#繁體中文)

---

<a id="english"></a>

## English

This document tracks the implementation status of the cross-platform DevOps AI Skill Pack (`devops-ai-skill`), supporting **Claude Code**, **OpenAI Codex CLI**, and **Google Gemini CLI**.

> **Goal:** One source of truth for DevOps skills, agents, and workflows — distributed to three AI coding assistants with platform-native experiences and seamless version upgrades.

> **Architecture:** [Agent Skills](https://agentskills.io/specification) open standard (SKILL.md) used for all skills. Platform-specific adapters handle agent routing and entry points only.

---

## Current State

| Dimension | Status |
|-----------|--------|
| **Repo** | `devops-ai-skill` (new cross-platform repo) |
| **Version** | v1.0.0 (semver, VERSION file as source of truth) |
| **Platforms** | Claude Code + OpenAI Codex CLI + Google Gemini CLI |
| **Distribution** | Git clone + Claude Marketplace + npx skills + npm |
| **Agents** | 2 (Horus IaC, Zeus GitOps) |
| **Skills** | 8 (SKILL.md with YAML frontmatter, versioned) |
| **Pipelines** | 14 (7 Horus + 7 Zeus) in `prompts/` |
| **Shared Utils** | 3 (repo-detect, report-format, tool-check) |
| **CI/CD** | GitHub Actions (structure tests + version consistency + security scan + release automation) |
| **Tests** | 116 (structure, cross-platform, cross-references, version, security) |

---

## Architecture

### Directory Structure

```
devops-ai-skill/
│
├── CLAUDE.md                            ← Claude Code entry point
├── AGENTS.md                            ← OpenAI Codex entry point
├── GEMINI.md                            ← Gemini CLI entry point
├── VERSION                              ← Version source of truth (1.0.0)
├── package.json                         ← npm/npx distribution
├── MIGRATION.md                         ← Version upgrade guide
│
├── .claude/                             ← Claude Code platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md                     ← Agent definition (YAML frontmatter, no model:)
│   │   └── zeus.md
│   └── skills/                          ← Symlinks to skills/
│
├── .codex/                              ← OpenAI Codex platform
│   ├── config.toml
│   └── skills/                          ← Symlinks to skills/
│
├── .gemini/                             ← Google Gemini platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md                     ← Gemini subagent format
│   │   └── zeus.md
│   └── extensions/devops/
│       └── gemini-extension.json        ← Generated from skills
│
├── skills/                              ← Shared Skills (Open Agent Skills standard)
│   ├── terraform-validate/SKILL.md      ← All platforms use directly
│   ├── terraform-security/SKILL.md
│   ├── helm-version-upgrade/SKILL.md
│   ├── helm-scaffold/SKILL.md
│   ├── cicd-enhancer/SKILL.md
│   ├── kustomize-resource-validation/SKILL.md
│   ├── yaml-fix-suggestions/SKILL.md
│   └── repo-detect/SKILL.md
│
├── prompts/                             ← Platform-neutral pipeline definitions
│   ├── horus/                           ← 7 Horus pipelines
│   │   ├── full-pipeline.md
│   │   ├── upgrade.md
│   │   ├── validate.md
│   │   ├── security.md
│   │   ├── new-module.md
│   │   ├── cicd.md
│   │   └── health.md
│   ├── zeus/                            ← 7 Zeus pipelines
│   │   ├── full-pipeline.md
│   │   ├── pre-merge.md
│   │   ├── health-check.md
│   │   ├── review.md
│   │   ├── onboard.md
│   │   ├── diagram.md
│   │   └── status.md
│   └── shared/                          ← 3 shared utilities
│       ├── repo-detect.md
│       ├── report-format.md
│       └── tool-check.md
│
├── scripts/
│   ├── install-tools.sh
│   ├── version-check.sh
│   ├── postinstall.js                   ← npm postinstall hook
│   └── setup/
│       ├── setup-claude.sh
│       ├── setup-codex.sh
│       └── setup-gemini.sh
│
├── .claude-plugin/                      ← Claude Code marketplace
│   ├── plugin.json
│   └── marketplace.json
│
├── .github/workflows/                   ← CI/CD
│   ├── ci.yml                           ← Structure tests + version + security
│   └── release.yml                      ← Tag-based GitHub Releases
│
├── tests/
│   └── test-structure.sh                ← 116 tests
│
├── docs/
│   ├── setup.md                         ← Multi-platform setup guide
│   ├── cross-platform-migration-plan.md ← This file
│   └── images/
│       ├── logo.png
│       └── logo.svg
│
├── CHANGELOG.md
└── README.md                            ← Bilingual (EN + ZH-TW)
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Repo strategy** | Separate repo (`devops-ai-skill`) | Clean cross-platform design from scratch; original `devops-plugin` stays as Claude-only |
| **Skills standard** | Open Agent Skills (SKILL.md) | All 3 platforms natively support the same standard |
| **Pipeline extraction** | `prompts/` directory (pure markdown) | Platform-neutral; `commands/*.md` had Claude-specific activation blocks |
| **Agent format** | Platform-specific adapters per directory | `.claude/agents/` (YAML frontmatter), `.gemini/agents/` (plain markdown) |
| **Version source** | `VERSION` file + all config files | Single source of truth, CI enforces consistency |
| **Distribution** | Git + npm + npx skills + Claude Marketplace | Multiple channels for different user preferences |

---

## Platform Compatibility Matrix

### Skills Sharing Strategy

```
skills/terraform-validate/SKILL.md
(Open Agent Skills standard — YAML frontmatter + Markdown body)
                │
   ┌────────────┼────────────┐
   │            │            │
Claude Code  Codex CLI   Gemini CLI
(native)     (native)    (via extension)
   │            │            │
.claude/     .codex/      .gemini/
skills/      skills/      extensions/
(symlink)    (symlink)    (json mapping)
```

### Feature Parity Table

| Feature | Claude Code | Codex CLI | Gemini CLI |
|---------|-------------|-----------|------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Global location | `~/.claude/CLAUDE.md` | `~/.codex/AGENTS.md` | `~/.gemini/GEMINI.md` |
| SKILL.md loading | Native | Native | Via extensions |
| Skills directory | `.claude/skills/` | `.codex/skills/` | `.gemini/extensions/` |
| Agent definitions | `.claude/agents/*.md` | Via AGENTS.md routing | `.gemini/agents/*.md` |
| Skill invocation | `/skill-name` | `$skill-name` | `/subagents` |
| Import syntax | In CLAUDE.md references | config.toml fallback | `@file.md` imports |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) |
| Auto-trigger skills | Yes (SKILL.md config) | Yes | Via GEMINI.md instructions |

---

## Distribution Channels

| Channel | Versioning | Cross-platform | Auto-update | Best For |
|---------|-----------|----------------|-------------|----------|
| **Claude Marketplace** | Marketplace-managed | Claude only | Automatic | Claude Code users |
| **`npx skills`** | Git-based | All agents | `npx skills update` | Individual developers |
| **npm package** | Semver | All (postinstall hooks) | `npm update` | Enterprise / private registry |
| **Git clone** | Tag-based | All | `git pull` | Development / contribution |
| **Git submodule** | SHA pinning | All | `git submodule update` | Team repos |

---

## Implementation Phases

### Phase 1: Foundation — COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| Create `devops-ai-skill` repo | Done | Separate repo from `devops-plugin` |
| Create `VERSION` file | Done | `1.0.0` |
| Migrate 8 skills to `skills/` | Done | Platform-agnostic (no `model:` field) |
| Add `version:` to all SKILL.md | Done | `version: "1.0.0"` in frontmatter |
| Extract pipelines to `prompts/` | Done | 7 Horus + 7 Zeus + 3 shared |
| Create `CLAUDE.md` entry point | Done | References `.claude/agents/` and `prompts/` |
| Create `AGENTS.md` entry point | Done | Codex routing with `$skill` syntax |
| Create `GEMINI.md` entry point | Done | `@import` syntax for agents |
| Create `.claude/agents/*.md` | Done | YAML frontmatter, no `model:` field |
| Create `.gemini/agents/*.md` | Done | Plain markdown subagent format |
| Create `gemini-extension.json` | Done | Maps all 8 skills |
| Create setup scripts (3) | Done | `setup-claude.sh`, `setup-codex.sh`, `setup-gemini.sh` |
| Create `version-check.sh` | Done | Compares local vs GitHub releases |
| Create `package.json` | Done | npm/npx distribution with postinstall |
| Update `README.md` | Done | Bilingual, 4 install methods |
| Create `docs/setup.md` | Done | Detailed per-platform guide |
| Create `MIGRATION.md` | Done | Version upgrade guide |
| Create `CHANGELOG.md` | Done | v1.0.0 initial entry |
| Create `.claude-plugin/` | Done | Marketplace compatibility |
| Copy logo assets | Done | `docs/images/logo.png` + `.svg` |
| Create test suite | Done | 116 tests, 11 sections |

### Phase 2: CI/CD & Stabilization — COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| GitHub Actions CI | Done | Structure tests + version consistency + security scan |
| GitHub Actions Release | Done | Tag-based release automation |
| Cross-platform test suite | Done | `tests/test-structure.sh` (116 tests) |
| `npm postinstall` hook | Done | Auto-detects agents, shows setup commands |

### Phase 2b: Stabilization — PENDING (Requires Manual Testing)

| Task | Status | Notes |
|------|--------|-------|
| Validate on Codex CLI | Pending | End-to-end testing with OpenAI Codex |
| Validate on Gemini CLI | Pending | End-to-end testing with Google Gemini |
| `npx skills` compatibility test | Pending | Verify `npx skills add` works |
| Version check at agent startup | Planned | Non-blocking notification integration |

### Phase 3: Distribution Optimization — PARTIALLY COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| GitHub Releases automation | Done | `release.yml` workflow |
| Tag-based versioning | Ready | CI validates tag matches VERSION |
| npm package publishing | Ready | `package.json` configured |
| `npx skills` compatibility | Ready | Standard SKILL.md layout |
| Community templates | Planned | Example integrations for common repos |
| `.well-known/skills/` endpoint | Planned | For documentation site discovery |
| Multi-language skill descriptions | Planned | EN + ZH-TW in SKILL.md |

---

## Version Management

### Versioning Scheme

```
MAJOR.MINOR.PATCH
  │     │     │
  │     │     └── Bug fixes, typo corrections, checklist updates
  │     └──────── New skills, new pipelines, new platform support
  └────────────── Breaking changes (skill rename, removed pipelines, restructure)
```

### Version is tracked in these files (kept in sync by CI):

1. `VERSION` file (single source of truth)
2. `.claude-plugin/plugin.json` → `"version"` field
3. `.claude-plugin/marketplace.json` → `metadata.version` AND `plugins[0].version`
4. `.gemini/extensions/devops/gemini-extension.json` → `"version"` field
5. `package.json` → `"version"` field
6. `CHANGELOG.md` → latest entry header
7. Each `SKILL.md` → `version:` field in YAML frontmatter

### Version Bump Procedure

```bash
# 1. Update VERSION file
echo "1.1.0" > VERSION

# 2. Update all config files (must match VERSION)
# - .claude-plugin/plugin.json
# - .claude-plugin/marketplace.json (metadata.version + plugins[0].version)
# - .gemini/extensions/devops/gemini-extension.json
# - package.json

# 3. Update CHANGELOG.md with new entry

# 4. Commit
git add -A
git commit -m "chore: bump version to 1.1.0"

# 5. Tag and push
git tag v1.1.0
git push origin main --tags
# → GitHub Actions creates release automatically
```

---

## Relationship to devops-plugin

| Aspect | `devops-plugin` | `devops-ai-skill` |
|--------|----------------|-------------------|
| **Purpose** | Claude Code plugin (original) | Cross-platform skill pack (new) |
| **Platforms** | Claude Code only | Claude + Codex + Gemini |
| **Skills** | Same 8 skills | Same 8 skills (with `version:` field) |
| **Agents** | `agents/*.md` (with `model:`) | Platform-specific dirs (no `model:`) |
| **Commands** | `commands/*.md` (Claude-specific) | `prompts/*.md` (platform-neutral) |
| **Distribution** | Claude Marketplace + git | Marketplace + git + npm + npx |
| **Version** | 1.1.0 | 1.0.0 |

Both repos can coexist:
- **Claude Code users** can use either repo (devops-plugin via marketplace, devops-ai-skill via git)
- **Codex/Gemini users** use devops-ai-skill only
- Future: devops-plugin may adopt devops-ai-skill as upstream source

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Agent Skills spec evolves | High | Pin to spec version in SKILL.md, test all 3 platforms in CI |
| Platform-specific SKILL.md extensions diverge | Medium | Use only common subset of frontmatter fields |
| Version drift between repos | Medium | Single VERSION file, CI enforces consistency |
| `npx skills` changes install behavior | Medium | Git clone as fallback; setup scripts are independent |
| Symlinks not supported on Windows | Low | Setup scripts fall back to file copy |
| User forgets to update | Low | Version check at startup, `npx skills check` |

---

## Quick Reference: Install Flow

### Claude Code (Marketplace)
```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
```

### Claude Code (Git)
```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-claude.sh
claude --plugin-dir ./devops-ai-skill
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

### Cross-Platform (npx skills)
```bash
npx skills add qwedsazxc78/devops-ai-skill
npx skills update
```

### Update (All Platforms)
```bash
cd devops-ai-skill
bash scripts/version-check.sh
git pull origin main
bash scripts/setup/setup-claude.sh    # Re-sync
```

---

---

<a id="繁體中文"></a>

## 繁體中文

本文件追蹤跨平台 DevOps AI 技能包（`devops-ai-skill`）的實作狀態，支援 **Claude Code**、**OpenAI Codex CLI** 和 **Google Gemini CLI**。

> **目標：** 一份 DevOps 技能、Agent 和工作流程的單一真相來源，分發至三個 AI 編程助手，提供平台原生體驗和無縫版本升級。

---

## 現狀

| 維度 | 狀態 |
|------|------|
| **Repo** | `devops-ai-skill`（新跨平台 repo） |
| **版本** | v1.0.0（語意版本控制，VERSION 檔案為真相來源） |
| **平台** | Claude Code + OpenAI Codex CLI + Google Gemini CLI |
| **分發** | Git clone + Claude Marketplace + npx skills + npm |
| **Agent** | 2 個（Horus IaC、Zeus GitOps） |
| **Skills** | 8 個（SKILL.md + YAML frontmatter，含版本號） |
| **Pipelines** | 14 個（7 Horus + 7 Zeus）在 `prompts/` |
| **CI/CD** | GitHub Actions（結構測試 + 版本一致性 + 安全掃描 + Release 自動化） |
| **測試** | 116 個（結構、跨平台、交叉引用、版本、安全性） |

---

## 架構

### 目錄結構

```
devops-ai-skill/
├── CLAUDE.md                    ← Claude Code 入口
├── AGENTS.md                    ← OpenAI Codex 入口
├── GEMINI.md                    ← Gemini CLI 入口
├── VERSION                      ← 版本真相來源
├── package.json                 ← npm/npx 分發
├── MIGRATION.md                 ← 版本升級指南
│
├── .claude/                     ← Claude Code 平台
│   ├── settings.json
│   ├── agents/{horus,zeus}.md
│   └── skills/ → symlink
│
├── .codex/                      ← Codex 平台
│   ├── config.toml
│   └── skills/ → symlink
│
├── .gemini/                     ← Gemini 平台
│   ├── settings.json
│   ├── agents/{horus,zeus}.md
│   └── extensions/devops/gemini-extension.json
│
├── skills/                      ← 共用 Skills（8 個）
├── prompts/                     ← 平台中立 Pipeline 定義（17 個）
├── scripts/                     ← 工具與設定腳本
├── .claude-plugin/              ← Claude Marketplace
├── .github/workflows/           ← CI/CD
├── tests/                       ← 116 個測試
└── docs/                        ← 文件
```

### 關鍵設計決策

| 決策 | 選擇 | 原因 |
|------|------|------|
| **Repo 策略** | 獨立 repo（`devops-ai-skill`） | 從頭設計跨平台；原始 `devops-plugin` 保持 Claude 專用 |
| **Skills 標準** | Open Agent Skills（SKILL.md） | 三平台原生支援 |
| **Pipeline 提取** | `prompts/` 目錄（純 Markdown） | 平台中立；`commands/*.md` 含 Claude 特定啟動區塊 |
| **版本來源** | `VERSION` 檔案 + 所有設定檔 | 單一真相來源，CI 強制一致性 |
| **分發方式** | Git + npm + npx skills + Marketplace | 多管道 |

---

## 平台相容性

### Skills 共用策略

```
skills/terraform-validate/SKILL.md
（Open Agent Skills 標準）
                │
   ┌────────────┼────────────┐
   │            │            │
Claude Code  Codex CLI   Gemini CLI
（原生）      （原生）     （透過 extension）
   │            │            │
.claude/     .codex/      .gemini/
skills/      skills/      extensions/
（symlink）   （symlink）   （json 對應）
```

### 功能對照表

| 功能 | Claude Code | Codex CLI | Gemini CLI |
|------|-------------|-----------|------------|
| 指令檔 | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` |
| Skills 目錄 | `.claude/skills/` | `.codex/skills/` | `.gemini/extensions/` |
| Agent 定義 | `.claude/agents/*.md` | 透過 AGENTS.md | `.gemini/agents/*.md` |
| Skill 呼叫語法 | `/skill-name` | `$skill-name` | `/subagents` |
| Bash 執行 | 可以 | 可以（`!cmd`） | 可以（`run_shell_command`） |

---

## 實作階段

### 第一階段：基礎 — 完成

| 任務 | 狀態 |
|------|------|
| 建立 repo + 初始化 | Done |
| 遷移 8 個 skills（含 `version:` 欄位） | Done |
| 提取 14 個 pipelines 到 `prompts/` | Done |
| 建立三個入口檔（CLAUDE.md、AGENTS.md、GEMINI.md） | Done |
| 建立平台特定 Agent 定義 | Done |
| 建立 setup 腳本（3 個） | Done |
| 建立 `package.json` + postinstall | Done |
| 建立 `MIGRATION.md` | Done |
| 建立測試套件（116 個測試） | Done |
| 建立文件（README、setup、changelog） | Done |

### 第二階段：CI/CD 與穩定化 — 部分完成

| 任務 | 狀態 |
|------|------|
| GitHub Actions CI | Done |
| GitHub Actions Release | Done |
| Codex CLI 端到端測試 | 待驗證 |
| Gemini CLI 端到端測試 | 待驗證 |
| `npx skills` 相容性測試 | 待驗證 |

### 第三階段：分發優化 — 部分完成

| 任務 | 狀態 |
|------|------|
| GitHub Releases 自動化 | Done |
| npm 套件設定 | Done |
| 社群模板 | 計劃中 |
| 多語言 skill 描述 | 計劃中 |
| `.well-known/skills/` 端點 | 計劃中 |

---

## 版本管理

### 版本追蹤位置（CI 強制一致性）

1. `VERSION`（單一真相來源）
2. `.claude-plugin/plugin.json`
3. `.claude-plugin/marketplace.json`
4. `.gemini/extensions/devops/gemini-extension.json`
5. `package.json`
6. `CHANGELOG.md`
7. 各 `SKILL.md` 的 `version:` 欄位

### 版本升版流程

```bash
echo "1.1.0" > VERSION
# 更新所有設定檔的版本號
# 更新 CHANGELOG.md
git commit -m "chore: bump version to 1.1.0"
git tag v1.1.0
git push origin main --tags
# → GitHub Actions 自動建立 Release
```

---

## 與 devops-plugin 的關係

| 面向 | `devops-plugin` | `devops-ai-skill` |
|------|----------------|-------------------|
| 用途 | Claude Code 外掛（原始） | 跨平台技能包（新） |
| 平台 | 僅 Claude Code | Claude + Codex + Gemini |
| Skills | 相同 8 個 | 相同 8 個（含 `version:` 欄位） |
| 命令 | `commands/*.md`（Claude 特定） | `prompts/*.md`（平台中立） |
| 分發 | Marketplace + git | Marketplace + git + npm + npx |

兩個 repo 可共存：
- **Claude Code 使用者**可使用任一 repo
- **Codex/Gemini 使用者**僅使用 devops-ai-skill
- 未來：devops-plugin 可能採用 devops-ai-skill 作為上游來源

---

## 風險評估

| 風險 | 影響 | 緩解措施 |
|------|------|----------|
| Agent Skills 規範變更 | 高 | 固定規範版本，CI 測試三平台 |
| 平台 SKILL.md 擴展分歧 | 中 | 僅使用共同 frontmatter 欄位 |
| Repo 間版本漂移 | 中 | VERSION 檔案 + CI 一致性檢查 |
| Windows 不支援 symlink | 低 | Setup 腳本降級為檔案複製 |

---

## 快速參考：安裝流程

### Claude Code
```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
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
