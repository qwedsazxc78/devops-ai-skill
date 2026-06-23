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

  # --- Legacy cleanup ---
  # Earlier versions of this script copied skills/agents/prompts directly
  # under ~/.claude/{skills,agents,prompts}/ in ADDITION to registering the
  # plugin. That caused every item to appear twice in Claude Code (once
  # unscoped, once under the `devops:` namespace). Remove those legacy
  # duplicates so only the plugin-scoped entries remain.
  _claude_purge_legacy_direct_install "$base"

  # Claude Code is plugin-only now: everything lives in the plugin cache
  # and is exposed under the `devops:` namespace via marketplace registration.
  _claude_register_plugin "$base"
}

# Remove unscoped copies from pre-plugin-only installs so they stop
# duplicating the plugin-registered entries.
_claude_purge_legacy_direct_install() {
  local base="$1"
  local legacy_skills=(cicd-enhancer gateway-api-migration helm-scaffold \
    helm-version-upgrade kustomize-resource-validation release-validate \
    repo-detect terraform-security terraform-validate yaml-fix-suggestions)
  local purged=0
  for skill in "${legacy_skills[@]}"; do
    if [[ -d "$base/skills/$skill" ]]; then
      rm -rf "$base/skills/$skill"
      echo -e "  ${YELLOW}[purge]${NC} legacy skill: $skill"
      ((purged++)) || true
    fi
  done
  for agent in horus zeus; do
    if [[ -f "$base/agents/$agent.md" ]]; then
      rm -f "$base/agents/$agent.md"
      echo -e "  ${YELLOW}[purge]${NC} legacy agent: $agent.md"
      ((purged++)) || true
    fi
  done
  for prompt_dir in horus zeus shared; do
    if [[ -d "$base/prompts/$prompt_dir" ]]; then
      rm -rf "$base/prompts/$prompt_dir"
      echo -e "  ${YELLOW}[purge]${NC} legacy prompts: $prompt_dir"
      ((purged++)) || true
    fi
  done
  if [[ $purged -gt 0 ]]; then
    echo -e "  ${DIM}Removed $purged legacy direct-install items — now plugin-only${NC}"
  fi
}

# Register as Claude Code marketplace plugin so /devops:* commands are discoverable
_claude_register_plugin() {
  local base="$1"
  local settings="$base/settings.json"
  local installed="$base/plugins/installed_plugins.json"
  local marketplace_id="devops-ai-skill"
  local plugin_name="devops"
  local plugin_key="${plugin_name}@${marketplace_id}"
  local version
  version=$(cat "$SKILL_PACK_DIR/VERSION" 2>/dev/null || echo "unknown")

  # Determine the cache directory
  local cache_dir="$base/plugins/cache/$marketplace_id/$plugin_name/$version"

  # Copy plugin files to cache
  mkdir -p "$cache_dir"
  # .claude-plugin/
  copy_dir "$SKILL_PACK_DIR/.claude-plugin" "$cache_dir/.claude-plugin" "plugin: .claude-plugin"
  # commands/
  if [[ -d "$SKILL_PACK_DIR/commands" ]]; then
    copy_dir "$SKILL_PACK_DIR/commands" "$cache_dir/commands" "plugin: commands"
  fi
  # agents/ (flat copy for plugin context)
  mkdir -p "$cache_dir/agents"
  for agent_file in "$SKILL_PACK_DIR"/.claude/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local name
    name=$(basename "$agent_file")
    cp "$agent_file" "$cache_dir/agents/$name"
  done
  # skills/
  if [[ -d "$SKILL_PACK_DIR/skills" ]]; then
    copy_dir "$SKILL_PACK_DIR/skills" "$cache_dir/skills" "plugin: skills"
  fi
  # prompts/
  for prompt_dir in horus zeus shared; do
    local src_dir="$SKILL_PACK_DIR/prompts/$prompt_dir"
    [[ -d "$src_dir" ]] || continue
    mkdir -p "$cache_dir/prompts"
    cp -r "$src_dir" "$cache_dir/prompts/$prompt_dir"
  done

  # Update settings.json — add marketplace + enable plugin
  if command -v python3 &>/dev/null && [[ -f "$settings" ]]; then
    python3 - "$settings" "$marketplace_id" "$plugin_key" <<'PYEOF'
import json, sys

settings_path, marketplace_id, plugin_key = sys.argv[1], sys.argv[2], sys.argv[3]

with open(settings_path, "r") as f:
    settings = json.load(f)

# Add extraKnownMarketplaces entry
mkts = settings.setdefault("extraKnownMarketplaces", {})
mkts[marketplace_id] = {
    "source": {
        "source": "github",
        "repo": "qwedsazxc78/devops-ai-skill"
    },
    "autoUpdate": True
}

# Enable the plugin
enabled = settings.setdefault("enabledPlugins", {})
enabled[plugin_key] = True

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
    log_ok "settings.json: marketplace registered + plugin enabled"
  else
    log_warn "settings.json: python3 not found or settings missing — manual setup needed"
    echo -e "    ${DIM}Add to ~/.claude/settings.json enabledPlugins: \"${plugin_key}\": true${NC}"
  fi

  # Update installed_plugins.json
  if command -v python3 &>/dev/null && [[ -f "$installed" ]]; then
    python3 - "$installed" "$plugin_key" "$cache_dir" "$version" <<'PYEOF'
import json, sys, datetime

installed_path = sys.argv[1]
plugin_key = sys.argv[2]
cache_dir = sys.argv[3]
version = sys.argv[4]

with open(installed_path, "r") as f:
    data = json.load(f)

now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

plugins = data.setdefault("plugins", {})
plugins[plugin_key] = [{
    "scope": "user",
    "installPath": cache_dir,
    "version": version,
    "installedAt": now,
    "lastUpdated": now
}]

with open(installed_path, "w") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")
PYEOF
    log_ok "installed_plugins.json: $plugin_key registered"
  fi
}

