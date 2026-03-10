# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
[1.1.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qwedsazxc78/devops-ai-skill/releases/tag/v1.0.0
