#!/usr/bin/env bash
# =============================================================================
# DevOps AI Skill Pack — Unified Setup
# =============================================================================
# Usage:
#   bash devops-ai-skill/scripts/setup.sh              # Interactive (select platforms)
#   bash devops-ai-skill/scripts/setup.sh --all         # One-click: all platforms
#   bash devops-ai-skill/scripts/setup.sh --claude      # Single platform
#   bash devops-ai-skill/scripts/setup.sh --codex --gemini  # Multiple platforms
#   bash devops-ai-skill/scripts/setup.sh --uninstall   # Remove all symlinks
#
# This script installs skills, agents, and pipelines into the TARGET repository
# (the parent directory of devops-ai-skill/).
# =============================================================================

set -euo pipefail

# --- Path resolution ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_PACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_PACK_NAME="$(basename "$SKILL_PACK_DIR")"
TARGET_DIR="$(cd "$SKILL_PACK_DIR/.." && pwd)"

# Colors (safe for non-interactive)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; NC=''
fi

# Counters
PASS=0; SKIP=0; WARN=0; FAIL=0

log_ok()   { echo -e "  ${GREEN}[ok]${NC} $1"; ((PASS++)) || true; }
log_skip() { echo -e "  ${YELLOW}[skip]${NC} $1"; ((SKIP++)) || true; }
log_link() { echo -e "  ${GREEN}[link]${NC} $1"; ((PASS++)) || true; }
log_warn() { echo -e "  ${YELLOW}[warn]${NC} $1"; ((WARN++)) || true; }
log_fail() { echo -e "  ${RED}[fail]${NC} $1"; ((FAIL++)) || true; }

# --- Helpers ---
# Create a relative symlink from $1 (target location) pointing to $2 (source)
create_symlink() {
  local target="$1"   # where the symlink is created
  local source="$2"   # what it points to (relative path)
  local label="${3:-$(basename "$target")}"

  if [ -L "$target" ]; then
    log_skip "$label (symlink exists)"
  elif [ -e "$target" ]; then
    log_skip "$label (file/dir exists)"
  else
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    log_link "$label → $source"
  fi
}

# Append a section to an entry file (CLAUDE.md, AGENTS.md, etc.)
append_entry_section() {
  local file="$1"
  local marker="$2"
  local content="$3"

  if [ -f "$file" ] && grep -q "$marker" "$file"; then
    log_skip "$(basename "$file") already has devops-ai-skill section"
    return
  fi

  echo "" >> "$file"
  echo "$content" >> "$file"
  log_ok "Appended devops-ai-skill section to $(basename "$file")"
}

# Remove symlinks created by this script
remove_symlink() {
  local target="$1"
  local label="${2:-$(basename "$target")}"
  if [ -L "$target" ]; then
    rm "$target"
    echo -e "  ${RED}[rm]${NC} $label"
  fi
}