install_codex() {
  local base="$HOME/.codex"
  echo ""
  echo -e "${BOLD}═══ OpenAI Codex CLI (~/.codex/) ═══${NC}"

  # 1. Agents — copy agent definitions
  mkdir -p "$base/agents"
  for agent_file in "$SKILL_PACK_DIR"/.claude/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local name
    name=$(basename "$agent_file")
    copy_file "$agent_file" "$base/agents/$name" "agent: $name"
  done

  # 2. Skills
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
  done

  # 3. Prompts — copy pipeline definitions
  for prompt_dir in horus zeus shared; do
    local src_dir="$SKILL_PACK_DIR/prompts/$prompt_dir"
    [[ -d "$src_dir" ]] || continue
    copy_dir "$src_dir" "$base/prompts/$prompt_dir" "prompts: $prompt_dir"
  done

  # 4. Append agent info to instructions.md if not present
  local instructions="$base/instructions.md"
  local marker="<!-- devops-ai-skill -->"
  if [[ -f "$instructions" ]] && grep -q "$marker" "$instructions"; then
    log_skip "instructions.md already has devops-ai-skill section"
  else
    cat >> "$instructions" <<'ENTRY'

<!-- devops-ai-skill -->
## DevOps AI Skill Pack (Global)

Agents at `~/.codex/agents/`, skills at `~/.codex/skills/`, pipelines at `~/.codex/prompts/`.

### Agents
- **Horus** (IaC) — Read `~/.codex/agents/horus.md` when working with Terraform + Helm + GKE
- **Zeus** (GitOps) — Read `~/.codex/agents/zeus.md` when working with Kustomize + ArgoCD

### Commands
Horus: `*full`, `*upgrade`, `*security`, `*validate`, `*scaffold`, `*cicd`, `*health`
Zeus: `*full`, `*pre-merge`, `*health`, `*review`, `*scaffold`, `*diagram`, `*status`, `*gateway-migrate`

When a `*command` is triggered, read the corresponding pipeline from `~/.codex/prompts/`.
ENTRY
    log_ok "Appended agent info to instructions.md"
  fi
}

