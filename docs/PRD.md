# PRD: 4-Platform Support + Cross-OS Tool Installation

> **Version**: 1.2.0
> **Date**: 2026-03-13
> **Status**: Draft

---

## 1. Background

DevOps AI Skill Pack currently supports 3 platforms in README/docs (Claude Code, OpenAI Codex, Gemini CLI) while a 4th platform (Google Antigravity) is already implemented in backend files but not exposed in user-facing documentation. Tool installation only supports macOS and Linux.

## 2. Goals

1. **4-Platform parity** — All user-facing docs reflect 4 platforms: Claude Code, OpenAI Codex, Gemini CLI, Google Antigravity
2. **Cross-OS tool installation** — Support Windows (winget/choco/scoop), macOS (brew), Linux (apt/snap)
3. **Scoped setup** — Install agents/skills/commands into a local target project for any of the 4 platforms
4. **Test coverage** — Structure tests validate all 4 platforms equally

---

## 3. Feature Spec

### 3.1 Tool Installation (`install-tools.sh`)

One-click installer for all DevOps CLI tools across 3 OS families.

#### Current State

| OS | Package Manager | Status |
|----|----------------|--------|
| macOS | Homebrew | ✅ Supported |
| Linux | apt / snap / yum | ✅ Supported |
| Windows | — | ❌ Not supported |
| Python | pip | ✅ Supported |

#### Target State

| OS | Package Manager | Status |
|----|----------------|--------|
| macOS | Homebrew | ✅ Supported |
| Linux | apt / snap / yum | ✅ Supported |
| Windows | winget (primary) / choco / scoop | 🆕 New |
| Python | pip / uv | ✅ Supported |

#### Windows Detection Logic

```bash
# Detect Windows (Git Bash / MSYS2 / WSL)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS="Windows" ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      OS="WSL"  # treat as Linux with Windows fallback
    else
      OS="Linux"
    fi ;;
  Darwin) OS="Darwin" ;;
esac
```

#### Windows Package Manager Detection

```bash
if command -v winget &>/dev/null; then
  PKG_MANAGER="winget"
elif command -v choco &>/dev/null; then
  PKG_MANAGER="choco"
elif command -v scoop &>/dev/null; then
  PKG_MANAGER="scoop"
fi
```

#### Tool Registry Update

Add `winget_cmd` column to tool registry:

```
"binary|category|tier|brew_cmd|apt_cmd|pip_cmd|winget_cmd"
```

#### Windows Install Commands

| Tool | winget | choco | scoop |
|------|--------|-------|-------|
| git | `winget install Git.Git` | `choco install git` | `scoop install git` |
| kubectl | `winget install Kubernetes.kubectl` | `choco install kubernetes-cli` | `scoop install kubectl` |
| jq | `winget install jqlang.jq` | `choco install jq` | `scoop install jq` |
| yq | `winget install MikeFarah.yq` | `choco install yq` | `scoop install yq` |
| terraform | `winget install Hashicorp.Terraform` | `choco install terraform` | `scoop install terraform` |
| tflint | — | `choco install tflint` | `scoop install tflint` |
| tfsec | — | `choco install tfsec` | `scoop install tfsec` |
| kustomize | — | `choco install kustomize` | `scoop install kustomize` |
| kubeconform | — | — | `scoop install kubeconform` |
| trivy | — | `choco install trivy` | `scoop install trivy` |
| gitleaks | — | `choco install gitleaks` | `scoop install gitleaks` |

> Tools without winget/choco/scoop packages: show `pip install` or manual download URL.

---

### 3.2 Platform Setup (`scripts/setup/`)

One-click setup to install agents, skills, and pipeline commands into a target project.

#### Architecture

```
install-tools.sh          → OS-level CLI tools (terraform, kubectl, etc.)
scripts/setup/
  setup-claude.sh          → .claude/skills/ symlinks
  setup-codex.sh           → .codex/skills/ symlinks
  setup-gemini.sh          → .gemini/ verification
  setup-antigravity.sh     → .agents/skills/ + .agents/workflows/ symlinks
```

#### Scope: Local Project Only

All setup scripts operate on the **current project directory** (local scope). Files are never installed globally.

| Method | Scope | What's Installed |
|--------|-------|-----------------|
| `npm install devops-ai-skill` | Local project | Copies files via postinstall.js |
| `npx skills add ...` | Local project | Skills only (8 SKILL.md files) |
| `git clone` + `setup-*.sh` | Local project | Full: agents + skills + pipelines |
| `pnpm setup:<platform>` | Local project | Symlinks for specified platform |

#### What Each Setup Installs

| Component | Claude Code | OpenAI Codex | Gemini CLI | Antigravity |
|-----------|-------------|--------------|------------|-------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `.agents/rules/devops.md` |
| Agent definitions | `.claude/agents/*.md` | via AGENTS.md | `.gemini/agents/*.md` | `.agents/skills/{horus,zeus}/SKILL.md` |
| Skills (8) | `.claude/skills/` symlinks | `.codex/skills/` symlinks | via extensions | `.agents/skills/` symlinks |
| Pipelines (14) | `prompts/` (direct read) | `prompts/` (direct read) | `prompts/` (direct read) | `.agents/workflows/` symlinks |
| Config | `.claude/settings.json` | `.codex/config.toml` | `.gemini/settings.json` | — |
| Plugin | `.claude-plugin/*.json` | — | `.gemini/extensions/` | — |