# --- Platform installers ---
setup_claude() {
  echo ""
  echo -e "${BOLD}═══ Claude Code ═══${NC}"

  local rel="$SKILL_PACK_NAME"

  # Skills: TARGET/.claude/skills/* → devops-ai-skill/skills/*
  mkdir -p "$TARGET_DIR/.claude/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    local name
    name=$(basename "$skill_dir")
    create_symlink \
      "$TARGET_DIR/.claude/skills/$name" \
      "../../$rel/skills/$name" \
      "skill: $name"
  done

  # Agents: TARGET/.claude/agents/{horus,zeus}.md → devops-ai-skill/.claude/agents/*.md
  mkdir -p "$TARGET_DIR/.claude/agents"
  for agent in horus zeus; do
    create_symlink \
      "$TARGET_DIR/.claude/agents/$agent.md" \
      "../../$rel/.claude/agents/$agent.md" \
      "agent: $agent"
  done

  # Append to CLAUDE.md
  local marker="<!-- devops-ai-skill -->"
  local section
  section=$(cat <<'ENTRY'
<!-- devops-ai-skill -->
## DevOps AI Skill Pack

Read `devops-ai-skill/docs/PROJECT.md` for shared project context.

- Agent definitions: `.claude/agents/horus.md` (IaC) and `.claude/agents/zeus.md` (GitOps)
- Skills directory: `.claude/skills/` (8 skills)
- Pipelines: `devops-ai-skill/prompts/` (14 pipelines)

### Commands

| Command | Pipeline |
|---------|----------|
| *full | Full check + report |
| *upgrade | Upgrade Helm Chart versions |
| *security | Security audit |
| *validate | Validation (fmt + analysis) |
| *new-module | Scaffold new Helm module |
| *cicd | Improve CI/CD pipeline |
| *health | Platform health check |
ENTRY
)
  if [ -f "$TARGET_DIR/CLAUDE.md" ]; then
    append_entry_section "$TARGET_DIR/CLAUDE.md" "$marker" "$section"
  else
    echo "$section" > "$TARGET_DIR/CLAUDE.md"
    log_ok "Created CLAUDE.md"
  fi

  local count
  count=$(find "$TARGET_DIR/.claude/skills" -maxdepth 1 -mindepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  Skills: ${GREEN}$count${NC} | Agents: ${GREEN}2${NC}"
}

setup_codex() {
  echo ""
  echo -e "${BOLD}═══ OpenAI Codex CLI ═══${NC}"

  local rel="$SKILL_PACK_NAME"

  # Skills: TARGET/.codex/skills/* → devops-ai-skill/skills/*
  mkdir -p "$TARGET_DIR/.codex/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    local name
    name=$(basename "$skill_dir")
    create_symlink \
      "$TARGET_DIR/.codex/skills/$name" \
      "../../$rel/skills/$name" \
      "skill: $name"
  done

  # Append to AGENTS.md
  local marker="<!-- devops-ai-skill -->"
  local section
  section=$(cat <<'ENTRY'
<!-- devops-ai-skill -->
## DevOps AI Skill Pack

Read `devops-ai-skill/docs/PROJECT.md` for shared project context.
Skills are available at `.codex/skills/`. Pipelines at `devops-ai-skill/prompts/`.

### Agents
- **Horus** — IaC Operations Engineer (Terraform + Helm + GKE): `*full`, `*upgrade`, `*security`, `*validate`, `*new-module`, `*cicd`, `*health`
- **Zeus** — GitOps Engineer (Kustomize + ArgoCD): `*full`, `*pre-merge`, `*health-check`, `*review`, `*onboard`, `*diagram`, `*status`
ENTRY
)
  if [ -f "$TARGET_DIR/AGENTS.md" ]; then
    append_entry_section "$TARGET_DIR/AGENTS.md" "$marker" "$section"
  else
    log_warn "AGENTS.md not found — creating with devops-ai-skill section"
    echo "$section" > "$TARGET_DIR/AGENTS.md"
    log_ok "Created AGENTS.md"
  fi

  local count
  count=$(find "$TARGET_DIR/.codex/skills" -maxdepth 1 -mindepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  Skills: ${GREEN}$count${NC}"
}

setup_gemini() {
  echo ""
  echo -e "${BOLD}═══ Google Gemini CLI ═══${NC}"

  local rel="$SKILL_PACK_NAME"

  # Agents: TARGET/.gemini/agents/{horus,zeus}.md
  mkdir -p "$TARGET_DIR/.gemini/agents"
  for agent in horus zeus; do
    create_symlink \
      "$TARGET_DIR/.gemini/agents/$agent.md" \
      "../../$rel/.gemini/agents/$agent.md" \
      "agent: $agent"
  done

  # Extension: TARGET/.gemini/extensions/devops/
  mkdir -p "$TARGET_DIR/.gemini/extensions"
  create_symlink \
    "$TARGET_DIR/.gemini/extensions/devops" \
    "../../$rel/.gemini/extensions/devops" \
    "extension: devops"

  # Create or append GEMINI.md
  local marker="<!-- devops-ai-skill -->"
  local section
  section=$(cat <<'ENTRY'
<!-- devops-ai-skill -->
## DevOps AI Skill Pack

Read `devops-ai-skill/docs/PROJECT.md` for shared project context.

- Agent definitions: `.gemini/agents/horus.md` (IaC) and `.gemini/agents/zeus.md` (GitOps)
- Extension: `.gemini/extensions/devops/gemini-extension.json`
- Pipelines: `devops-ai-skill/prompts/` (14 pipelines)

Trigger with `*full`, `*upgrade`, `*security`, `*validate`, `*new-module`, `*cicd`, `*health` (Horus) or `*full`, `*pre-merge`, `*health-check`, `*review`, `*onboard`, `*diagram`, `*status` (Zeus).
ENTRY
)
  if [ -f "$TARGET_DIR/GEMINI.md" ]; then
    append_entry_section "$TARGET_DIR/GEMINI.md" "$marker" "$section"
  else
    echo "$section" > "$TARGET_DIR/GEMINI.md"
    log_ok "Created GEMINI.md"
  fi
}

setup_antigravity() {
  echo ""
  echo -e "${BOLD}═══ Google Antigravity ═══${NC}"

  local rel="$SKILL_PACK_NAME"

  # Rules
  mkdir -p "$TARGET_DIR/.agents/rules"
  create_symlink \
    "$TARGET_DIR/.agents/rules/devops.md" \
    "../../$rel/.agents/rules/devops.md" \
    "rules: devops.md"

  # Agent wrappers
  for agent in horus zeus; do
    mkdir -p "$TARGET_DIR/.agents/skills/$agent"
    create_symlink \
      "$TARGET_DIR/.agents/skills/$agent/SKILL.md" \
      "../../../$rel/.agents/skills/$agent/SKILL.md" \
      "agent-skill: $agent"
  done

  # Skills
  mkdir -p "$TARGET_DIR/.agents/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    local name
    name=$(basename "$skill_dir")
    create_symlink \
      "$TARGET_DIR/.agents/skills/$name" \
      "../../$rel/skills/$name" \
      "skill: $name"
  done

  # Workflows
  mkdir -p "$TARGET_DIR/.agents/workflows"

  local -a workflows=(
    "horus-full:horus/full-pipeline.md"
    "horus-upgrade:horus/upgrade.md"
    "horus-security:horus/security.md"
    "horus-validate:horus/validate.md"
    "horus-new-module:horus/new-module.md"
    "horus-cicd:horus/cicd.md"
    "horus-health:horus/health.md"
    "zeus-full:zeus/full-pipeline.md"
    "zeus-pre-merge:zeus/pre-merge.md"
    "zeus-health-check:zeus/health-check.md"
    "zeus-review:zeus/review.md"
    "zeus-onboard:zeus/onboard.md"
    "zeus-diagram:zeus/diagram.md"
    "zeus-status:zeus/status.md"
    "shared-repo-detect:shared/repo-detect.md"
    "shared-report-format:shared/report-format.md"
    "shared-tool-check:shared/tool-check.md"
  )

  for entry in "${workflows[@]}"; do
    local wf_name="${entry%%:*}"
    local wf_path="${entry#*:}"
    create_symlink \
      "$TARGET_DIR/.agents/workflows/${wf_name}.md" \
      "../../$rel/prompts/$wf_path" \
      "workflow: $wf_name"
  done
}

# --- Uninstall ---
do_uninstall() {
  echo ""
  echo -e "${BOLD}═══ Uninstall devops-ai-skill ═══${NC}"

  # Claude skills & agents
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    remove_symlink "$TARGET_DIR/.claude/skills/$(basename "$skill_dir")"
  done
  for agent in horus zeus; do
    remove_symlink "$TARGET_DIR/.claude/agents/$agent.md"
  done

  # Codex skills
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    remove_symlink "$TARGET_DIR/.codex/skills/$(basename "$skill_dir")"
  done

  # Gemini agents & extension
  for agent in horus zeus; do
    remove_symlink "$TARGET_DIR/.gemini/agents/$agent.md"
  done
  remove_symlink "$TARGET_DIR/.gemini/extensions/devops"

  # Antigravity
  remove_symlink "$TARGET_DIR/.agents/rules/devops.md"
  for agent in horus zeus; do
    remove_symlink "$TARGET_DIR/.agents/skills/$agent/SKILL.md"
  done
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    remove_symlink "$TARGET_DIR/.agents/skills/$(basename "$skill_dir")"
  done
  if [ -d "$TARGET_DIR/.agents/workflows" ]; then
    find "$TARGET_DIR/.agents/workflows" -type l -name "*.md" -delete 2>/dev/null || true
    echo -e "  ${RED}[rm]${NC} all workflow symlinks"
  fi

  echo ""
  echo -e "${YELLOW}Note:${NC} Entry file sections (CLAUDE.md, AGENTS.md, GEMINI.md) were NOT removed."
  echo "Search for '<!-- devops-ai-skill -->' to remove manually."
  echo ""
  echo -e "${GREEN}Uninstall complete.${NC}"
}

# --- Interactive selection ---
interactive_select() {
  echo ""
  echo -e "${BOLD}Select platforms to install:${NC}"
  echo ""
  echo "  1) Claude Code"
  echo "  2) OpenAI Codex CLI"
  echo "  3) Google Gemini CLI"
  echo "  4) Google Antigravity"
  echo "  a) All platforms"
  echo "  q) Quit"
  echo ""
  read -rp "Enter choices (e.g. 1 3 or a): " choices

  DO_CLAUDE=false; DO_CODEX=false; DO_GEMINI=false; DO_ANTIGRAVITY=false

  for choice in $choices; do
    case "$choice" in
      1) DO_CLAUDE=true ;;
      2) DO_CODEX=true ;;
      3) DO_GEMINI=true ;;
      4) DO_ANTIGRAVITY=true ;;
      a|A) DO_CLAUDE=true; DO_CODEX=true; DO_GEMINI=true; DO_ANTIGRAVITY=true ;;
      q|Q) echo "Cancelled."; exit 0 ;;
      *) echo -e "${YELLOW}Unknown option: $choice${NC}" ;;
    esac
  done

  if ! $DO_CLAUDE && ! $DO_CODEX && ! $DO_GEMINI && ! $DO_ANTIGRAVITY; then
    echo "No platform selected. Exiting."
    exit 0
  fi
}