install_gemini() {
  local base="$HOME/.gemini"
  echo ""
  echo -e "${BOLD}═══ Google Gemini CLI (~/.gemini/) ═══${NC}"

  # 1. Skills — copy to ~/.gemini/skills/ (User Skills tier)
  _gemini_manual_install "$base"

  # 2. Agents — copy agent definitions
  mkdir -p "$base/agents"
  for agent_file in "$SKILL_PACK_DIR"/.gemini/agents/*.md; do
    [[ -f "$agent_file" ]] || continue
    local name
    name=$(basename "$agent_file")
    copy_file "$agent_file" "$base/agents/$name" "agent: $name"
  done

  # 3. Commands — copy TOML command files for Gemini command palette
  local cmd_src="$SKILL_PACK_DIR/.gemini/commands/devops"
  if [[ -d "$cmd_src" ]]; then
    copy_dir "$cmd_src" "$base/commands/devops" "commands: devops"
  fi

  # Extension manifest (.gemini/extensions/devops/)
  local ext_src="$SKILL_PACK_DIR/.gemini/extensions/devops"
  if [[ -d "$ext_src" ]]; then
    copy_dir "$ext_src" "$base/extensions/devops" "extension: devops"
  fi
}

_gemini_manual_install() {
  local base="$1"
  # Copy skills to ~/.gemini/skills/ (the path gemini skills list discovers).
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

  local base="$HOME/.agents"

  # --- Legacy cleanup ---
  # Older versions of this script wrote workflow files under different
  # filenames that no longer correspond to any source pipeline. Remove
  # those stale leftovers before re-installing.
  _antigravity_purge_legacy_workflows "$base"

  # 1. Rules
  mkdir -p "$base/rules"
  if [[ -f "$SKILL_PACK_DIR/.agents/rules/devops.md" ]]; then
    copy_file "$SKILL_PACK_DIR/.agents/rules/devops.md" "$base/rules/devops.md" "rules: devops.md"
  fi

  # 2. Agent skill wrappers (horus/zeus SKILL.md)
  for agent_dir in "$SKILL_PACK_DIR"/.agents/skills/*/; do
    [[ -d "$agent_dir" ]] || continue
    local name
    name=$(basename "$agent_dir")
    copy_dir "$agent_dir" "$base/skills/$name" "agent-skill: $name"
  done

  # 3. Skills — Gemini CLI scans BOTH ~/.gemini/skills/ AND ~/.agents/skills/.
  #    If a skill exists in ~/.gemini/skills/, remove it from ~/.agents/skills/
  #    to avoid "Skill conflict" warnings, then skip the copy.
  mkdir -p "$base/skills"
  for skill_dir in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$skill_dir" ]] || continue
    local name
    name=$(basename "$skill_dir")
    if [[ -d "$HOME/.gemini/skills/$name" ]]; then
      # Remove old copy from ~/.agents/skills/ if it exists (cleanup)
      if [[ -d "$base/skills/$name" ]]; then
        rm -rf "$base/skills/$name"
        log_ok "skill: $name (removed from ~/.agents/, using ~/.gemini/)"
      else
        log_skip "skill: $name (in ~/.gemini/skills/)"
      fi
    else
      copy_dir "$skill_dir" "$base/skills/$name" "skill: $name"
    fi
  done

  # 4. Workflows — copy pipeline prompts to ~/.agents/workflows/
  mkdir -p "$base/workflows"
  for prompt_dir in horus zeus shared; do
    local src_dir="$SKILL_PACK_DIR/prompts/$prompt_dir"
    [[ -d "$src_dir" ]] || continue
    for prompt_file in "$src_dir"/*.md; do
      [[ -f "$prompt_file" ]] || continue
      local fname
      fname=$(basename "$prompt_file" .md)
      # Prefix with agent name for horus/zeus, keep shared- prefix for shared
      if [[ "$prompt_dir" == "shared" ]]; then
        local wf_name="shared-${fname}"
      else
        local wf_name="${prompt_dir}-${fname}"
      fi
      copy_file "$prompt_file" "$base/workflows/${wf_name}.md" "workflow: $wf_name"
    done
  done
}

# Remove ~/.agents/workflows/ entries that no longer correspond to any
# source pipeline. Each entry here is the legacy filename that an older
# install script wrote and that current install runs no longer touch —
# left behind, they look like real workflows but point at nothing.
_antigravity_purge_legacy_workflows() {
  local base="$1"
  local stale=(
    horus-new-module
    zeus-health-check
    zeus-onboard
  )
  local purged=0
  for wf in "${stale[@]}"; do
    if [[ -f "$base/workflows/${wf}.md" ]]; then
      rm -f "$base/workflows/${wf}.md"
      echo -e "  ${YELLOW}[purge]${NC} legacy workflow: $wf"
      ((purged++)) || true
    fi
  done
  if [[ $purged -gt 0 ]]; then
    echo -e "  ${DIM}Removed $purged stale workflow(s) from previous installs${NC}"
  fi
}

# --- Dynamic discovery (keeps uninstall/status in sync with the source tree) ---
# Enumerate skill names straight from skills/ so the lists below never go stale
# when skills are added or removed. Echoes one name per line.
_discover_skills() {
  local d
  for d in "$SKILL_PACK_DIR"/skills/*/; do
    [[ -d "$d" ]] || continue
    basename "$d"
  done
}