---

### 3.3 README Updates (3 Languages)

Update all 3 language sections (繁體中文, English, 简体中文) with:

#### 3.3.1 Badge

```
PLATFORMS-3 → PLATFORMS-4
```

#### 3.3.2 Description

```diff
-支援 Claude Code、OpenAI Codex CLI 和 Google Gemini CLI
+支援 Claude Code、OpenAI Codex CLI、Google Gemini CLI 和 Google Antigravity
```

#### 3.3.3 Quick Start — Add Antigravity Tab

```markdown
<details>
<summary><strong>Google Antigravity</strong></summary>

git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill && bash scripts/setup/setup-antigravity.sh
# .agents/ 目錄會被 Antigravity 自動載入

</details>
```

#### 3.3.4 Platform Support Table — Add Antigravity Column

| Feature | Claude Code | OpenAI Codex | Gemini CLI | Antigravity |
|---------|-------------|--------------|------------|-------------|
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `.agents/rules/` |
| Skills | `.claude/skills/` | `.codex/skills/` | extensions | `.agents/skills/` |
| Skills format | SKILL.md | SKILL.md | JSON | SKILL.md |
| Agent defs | `.claude/agents/` | via AGENTS.md | `.gemini/agents/` | `.agents/skills/{h,z}/` |
| Pipelines | `*cmd` | `*cmd` | `*cmd` | `/workflow-name` |
| Bash | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) | Yes |

#### 3.3.5 Tool Tables — Add Windows Column

Each tool table gains a `Windows (winget)` column:

| Tool | Tier | macOS (brew) | Linux (apt/snap) | Windows (winget) | Purpose |
|------|------|-------------|-------------------|------------------|---------|
| git | Required | `brew install git` | `apt-get install git` | `winget install Git.Git` | Version control |
| ... | ... | ... | ... | ... | ... |

#### 3.3.6 Project Structure — Add `.agents/`

```
├── .agents/                    # Google Antigravity 平台
│   ├── rules/devops.md
│   ├── skills/
│   │   ├── horus/SKILL.md
│   │   ├── zeus/SKILL.md
│   │   └── (8 skill symlinks)
│   └── workflows/              # symlinks → prompts/
```

---

### 3.4 Test Updates (`tests/test-structure.sh`)

#### Current Coverage

| Section | Platform | Tests |
|---------|----------|-------|
| 4 | Claude Code | settings, agents, plugins |
| 5 | OpenAI Codex | config.toml, skills dir |
| 6 | Gemini CLI | settings, agents, extension JSON |
| 6b | Antigravity | agent-as-skill wrappers, rules |

#### New/Enhanced Tests

**Section 6b Enhancement — Antigravity deeper checks:**
- Verify `.agents/rules/devops.md` references `docs/PROJECT.md`
- Verify agent-as-skill wrappers have `version:` field
- Already tested: YAML frontmatter, name, description

**New Section 13 — Setup Script Validation:**
- All 4 setup scripts exist and are executable
- Each setup script has correct shebang (`#!/usr/bin/env bash`)
- `setup-antigravity.sh` references all 17 expected workflow names

**New Section 14 — Cross-Platform Parity:**
- README mentions all 4 platforms in description
- README has Quick Start section for each platform
- Platform support table has 4 platform columns
- All platform entry files exist (CLAUDE.md, AGENTS.md, GEMINI.md, .agents/rules/devops.md)
- `docs/PROJECT.md` has Antigravity section

**New Section 15 — Tool Installation Script:**
- `install-tools.sh` exists and is executable
- Script contains Windows detection (`MINGW\|MSYS\|CYGWIN`)
- Script contains all 3 package manager families (brew, apt, winget)
- Tool registry includes all expected tools

---

## 4. Files to Modify

| File | Change |
|------|--------|
| `README.md` | Badge, description, quick start, platform table, tool tables, project structure (×3 langs) |
| `scripts/install-tools.sh` | Add Windows (winget/choco/scoop) detection + install commands |
| `tests/test-structure.sh` | Add sections 13-15 for setup validation, cross-platform parity, tool script |
| `docs/PROJECT.md` | Update tool installation description to include Windows |

## 5. Files NOT Modified

| File | Reason |
|------|--------|
| Setup scripts | Already complete for all 4 platforms |
| Agent definitions | Already platform-agnostic |
| Skill definitions | Already platform-agnostic |
| `postinstall.js` | Already handles all 4 platforms |
| `package.json` | Already has `setup:antigravity` script |

---

## 6. Verification

```bash
# Run structure tests
pnpm test

# Run version consistency
pnpm version:consistency

# Verify install-tools.sh syntax
bash -n scripts/install-tools.sh

# Check README has 4 platforms
grep -c "Antigravity" README.md  # should be > 0 in all 3 sections
```

---

## 7. Out of Scope

- Global installation (all installs are project-local)
- PowerShell-native setup scripts (bash via Git Bash/WSL is sufficient)
- GUI installer
- Auto-detection of which platforms are installed