# --- Main ---
main() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   DevOps AI Skill Pack — Setup          ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Skill pack: ${CYAN}$SKILL_PACK_DIR${NC}"
  echo -e "  Target:     ${CYAN}$TARGET_DIR${NC}"

  # Validate skill pack
  if [ ! -d "$SKILL_PACK_DIR/skills" ] || [ ! -d "$SKILL_PACK_DIR/prompts" ]; then
    echo -e "${RED}Error: devops-ai-skill directory is incomplete.${NC}"
    exit 1
  fi

  # Validate target directory (must not be the same as skill pack)
  if [ "$TARGET_DIR" = "$SKILL_PACK_DIR" ]; then
    echo -e "${RED}Error: Cannot install into self. Run from a parent directory.${NC}"
    exit 1
  fi

  # Warn if target doesn't look like a project root
  if [ ! -d "$TARGET_DIR/.git" ] && [ ! -f "$TARGET_DIR/CLAUDE.md" ] && [ ! -f "$TARGET_DIR/AGENTS.md" ]; then
    echo -e "${YELLOW}Warning: $TARGET_DIR doesn't appear to be a project root (no .git, CLAUDE.md, or AGENTS.md).${NC}"
    read -rp "Continue anyway? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || exit 0
  fi

  # Parse flags
  DO_CLAUDE=false; DO_CODEX=false; DO_GEMINI=false; DO_ANTIGRAVITY=false
  UNINSTALL=false
  PARSED=false

  for arg in "$@"; do
    case "$arg" in
      --all|-a)          DO_CLAUDE=true; DO_CODEX=true; DO_GEMINI=true; DO_ANTIGRAVITY=true; PARSED=true ;;
      --claude)          DO_CLAUDE=true; PARSED=true ;;
      --codex)           DO_CODEX=true; PARSED=true ;;
      --gemini)          DO_GEMINI=true; PARSED=true ;;
      --antigravity)     DO_ANTIGRAVITY=true; PARSED=true ;;
      --uninstall|-u)    UNINSTALL=true; PARSED=true ;;
      --help|-h)
        echo ""
        echo "Usage: bash devops-ai-skill/scripts/setup.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --all, -a         Install for all platforms"
        echo "  --claude          Install for Claude Code"
        echo "  --codex           Install for OpenAI Codex CLI"
        echo "  --gemini          Install for Google Gemini CLI"
        echo "  --antigravity     Install for Google Antigravity"
        echo "  --uninstall, -u   Remove all symlinks"
        echo "  --help, -h        Show this help"
        echo ""
        echo "No flags = interactive mode (select platforms)"
        exit 0
        ;;
      *) echo -e "${YELLOW}Unknown option: $arg${NC}"; exit 1 ;;
    esac
  done

  if $UNINSTALL; then
    do_uninstall
    exit 0
  fi

  # Interactive mode if no flags
  if ! $PARSED; then
    interactive_select
  fi

  # Run selected installers
  if $DO_CLAUDE;      then setup_claude;      fi
  if $DO_CODEX;       then setup_codex;       fi
  if $DO_GEMINI;      then setup_gemini;      fi
  if $DO_ANTIGRAVITY; then setup_antigravity; fi

  # Summary
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}PASS:${NC} $PASS  ${YELLOW}SKIP:${NC} $SKIP  ${YELLOW}WARN:${NC} $WARN  ${RED}FAIL:${NC} $FAIL"
  echo -e "${BOLD}═══════════════════════════════════════════${NC}"

  if [ "$FAIL" -gt 0 ]; then
    echo -e "  ${RED}Some items failed. Check output above.${NC}"
    exit 1
  fi

  local target_name
  target_name=$(basename "$TARGET_DIR")

  echo ""
  echo -e "${GREEN}Setup complete!${NC} The devops-ai-skill is now active in ${CYAN}${target_name}/${NC}"
  echo ""
  echo "Next steps:"
  if $DO_CLAUDE;      then echo "  Claude Code:   open ${target_name}/ in Claude Code — agents auto-load"; fi
  if $DO_CODEX;       then echo "  Codex CLI:     run codex from ${target_name}/ — AGENTS.md auto-loads"; fi
  if $DO_GEMINI;      then echo "  Gemini CLI:    run gemini from ${target_name}/ — GEMINI.md auto-loads"; fi
  if $DO_ANTIGRAVITY; then echo "  Antigravity:   open ${target_name}/ — .agents/ auto-loads"; fi
  echo ""
  echo "Try: *full, *validate, *security, *upgrade, *health"
}

main "$@"