# Enumerate the workflow filenames install_antigravity writes, derived from the
# same prompts/ sources and the same naming rule (shared-* / <agent>-*).
_discover_workflows() {
  local prompt_dir src_dir f fname
  for prompt_dir in horus zeus shared; do
    src_dir="$SKILL_PACK_DIR/prompts/$prompt_dir"
    [[ -d "$src_dir" ]] || continue
    for f in "$src_dir"/*.md; do
      [[ -f "$f" ]] || continue
      fname=$(basename "$f" .md)
      if [[ "$prompt_dir" == "shared" ]]; then
        echo "shared-${fname}"
      else
        echo "${prompt_dir}-${fname}"
      fi
    done
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

_claude_unregister_plugin() {
  local settings="$HOME/.claude/settings.json"
  local installed="$HOME/.claude/plugins/installed_plugins.json"
  if ! command -v python3 &>/dev/null; then return 1; fi

  # Remove from settings.json
  if [[ -f "$settings" ]]; then
    python3 - "$settings" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "r") as f:
    s = json.load(f)
changed = False
if "extraKnownMarketplaces" in s and "devops-ai-skill" in s["extraKnownMarketplaces"]:
    del s["extraKnownMarketplaces"]["devops-ai-skill"]
    changed = True
if "enabledPlugins" in s and "devops@devops-ai-skill" in s["enabledPlugins"]:
    del s["enabledPlugins"]["devops@devops-ai-skill"]
    changed = True
if changed:
    with open(path, "w") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF
    echo -e "  ${RED}[rm]${NC} settings.json: devops-ai-skill entries"
  fi

  # Remove from installed_plugins.json
  if [[ -f "$installed" ]]; then
    python3 - "$installed" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, "r") as f:
    d = json.load(f)
if "plugins" in d and "devops@devops-ai-skill" in d["plugins"]:
    del d["plugins"]["devops@devops-ai-skill"]
    with open(path, "w") as f:
        json.dump(d, f, indent=4, ensure_ascii=False)
        f.write("\n")
PYEOF
    echo -e "  ${RED}[rm]${NC} installed_plugins.json: devops@devops-ai-skill"
  fi
  return 0
}

do_uninstall() {
  echo ""
  echo -e "${BOLD}═══ Uninstall (Global) ═══${NC}"

  local removed=0
  local skills=()
  while IFS= read -r _s; do skills+=("$_s"); done < <(_discover_skills)

  # Claude: ~/.claude/agents/ + ~/.claude/skills/ + ~/.claude/prompts/ + plugin cache
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.claude/agents/$agent.md" "~/.claude/agents/$agent.md" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.claude/skills/$skill" "~/.claude/skills/$skill" && ((removed++)) || true
  done
  for prompt_dir in horus zeus shared; do
    _rm_if_exists "$HOME/.claude/prompts/$prompt_dir" "~/.claude/prompts/$prompt_dir" && ((removed++)) || true
  done
  # Plugin cache + settings entries
  _rm_if_exists "$HOME/.claude/plugins/cache/devops-ai-skill" "~/.claude/plugins/cache/devops-ai-skill" && ((removed++)) || true
  _claude_unregister_plugin && ((removed++)) || true

  # Codex: ~/.codex/agents/ + ~/.codex/skills/ + ~/.codex/prompts/
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.codex/agents/$agent.md" "~/.codex/agents/$agent.md" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.codex/skills/$skill" "~/.codex/skills/$skill" && ((removed++)) || true
  done
  for prompt_dir in horus zeus shared; do
    _rm_if_exists "$HOME/.codex/prompts/$prompt_dir" "~/.codex/prompts/$prompt_dir" && ((removed++)) || true
  done

  # Gemini: ~/.gemini/agents/ + ~/.gemini/skills/ + ~/.gemini/extensions/devops/
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.gemini/agents/$agent.md" "~/.gemini/agents/$agent.md" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.gemini/skills/$skill" "~/.gemini/skills/$skill" && ((removed++)) || true
  done
  _rm_if_exists "$HOME/.gemini/extensions/devops" "~/.gemini/extensions/devops" && ((removed++)) || true
  _rm_if_exists "$HOME/.gemini/commands/devops" "~/.gemini/commands/devops" && ((removed++)) || true

  # Antigravity / shared ~/.agents/: rules + skills + workflows
  _rm_if_exists "$HOME/.agents/rules/devops.md" "~/.agents/rules/devops.md" && ((removed++)) || true
  for agent in horus zeus; do
    _rm_if_exists "$HOME/.agents/skills/$agent" "~/.agents/skills/$agent" && ((removed++)) || true
  done
  for skill in "${skills[@]}"; do
    _rm_if_exists "$HOME/.agents/skills/$skill" "~/.agents/skills/$skill" && ((removed++)) || true
  done
  # Workflows — enumerated from prompts/ with the same naming rule install
  # uses (install writes the source filename verbatim, so `full-pipeline.md` →
  # `horus-full-pipeline.md`). Dynamic so new pipelines are removed too.
  local workflows=()
  while IFS= read -r _w; do workflows+=("$_w"); done < <(_discover_workflows)
  for wf in "${workflows[@]}"; do
    _rm_if_exists "$HOME/.agents/workflows/${wf}.md" "~/.agents/workflows/${wf}.md" && ((removed++)) || true
  done
  # Also clean up known legacy filenames that older installs left behind.
  for wf in horus-new-module zeus-health-check zeus-onboard horus-full zeus-full; do
    _rm_if_exists "$HOME/.agents/workflows/${wf}.md" "~/.agents/workflows/${wf}.md" && ((removed++)) || true
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
  local skills=()
  while IFS= read -r _s; do skills+=("$_s"); done < <(_discover_skills)
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

  # Commands (Gemini)
  if [[ -d "$base/commands/devops" ]]; then
    local cmd_count
    cmd_count=$(find "$base/commands/devops" -name "*.toml" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${GREEN}[ok]${NC} commands: $cmd_count toml files"
    ((found++)) || true
  fi

  # Plugin (Claude — /devops:* commands)
  if [[ -d "$base/plugins/cache/devops-ai-skill" ]]; then
    local cmd_md_count
    cmd_md_count=$(find "$base/plugins/cache/devops-ai-skill" -path "*/commands/*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  ${GREEN}[ok]${NC} plugin: devops ($cmd_md_count commands → /devops:*)"
    ((found++)) || true
  fi

  # Prompts (Codex)
  if [[ -d "$base/prompts" ]]; then
    local prompt_count
    prompt_count=$(find "$base/prompts" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $prompt_count -gt 0 ]]; then
      echo -e "  ${GREEN}[ok]${NC} prompts: $prompt_count pipeline files"
      ((found++)) || true
    fi
  fi

  # Workflows (Antigravity)
  if [[ -d "$base/workflows" ]]; then
    local wf_count
    wf_count=$(find "$base/workflows" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [[ $wf_count -gt 0 ]]; then
      echo -e "  ${GREEN}[ok]${NC} workflows: $wf_count pipeline files"
      ((found++)) || true
    fi
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
