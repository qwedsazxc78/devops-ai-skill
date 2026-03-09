# Migration Guide

[English](#english) | [繁體中文](#繁體中文)

---

<a id="english"></a>

## English

### Upgrading Between Versions

#### Patch Updates (1.0.x → 1.0.y)

No action needed. Pull latest and continue:

```bash
git pull origin main
```

#### Minor Updates (1.x → 1.y)

New skills or pipelines may be added. Update and re-run setup:

```bash
git pull origin main
bash scripts/setup/setup-claude.sh   # Re-sync symlinks
bash scripts/setup/setup-codex.sh    # If using Codex
bash scripts/setup/setup-gemini.sh   # If using Gemini
```

#### Major Updates (x.0 → y.0)

Breaking changes may affect skill names, pipeline structure, or entry point format.

**Before upgrading:**
1. Read the release notes for the target version
2. Back up any customized skills or prompts
3. Check the breaking changes list below

**Upgrade steps:**
```bash
git fetch origin main
git diff HEAD..origin/main -- skills/ prompts/ CLAUDE.md AGENTS.md GEMINI.md
git pull origin main
bash scripts/setup/setup-claude.sh
```

### Breaking Changes Log

#### v1.0.0 (Initial Release)

No breaking changes — this is the initial release.

### Rollback

```bash
# List available versions
git tag -l "v*" --sort=-version:refname

# Rollback to specific version
git checkout v1.0.0

# Re-run setup after rollback
bash scripts/setup/setup-claude.sh
```

---

<a id="繁體中文"></a>

## 繁體中文

### 版本升級

#### Patch 更新（1.0.x → 1.0.y）

無需額外動作，拉取最新即可：

```bash
git pull origin main
```

#### Minor 更新（1.x → 1.y）

可能新增 skills 或 pipelines。更新後重新執行 setup：

```bash
git pull origin main
bash scripts/setup/setup-claude.sh
bash scripts/setup/setup-codex.sh    # 如有使用 Codex
bash scripts/setup/setup-gemini.sh   # 如有使用 Gemini
```

#### Major 更新（x.0 → y.0）

可能有破壞性變更。升級前請：
1. 閱讀目標版本的 release notes
2. 備份自訂的 skills 或 prompts
3. 檢查破壞性變更清單

### 回滾

```bash
git tag -l "v*" --sort=-version:refname    # 列出版本
git checkout v1.0.0                         # 回滾
bash scripts/setup/setup-claude.sh          # 重新設定
```
