#!/usr/bin/env bash
# =============================================================================
# DevOps AI Skill Pack — Global Install
# =============================================================================
# Installs skills and agents into user-level config directories (~/.claude/,
# ~/.codex/, ~/.gemini/, ~/.antigravity/) so they are available across ALL
# projects without per-repo symlinks.
#
# Usage:
#   bash scripts/install-global.sh              # Auto-detect installed CLIs
#   bash scripts/install-global.sh --all        # Force all platforms
#   bash scripts/install-global.sh --claude     # Single platform
#   bash scripts/install-global.sh --claude --gemini  # Multiple platforms
#   bash scripts/install-global.sh --uninstall  # Remove global installations
#   bash scripts/install-global.sh --status     # Show what's installed where
#
# Graceful: skips any platform whose CLI is not installed (unless forced).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_PACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

PASS=0; SKIP=0; WARN=0

log_ok()   { echo -e "  ${GREEN}[ok]${NC}   $1"; ((PASS++)) || true; }
log_skip() { echo -e "  ${YELLOW}[skip]${NC} $1"; ((SKIP++)) || true; }
log_warn() { echo -e "  ${YELLOW}[warn]${NC} $1"; ((WARN++)) || true; }
log_new()  { echo -e "  ${GREEN}[new]${NC}  $1"; ((PASS++)) || true; }
log_upd()  { echo -e "  ${GREEN}[upd]${NC}  $1"; ((PASS++)) || true; }

# --- Detection ---
cli_exists() {
  command -v "$1" &>/dev/null
}

dir_exists() {
  [[ -d "$1" ]]
}

detect_platform() {
  local name="$1"
  local cli_cmd="$2"
  local config_dir="$3"

  if cli_exists "$cli_cmd"; then
    local ver
    ver=$("$cli_cmd" --version 2>/dev/null | head -1 || echo "installed")
    echo -e "  ${GREEN}[ok]${NC}   $name  ${DIM}($ver)${NC}"
    return 0
  elif dir_exists "$config_dir"; then
    echo -e "  ${YELLOW}[dir]${NC}  $name  ${DIM}(config dir exists, CLI not in PATH)${NC}"
    return 0
  else
    echo -e "  ${DIM}[--]${NC}   $name  ${DIM}(not installed — skipping)${NC}"
    return 1
  fi
}

# --- Copy helpers ---
copy_dir() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -d "$src" ]]; then
    log_warn "$label source not found: $src"
    return
  fi
  if [[ -d "$dst" ]]; then
    # Update: remove old, copy new
    rm -rf "$dst"
    cp -r "$src" "$dst"
    log_upd "$label"
  else
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
    log_new "$label"
  fi
}

copy_file() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    log_warn "$label source not found: $src"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && diff -q "$src" "$dst" &>/dev/null; then
    log_skip "$label (unchanged)"
  elif [[ -f "$dst" ]]; then
    cp "$src" "$dst"
    log_upd "$label"
  else
    cp "$src" "$dst"
    log_new "$label"
  fi
}

# --- Platform installers ---

install_claude() {
  local base="$HOME/.claude"
  echo ""
  echo -e "${BOLD}═══ Claude Code (~/.claude/) ═══${NC}"

  # Agents
  mkdir -p "$base/agents"
  for agent_file in "$SKILL_PACK_DIR"/.claude/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local name
    name=$(basename "$agent_file")
    copy_file "$agent_file" "$base/agents/$name" "agent: $name"
  done

  # Skills
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
  done
}

install_codex() {
  local base="$HOME/.codex"
  echo ""
  echo -e "${BOLD}═══ OpenAI Codex CLI (~/.codex/) ═══${NC}"

  # Skills
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
  done

  # Append agent info to instructions.md if not present
  local instructions="$base/instructions.md"
  local marker="<!-- devops-ai-skill -->"
  if [[ -f "$instructions" ]] && grep -q "$marker" "$instructions"; then
    log_skip "instructions.md already has devops-ai-skill section"
  else
    cat >> "$instructions" <<'ENTRY'

<!-- devops-ai-skill -->
## DevOps AI Skill Pack (Global)

Skills at `~/.codex/skills/`. Agents: Horus (IaC) and Zeus (GitOps).
Trigger: `*full`, `*upgrade`, `*security`, `*validate`, `*new-module`, `*cicd`, `*health`
ENTRY
    log_ok "Appended agent info to instructions.md"
  fi
}

install_gemini() {
  local base="$HOME/.gemini"
  echo ""
  echo -e "${BOLD}═══ Google Gemini CLI (~/.gemini/) ═══${NC}"

  # Skills — copy to ~/.gemini/skills/ (User Skills tier)
  _gemini_manual_install "$base"

  # Agent definitions (Gemini agents are in .gemini/agents/)
  mkdir -p "$base/agents"
  for agent_file in "$SKILL_PACK_DIR"/.gemini/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local name
    name=$(basename "$agent_file")
    copy_file "$agent_file" "$base/agents/$name" "agent: $name"
  done

  # Extension manifest (.gemini/extensions/devops/)
  local ext_src="$SKILL_PACK_DIR/.gemini/extensions/devops"
  if [[ -d "$ext_src" ]]; then
    copy_dir "$ext_src" "$base/extensions/devops" "extension: devops"
  fi
}

