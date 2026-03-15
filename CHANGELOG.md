# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-03-16

### Added

- 全域安裝腳本 `install-global.sh`：一次安裝至 `~/.claude/`、`~/.codex/`、`~/.gemini/`、`~/.agents/`
- 統一安裝腳本 `setup.sh`：支援一鍵安裝至目標專案（per-repo symlinks）
- Gemini CLI 命令面板支援：18 個 TOML 檔（`.gemini/commands/devops/`）
- Antigravity 工作流全域安裝：17 個 pipeline 檔案複製至 `~/.agents/workflows/`
- Gemini extensions 全域安裝（`~/.gemini/extensions/devops/`）
- 新增 22 項 Gemini commands TOML 結構測試

### Fixed

- 修正 Gemini 全域安裝 skills 缺失（移除不存在的 `gemini skills link` 指令）
- 修正 `|| true` 導致 fallback 永遠不觸發的 bash bug
- 修正 `$DO_VAR && func || true` 隱藏錯誤，改用 `if/then`
- 修正 Gemini/Antigravity skills 衝突：Antigravity 自動清除與 `~/.gemini/skills/` 重複的 skill
- 修正 docs 中所有 `devops-go` 錯字為 `devops-ai-skill`
- 移除所有文件中不存在的 `gemini skills link` 引用

### Changed

- README 三語平台支援表重構：新增命令面板、工作流、全域路徑欄位
- README 安裝方式改為全域安裝優先（per-repo 改為 legacy）
- 專案結構樹新增 `.gemini/commands/devops/` 目錄

## [1.1.0] - 2026-03-10

### Added

- npm 套件包含完整 agent 定義檔（`.claude/agents/`、`.gemini/agents/`）
- npm 套件包含平台設定檔（`.claude-plugin/`、`.codex/`、`.gemini/extensions/`）
- npm 套件包含 `docs/`、`CHANGELOG.md`
- postinstall 自動複製 agents、prompts、entry files 至專案根目錄
- README 新增 npm version 與 GitHub Release 動態徽章
- CHANGELOG 底部加入 Keep a Changelog 標準比較連結
- `version-bump.sh` 自動建立 CHANGELOG 條目與版本比較連結
- `release.sh` 發版前驗證 CHANGELOG 條目存在
- `release.yml` 自動附加 npm/tag/changelog 交叉連結至 GitHub Release

## [1.0.0] - 2026-03-09

### Added

- Cross-platform DevOps AI Skill Pack
- **Horus** IaC Operations Engineer agent (Terraform + Helm + GKE)
- **Zeus** GitOps Engineer agent (Kustomize + ArgoCD)
- 8 shared skills following Open Agent Skills standard (SKILL.md)
  - terraform-validate, terraform-security, helm-version-upgrade, helm-scaffold
  - cicd-enhancer, kustomize-resource-validation, yaml-fix-suggestions, repo-detect
- 14 pipeline definitions in `prompts/` (7 Horus + 7 Zeus)
- Platform support: Claude Code, OpenAI Codex CLI, Google Gemini CLI
- Platform entry points: CLAUDE.md, AGENTS.md, GEMINI.md
- Setup scripts for each platform (`scripts/setup/`)
- Claude Code marketplace compatibility (`.claude-plugin/`)
- Cross-platform version check (`scripts/version-check.sh`)
- Tool installer (`scripts/install-tools.sh`)
- Bilingual documentation (EN + 繁體中文)

<!-- Links -->
[1.2.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qwedsazxc78/devops-ai-skill/releases/tag/v1.0.0