_gemini_manual_install() {
  local base="$1"
  # Manual: copy skills to ~/.gemini/skills/ (User Skills tier)
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
  done
}

install_antigravity() {
  echo ""
  echo -e "${BOLD}═══ Antigravity (~/.agents/) ═══${NC}"

  # Antigravity uses ~/.agents/skills/ as User Skills tier
  # (same path convention as Gemini's ~/.agents/skills/ alias).
  # Skills with SKILL.md are auto-discovered.
  local base="$HOME/.agents"

  # Rules
  mkdir -p "$base/rules"
  if [[ -f "$SKILL_PACK_DIR/.agents/rules/devops.md" ]]; then
    copy_file "$SKILL_PACK_DIR/.agents/rules/devops.md" "$base/rules/devops.md" "rules: devops.md"
  fi

  # Agent skill wrappers (horus/zeus SKILL.md)
  for agent_dir in "$SKILL_PACK_DIR"/.agents/skills/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name
    name=$(basename "$agent_dir")
    copy_dir "$agent_dir" "$base/skills/$name" "agent-skill: $name"
  done

  # Skills
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
  done
}

# --- Uninstall ---
_rm_if_exists() {
  local path="$1" label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    rm -rf "$path"
    echo -e "  ${RED}[rm]${NC} $label"
    return 0
  fi
  return 1
}

do_uninstall() {
  echo ""
  echo -e "${BOLD}═══ Uninstall (Global) ═══${NC}"

  local removed=0
  local skills=("cicd-enhancer" "helm-scaffold" "helm-version-upgrade" "kustomize-resource-validation" "repo-detect" "terraform-security" "terraform-validate" "yaml-fix-suggestions")

  # Claude: ~/.claude/agents/ + ~/.claude/skills/
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.claude/agents/$agent.md" "~/.claude/agents/$agent.md" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.claude/skills/$skill" "~/.claude/skills/$skill" && ((removed++)) || true
  done

  # Codex: ~/.codex/skills/
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.codex/skills/$skill" "~/.codex/skills/$skill" && ((removed++)) || true
  done

  # Gemini: ~/.gemini/agents/ + ~/.gemini/skills/ + ~/.gemini/extensions/devops/
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.gemini/agents/$agent.md" "~/.gemini/agents/$agent.md" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.gemini/skills/$skill" "~/.gemini/skills/$skill" && ((removed++)) || true
  done
  _rm_if_exists "$HOME/.gemini/extensions/devops" "~/.gemini/extensions/devops" && ((removed++)) || true

  # Antigravity / shared ~/.agents/: rules + skills
  _rm_if_exists "$HOME/.agents/rules/devops.md" "~/.agents/rules/devops.md" && ((removed++)) || true
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.agents/skills/$agent" "~/.agents/skills/$agent" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.agents/skills/$skill" "~/.agents/skills/$skill" && ((removed++)) || true
  done

  echo ""
  echo -e "Removed ${RED}$removed${NC} items."
  echo -e "${YELLOW}Note:${NC} Entry sections in ~/.codex/instructions.md were NOT removed."
  echo "Search for '<!-- devops-ai-skill -->' to remove manually."
}

# --- Status ---
do_status() {
  echo ""
  echo -e "${BOLD}═══ Global Install Status ═══${NC}"

  local skills=("cicd-enhancer" "helm-scaffold" "helm-version-upgrade" "kustomize-resource-validation" "repo-detect" "terraform-security" "terraform-validate" "yaml-fix-suggestions")

  # Claude: ~/.claude/
  _status_section "Claude Code" "$HOME/.claude" "claude"

  # Codex: ~/.codex/
  _status_section "Codex CLI" "$HOME/.codex" "codex"

  # Gemini: ~/.gemini/
  _status_section "Gemini CLI" "$HOME/.gemini" "gemini"

  # Antigravity: ~/.agents/ (shared alias)
  _status_section "Antigravity" "$HOME/.agents" "agents"
}

_status_section() {
  local label="$1" base="$2" id="$3"
  local skills=("cicd-enhancer" "helm-scaffold" "helm-version-upgrade" "kustomize-resource-validation" "repo-detect" "terraform-security" "terraform-validate" "yaml-fix-suggestions")
  local found=0

  echo ""
  echo -e "${BOLD}$label${NC} ($base/)"

  if [[ ! -d "$base" ]]; then
    echo -e "  ${DIM}not installed${NC}"
    return
  fi

  # Agents
  for agent in horus zeus; do
    if [[ -f "$base/agents/$agent.md" ]]; then
      echo -e "  ${GREEN}[ok]${NC} agent: $agent"
      ((found++)) || true
    elif [[ -f "$base/skills/$agent/SKILL.md" ]]; then
      echo -e "  ${GREEN}[ok]${NC} agent-skill: $agent"
      ((found++)) || true
    fi
  done

  # Skills
  for skill in "${skills[@]}"; do
    if [[ -d "$base/skills/$skill" ]]; then
      echo -e "  ${GREEN}[ok]${NC} skill: $skill"
      ((found++)) || true
    fi
  done

  # Rules
  if [[ -f "$base/rules/devops.md" ]]; then
    echo -e "  ${GREEN}[ok]${NC} rules: devops.md"
    ((found++)) || true
  fi

  # Extensions (Gemini)
  if [[ -d "$base/extensions/devops" ]]; then
    echo -e "  ${GREEN}[ok]${NC} extension: devops"
    ((found++)) || true
  fi

  if [[ $found -eq 0 ]]; then
    echo -e "  ${DIM}no devops-ai-skill components found${NC}"
  fi
}

# --- Main ---
main() {
  echo ""
  echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║   DevOps AI Skill Pack — Global Install     ║${NC}"
  echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "  Source: ${CYAN}$SKILL_PACK_DIR${NC}"

  # Validate source
  if [[ ! -d "$SKILL_PACK_DIR/skills" ]]; then
    echo -e "${RED}Error: skills/ directory not found in $SKILL_PACK_DIR${NC}"
    exit 1
  fi

  # Parse args
  DO_CLAUDE=false; DO_CODEX=false; DO_GEMINI=false; DO_ANTIGRAVITY=false
  FORCE_ALL=false; UNINSTALL=false; STATUS=false
  PARSED=false

  for arg in "$@"; do
    case "$arg" in
      --all|-a)          FORCE_ALL=true; PARSED=true ;;
      --claude)          DO_CLAUDE=true; PARSED=true ;;
      --codex)           DO_CODEX=true; PARSED=true ;;
      --gemini)          DO_GEMINI=true; PARSED=true ;;
      --antigravity)     DO_ANTIGRAVITY=true; PARSED=true ;;
      --uninstall|-u)    UNINSTALL=true; PARSED=true ;;
      --status|-s)       STATUS=true; PARSED=true ;;
      --help|-h)
        echo ""
        echo "Usage: bash scripts/install-global.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no flags)        Auto-detect installed CLIs and install"
        echo "  --all, -a         Force install for all 4 platforms"
        echo "  --claude          Install for Claude Code only"
        echo "  --codex           Install for Codex CLI only"
        echo "  --gemini          Install for Gemini CLI only"
        echo "  --antigravity     Install for Windsurf/Antigravity only"
        echo "  --status, -s      Show current global install status"
        echo "  --uninstall, -u   Remove all global installations"
        echo "  --help, -h        Show this help"
        exit 0
        ;;
      *) echo -e "${YELLOW}Unknown option: $arg${NC}"; exit 1 ;;
    esac
  done

  if $STATUS; then
    do_status
    exit 0
  fi

  if $UNINSTALL; then
    do_uninstall
    exit 0
  fi

  # Auto-detect mode: detect which CLIs are installed
  if ! $PARSED; then
    echo ""
    echo -e "${BOLD}Detecting installed platforms...${NC}"
    detect_platform "Claude Code"  "claude"  "$HOME/.claude"  && DO_CLAUDE=true  || true
    detect_platform "Codex CLI"    "codex"   "$HOME/.codex"   && DO_CODEX=true   || true
    detect_platform "Gemini CLI"   "gemini"  "$HOME/.gemini"  && DO_GEMINI=true  || true
    detect_platform "Antigravity"  "antigravity" "$HOME/.agents" && DO_ANTIGRAVITY=true || true

    if ! $DO_CLAUDE && ! $DO_CODEX && ! $DO_GEMINI && ! $DO_ANTIGRAVITY; then
      echo ""
      echo -e "${YELLOW}No supported AI coding tools detected.${NC}"
      echo "Install one of: claude, codex, gemini, windsurf"
      echo "Or use --all to force install for all platforms."
      exit 1
    fi
  fi

  # Force all
  if $FORCE_ALL; then
    DO_CLAUDE=true; DO_CODEX=true; DO_GEMINI=true; DO_ANTIGRAVITY=true
  fi

  # Run installers
  if $DO_CLAUDE;      then install_claude;      fi
  if $DO_CODEX;       then install_codex;       fi
  if $DO_GEMINI;      then install_gemini;      fi
  if $DO_ANTIGRAVITY; then install_antigravity; fi

  # Summary
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}OK:${NC} $PASS  ${YELLOW}SKIP:${NC} $SKIP  ${YELLOW}WARN:${NC} $WARN"
  echo -e "${BOLD}═══════════════════════════════════════════════${NC}"
  echo ""
  echo -e "${GREEN}Global install complete!${NC}"
  echo ""
  echo "To update later:  bash $SKILL_PACK_DIR/scripts/install-global.sh"
  echo "To check status:  bash $SKILL_PACK_DIR/scripts/install-global.sh --status"
  echo "To uninstall:     bash $SKILL_PACK_DIR/scripts/install-global.sh --uninstall"
}

main "$@"
