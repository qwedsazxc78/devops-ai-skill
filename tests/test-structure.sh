#!/usr/bin/env bash
set -euo pipefail

# DevOps AI Skill Pack — Structure Tests
# Validates all platform adapters, skills, and cross-references

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
WARN=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

warn() {
    WARN=$((WARN + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${YELLOW}[WARN]${NC} $1"
}

section() {
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  $1"
    echo "═══════════════════════════════════════════"
}

# ============================================
# SECTION 1: Core Files
# ============================================
section "Core Files"

for file in CLAUDE.md AGENTS.md GEMINI.md VERSION CHANGELOG.md README.md .gitignore package.json MIGRATION.md; do
    if [ -f "$ROOT_DIR/$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

# VERSION file should contain valid semver
if [ -f "$ROOT_DIR/VERSION" ]; then
    version=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
    if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        pass "VERSION contains valid semver: $version"
    else
        fail "VERSION does not contain valid semver: '$version'"
    fi
fi

# ============================================
# SECTION 2: Skills Directory
# ============================================
section "Skills Directory"

EXPECTED_SKILLS=(
    "terraform-validate"
    "terraform-security"
    "helm-version-upgrade"
    "helm-scaffold"
    "cicd-enhancer"
    "kustomize-resource-validation"
    "yaml-fix-suggestions"
    "repo-detect"
)

for skill in "${EXPECTED_SKILLS[@]}"; do
    skill_dir="$ROOT_DIR/skills/$skill"
    skill_md="$skill_dir/SKILL.md"

    if [ -d "$skill_dir" ]; then
        pass "skills/$skill/ directory exists"
    else
        fail "skills/$skill/ directory missing"
        continue
    fi

    if [ -f "$skill_md" ]; then
        pass "skills/$skill/SKILL.md exists"
    else
        fail "skills/$skill/SKILL.md missing"
        continue
    fi

    # Check YAML frontmatter
    if head -1 "$skill_md" | grep -q "^---$"; then
        pass "skills/$skill/SKILL.md has YAML frontmatter"
    else
        fail "skills/$skill/SKILL.md missing YAML frontmatter"
    fi

    # Check name: field
    if grep -q "^name:" "$skill_md"; then
        pass "skills/$skill/SKILL.md has name: field"
    else
        fail "skills/$skill/SKILL.md missing name: field"
    fi

    # Check description: field
    if grep -q "^description:" "$skill_md"; then
        pass "skills/$skill/SKILL.md has description: field"
    else
        fail "skills/$skill/SKILL.md missing description: field"
    fi

    # Check no Claude-specific model: field
    if grep -q "^model:" "$skill_md"; then
        fail "skills/$skill/SKILL.md has Claude-specific model: field (should be removed)"
    else
        pass "skills/$skill/SKILL.md has no model: field (platform-agnostic)"
    fi

    # Check version: field exists
    if grep -q "^version:" "$skill_md"; then
        pass "skills/$skill/SKILL.md has version: field"
    else
        fail "skills/$skill/SKILL.md missing version: field"
    fi
done

# ============================================
# SECTION 3: Prompts Directory
# ============================================
section "Prompts Directory"

HORUS_PROMPTS=("full-pipeline.md" "upgrade.md" "security.md" "validate.md" "new-module.md" "cicd.md" "health.md")
ZEUS_PROMPTS=("full-pipeline.md" "pre-merge.md" "health-check.md" "review.md" "onboard.md" "diagram.md" "status.md")
SHARED_PROMPTS=("repo-detect.md" "report-format.md" "tool-check.md")

for prompt in "${HORUS_PROMPTS[@]}"; do
    if [ -f "$ROOT_DIR/prompts/horus/$prompt" ]; then
        pass "prompts/horus/$prompt exists"
    else
        fail "prompts/horus/$prompt missing"
    fi
done

for prompt in "${ZEUS_PROMPTS[@]}"; do
    if [ -f "$ROOT_DIR/prompts/zeus/$prompt" ]; then
        pass "prompts/zeus/$prompt exists"
    else
        fail "prompts/zeus/$prompt missing"
    fi
done

for prompt in "${SHARED_PROMPTS[@]}"; do
    if [ -f "$ROOT_DIR/prompts/shared/$prompt" ]; then
        pass "prompts/shared/$prompt exists"
    else
        fail "prompts/shared/$prompt missing"
    fi
done

# ============================================
# SECTION 4: Claude Code Platform
# ============================================
section "Claude Code Platform"

for file in .claude/settings.json .claude/agents/horus.md .claude/agents/zeus.md; do
    if [ -f "$ROOT_DIR/$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

# Agent files should NOT have model: field
for agent in horus zeus; do
    agent_file="$ROOT_DIR/.claude/agents/$agent.md"
    if [ -f "$agent_file" ]; then
        if grep -q "^model:" "$agent_file"; then
            fail ".claude/agents/$agent.md has model: field (should be removed for cross-platform)"
        else
            pass ".claude/agents/$agent.md has no model: field"
        fi

        if head -1 "$agent_file" | grep -q "^---$"; then
            pass ".claude/agents/$agent.md has YAML frontmatter"
        else
            fail ".claude/agents/$agent.md missing YAML frontmatter"
        fi
    fi
done

# Plugin files
for file in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    if [ -f "$ROOT_DIR/$file" ]; then
        pass "$file exists"
        # Validate JSON
        if python3 -c "import json; json.load(open('$ROOT_DIR/$file'))" 2>/dev/null; then
            pass "$file is valid JSON"
        else
            fail "$file is invalid JSON"
        fi
    else
        fail "$file missing"
    fi
done

# ============================================
# SECTION 5: Codex Platform
# ============================================
section "OpenAI Codex Platform"

if [ -f "$ROOT_DIR/.codex/config.toml" ]; then
    pass ".codex/config.toml exists"
else
    fail ".codex/config.toml missing"
fi

if [ -d "$ROOT_DIR/.codex/skills" ]; then
    pass ".codex/skills/ directory exists"
else
    warn ".codex/skills/ directory missing (run setup-codex.sh to create symlinks)"
fi

# ============================================
# SECTION 6: Gemini Platform
# ============================================
section "Google Gemini Platform"

for file in .gemini/settings.json .gemini/agents/horus.md .gemini/agents/zeus.md .gemini/extensions/devops/gemini-extension.json; do
    if [ -f "$ROOT_DIR/$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

# Validate gemini-extension.json
gemini_ext="$ROOT_DIR/.gemini/extensions/devops/gemini-extension.json"
if [ -f "$gemini_ext" ]; then
    if python3 -c "import json; json.load(open('$gemini_ext'))" 2>/dev/null; then
        pass "gemini-extension.json is valid JSON"
    else
        fail "gemini-extension.json is invalid JSON"
    fi
fi

# Gemini Commands (TOML files for command palette)
gemini_cmds_dir="$ROOT_DIR/.gemini/commands/devops"
if [ -d "$gemini_cmds_dir" ]; then
    pass ".gemini/commands/devops/ directory exists"
else
    fail ".gemini/commands/devops/ directory missing"
fi

# Agent command TOMLs
for agent in horus zeus; do
    toml_file="$gemini_cmds_dir/agents/$agent.toml"
    if [ -f "$toml_file" ]; then
        pass ".gemini/commands/devops/agents/$agent.toml exists"
        if grep -q 'description' "$toml_file" && grep -q 'prompt' "$toml_file"; then
            pass "$agent.toml has description and prompt fields"
        else
            fail "$agent.toml missing description or prompt fields"
        fi
    else
        fail ".gemini/commands/devops/agents/$agent.toml missing"
    fi
done

# Pipeline command TOMLs
gemini_pipelines=("horus-full" "horus-upgrade" "horus-security" "horus-validate" "horus-new-module" "horus-cicd" "horus-health" "zeus-full" "zeus-pre-merge" "zeus-health-check" "zeus-review" "zeus-onboard" "zeus-diagram" "zeus-status" "repo-detect" "tool-check")
for pipeline in "${gemini_pipelines[@]}"; do
    toml_file="$gemini_cmds_dir/pipelines/$pipeline.toml"
    if [ -f "$toml_file" ]; then
        pass "pipeline $pipeline.toml exists"
    else
        fail "pipeline $pipeline.toml missing"
    fi
done

# Count total TOML files
toml_count=$(find "$gemini_cmds_dir" -name "*.toml" 2>/dev/null | wc -l | tr -d ' ')
if [ "$toml_count" -eq 18 ]; then
    pass "Correct TOML command count: $toml_count"
else
    fail "Expected 18 TOML commands, found $toml_count"
fi

# ============================================
# SECTION 6b: Google Antigravity Platform
# ============================================
section "Google Antigravity Platform"

# Agent-as-skill wrappers
for agent in horus zeus; do
    skill_file="$ROOT_DIR/.agents/skills/$agent/SKILL.md"
    if [ -f "$skill_file" ]; then
        pass ".agents/skills/$agent/SKILL.md exists"

        # Check YAML frontmatter
        if head -1 "$skill_file" | grep -q "^---$"; then
            pass ".agents/skills/$agent/SKILL.md has YAML frontmatter"
        else
            fail ".agents/skills/$agent/SKILL.md missing YAML frontmatter"
        fi

        # Check name: field
        if grep -q "^name:" "$skill_file"; then
            pass ".agents/skills/$agent/SKILL.md has name: field"
        else
            fail ".agents/skills/$agent/SKILL.md missing name: field"
        fi

        # Check description: field (mandatory for Antigravity)
        if grep -q "^description:" "$skill_file"; then
            pass ".agents/skills/$agent/SKILL.md has description: field"
        else
            fail ".agents/skills/$agent/SKILL.md missing description: field"
        fi

        # Check version: field
        if grep -q "^version:" "$skill_file"; then
            pass ".agents/skills/$agent/SKILL.md has version: field"
        else
            fail ".agents/skills/$agent/SKILL.md missing version: field"
        fi
    else
        fail ".agents/skills/$agent/SKILL.md missing"
    fi
done

# Rules file
if [ -f "$ROOT_DIR/.agents/rules/devops.md" ]; then
    pass ".agents/rules/devops.md exists"
    # Verify rules file references docs/PROJECT.md
    if grep -q "docs/PROJECT.md" "$ROOT_DIR/.agents/rules/devops.md" 2>/dev/null; then
        pass ".agents/rules/devops.md references docs/PROJECT.md"
    else
        fail ".agents/rules/devops.md does not reference docs/PROJECT.md"
    fi
else
    fail ".agents/rules/devops.md missing"
fi

# ============================================
# SECTION 7: Scripts
# ============================================
section "Scripts"

for script in scripts/install-tools.sh scripts/version-check.sh scripts/postinstall.js scripts/setup/setup-claude.sh scripts/setup/setup-codex.sh scripts/setup/setup-gemini.sh scripts/setup/setup-antigravity.sh; do
    if [ -f "$ROOT_DIR/$script" ]; then
        pass "$script exists"
        if [ -x "$ROOT_DIR/$script" ] || head -1 "$ROOT_DIR/$script" | grep -q "^#!/"; then
            pass "$script has shebang or is executable"
        else
            warn "$script may not be executable"
        fi
    else
        fail "$script missing"
    fi
done

# ============================================
# SECTION 8: Documentation
# ============================================
section "Documentation"

for file in docs/setup.md docs/cross-platform-migration-plan.md MIGRATION.md; do
    if [ -f "$ROOT_DIR/$file" ]; then
        pass "$file exists"
    else
        fail "$file missing"
    fi
done

# ============================================
# SECTION 9: Cross-References
# ============================================
section "Cross-References"

# CLAUDE.md should reference .claude/agents/
if grep -q ".claude/agents/" "$ROOT_DIR/CLAUDE.md" 2>/dev/null; then
    pass "CLAUDE.md references .claude/agents/"
else
    fail "CLAUDE.md does not reference .claude/agents/"
fi

# CLAUDE.md should reference prompts/
if grep -q "prompts/" "$ROOT_DIR/CLAUDE.md" 2>/dev/null; then
    pass "CLAUDE.md references prompts/"
else
    fail "CLAUDE.md does not reference prompts/"
fi

# AGENTS.md should reference skills/
if grep -q "skills/" "$ROOT_DIR/AGENTS.md" 2>/dev/null; then
    pass "AGENTS.md references skills/"
else
    fail "AGENTS.md does not reference skills/"
fi

# AGENTS.md should reference prompts/
if grep -q "prompts/" "$ROOT_DIR/AGENTS.md" 2>/dev/null; then
    pass "AGENTS.md references prompts/"
else
    fail "AGENTS.md does not reference prompts/"
fi

# GEMINI.md should reference .gemini/agents/
if grep -q ".gemini/agents/" "$ROOT_DIR/GEMINI.md" 2>/dev/null; then
    pass "GEMINI.md references .gemini/agents/"
else
    fail "GEMINI.md does not reference .gemini/agents/"
fi

# GEMINI.md should reference prompts/
if grep -q "prompts/" "$ROOT_DIR/GEMINI.md" 2>/dev/null; then
    pass "GEMINI.md references prompts/"
else
    fail "GEMINI.md does not reference prompts/"
fi

# .agents/skills/horus should reference prompts/ and docs/PROJECT.md
if grep -q "prompts/" "$ROOT_DIR/.agents/skills/horus/SKILL.md" 2>/dev/null; then
    pass ".agents/skills/horus/SKILL.md references prompts/"
else
    fail ".agents/skills/horus/SKILL.md does not reference prompts/"
fi
if grep -q "docs/PROJECT.md" "$ROOT_DIR/.agents/skills/horus/SKILL.md" 2>/dev/null; then
    pass ".agents/skills/horus/SKILL.md references docs/PROJECT.md"
else
    fail ".agents/skills/horus/SKILL.md does not reference docs/PROJECT.md"
fi

# .agents/skills/zeus should reference prompts/ and docs/PROJECT.md
if grep -q "prompts/" "$ROOT_DIR/.agents/skills/zeus/SKILL.md" 2>/dev/null; then
    pass ".agents/skills/zeus/SKILL.md references prompts/"
else
    fail ".agents/skills/zeus/SKILL.md does not reference prompts/"
fi
if grep -q "docs/PROJECT.md" "$ROOT_DIR/.agents/skills/zeus/SKILL.md" 2>/dev/null; then
    pass ".agents/skills/zeus/SKILL.md references docs/PROJECT.md"
else
    fail ".agents/skills/zeus/SKILL.md does not reference docs/PROJECT.md"
fi

# ============================================
# SECTION 10: Version Consistency
# ============================================
section "Version Consistency"

if [ -f "$ROOT_DIR/VERSION" ]; then
    expected_version=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')

    # Check plugin.json
    if [ -f "$ROOT_DIR/.claude-plugin/plugin.json" ]; then
        plugin_version=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/plugin.json'))['version'])" 2>/dev/null || echo "")
        if [ "$plugin_version" = "$expected_version" ]; then
            pass "plugin.json version matches VERSION ($expected_version)"
        else
            fail "plugin.json version ($plugin_version) does not match VERSION ($expected_version)"
        fi
    fi

    # Check marketplace.json
    if [ -f "$ROOT_DIR/.claude-plugin/marketplace.json" ]; then
        mp_version=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/.claude-plugin/marketplace.json'))['metadata']['version'])" 2>/dev/null || echo "")
        if [ "$mp_version" = "$expected_version" ]; then
            pass "marketplace.json version matches VERSION ($expected_version)"
        else
            fail "marketplace.json version ($mp_version) does not match VERSION ($expected_version)"
        fi
    fi

    # Check gemini-extension.json
    if [ -f "$gemini_ext" ]; then
        gemini_version=$(python3 -c "import json; print(json.load(open('$gemini_ext'))['version'])" 2>/dev/null || echo "")
        if [ "$gemini_version" = "$expected_version" ]; then
            pass "gemini-extension.json version matches VERSION ($expected_version)"
        else
            fail "gemini-extension.json version ($gemini_version) does not match VERSION ($expected_version)"
        fi
    fi
fi

# ============================================
# SECTION 11: Package & CI
# ============================================
section "Package & CI"

# package.json version
if [ -f "$ROOT_DIR/package.json" ]; then
    pkg_version=$(python3 -c "import json; print(json.load(open('$ROOT_DIR/package.json'))['version'])" 2>/dev/null || echo "")
    if [ -f "$ROOT_DIR/VERSION" ]; then
        expected_version=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
        if [ "$pkg_version" = "$expected_version" ]; then
            pass "package.json version matches VERSION ($expected_version)"
        else
            fail "package.json version ($pkg_version) does not match VERSION ($expected_version)"
        fi
    fi
    if python3 -c "import json; json.load(open('$ROOT_DIR/package.json'))" 2>/dev/null; then
        pass "package.json is valid JSON"
    else
        fail "package.json is invalid JSON"
    fi
fi

# CI workflows
for ci_file in .github/workflows/ci.yml .github/workflows/release.yml; do
    if [ -f "$ROOT_DIR/$ci_file" ]; then
        pass "$ci_file exists"
    else
        fail "$ci_file missing"
    fi
done

# Logo assets
for img in docs/images/logo.png; do
    if [ -f "$ROOT_DIR/$img" ]; then
        pass "$img exists"
    else
        warn "$img missing (marketplace logo)"
    fi
done

# ============================================
# SECTION 12: Security Scan
# ============================================
section "Security Scan"

# Check for hardcoded secrets patterns
SECRET_PATTERNS=(
    "password\s*=\s*['\"]"
    "api_key\s*=\s*['\"]"
    "secret\s*=\s*['\"]"
    "AKIA[0-9A-Z]{16}"
    "token\s*=\s*['\"][a-zA-Z0-9]"
)

for pattern in "${SECRET_PATTERNS[@]}"; do
    matches=$(grep -rn "$pattern" "$ROOT_DIR" \
        --include="*.md" --include="*.json" --include="*.yaml" --include="*.sh" \
        --exclude-dir=tests --exclude-dir=.git --exclude="CHANGELOG.md" \
        2>/dev/null | grep -v "example\|template\|placeholder\|<\|command\|install\|Version Command\|Version.*Command\|brew\|apt\|snap\|uv\|pip" || true)
    if [ -z "$matches" ]; then
        pass "No matches for pattern: $pattern"
    else
        fail "Potential secret found for pattern: $pattern"
        echo "    $matches" | head -3
    fi
done

# ============================================
# SECTION 13: Setup Script Validation
# ============================================
section "Setup Script Validation"

SETUP_SCRIPTS=("setup-claude.sh" "setup-codex.sh" "setup-gemini.sh" "setup-antigravity.sh")
for script in "${SETUP_SCRIPTS[@]}"; do
    script_path="$ROOT_DIR/scripts/setup/$script"
    if [ -f "$script_path" ]; then
        pass "scripts/setup/$script exists"
        # Check shebang
        if head -1 "$script_path" | grep -q "^#!/"; then
            pass "scripts/setup/$script has shebang"
        else
            fail "scripts/setup/$script missing shebang"
        fi
        # Check executable or has shebang
        if [ -x "$script_path" ] || head -1 "$script_path" | grep -q "^#!/usr/bin/env bash"; then
            pass "scripts/setup/$script is executable or has env bash shebang"
        else
            warn "scripts/setup/$script may not be executable"
        fi
    else
        fail "scripts/setup/$script missing"
    fi
done

# setup-antigravity.sh should reference all workflow names
antigravity_script="$ROOT_DIR/scripts/setup/setup-antigravity.sh"
if [ -f "$antigravity_script" ]; then
    EXPECTED_WORKFLOWS=("horus-full" "horus-upgrade" "horus-security" "horus-validate" "horus-new-module" "horus-cicd" "horus-health" "zeus-full" "zeus-pre-merge" "zeus-health-check" "zeus-review" "zeus-onboard" "zeus-diagram" "zeus-status" "shared-repo-detect" "shared-report-format" "shared-tool-check")
    workflow_count=0
    for wf in "${EXPECTED_WORKFLOWS[@]}"; do
        if grep -q "$wf" "$antigravity_script" 2>/dev/null; then
            ((workflow_count++))
        fi
    done
    if [ "$workflow_count" -eq "${#EXPECTED_WORKFLOWS[@]}" ]; then
        pass "setup-antigravity.sh references all ${#EXPECTED_WORKFLOWS[@]} expected workflows"
    else
        fail "setup-antigravity.sh references only $workflow_count/${#EXPECTED_WORKFLOWS[@]} expected workflows"
    fi
fi

# ============================================
# SECTION 14: Cross-Platform Parity
# ============================================
section "Cross-Platform Parity"

# All platform entry files exist
for entry_file in CLAUDE.md AGENTS.md GEMINI.md .agents/rules/devops.md; do
    if [ -f "$ROOT_DIR/$entry_file" ]; then
        pass "Platform entry file $entry_file exists"
    else
        fail "Platform entry file $entry_file missing"
    fi
done

# README mentions all 4 platforms
if [ -f "$ROOT_DIR/README.md" ]; then
    for platform in "Claude Code" "OpenAI Codex" "Gemini CLI" "Antigravity"; do
        if grep -q "$platform" "$ROOT_DIR/README.md" 2>/dev/null; then
            pass "README.md mentions $platform"
        else
            fail "README.md does not mention $platform"
        fi
    done
fi

# docs/PROJECT.md has Antigravity section
if grep -q "Antigravity" "$ROOT_DIR/docs/PROJECT.md" 2>/dev/null; then
    pass "docs/PROJECT.md mentions Antigravity"
else
    fail "docs/PROJECT.md does not mention Antigravity"
fi

# ============================================
# SECTION 15: Tool Installation Script
# ============================================
section "Tool Installation Script"

install_script="$ROOT_DIR/scripts/install-tools.sh"
if [ -f "$install_script" ]; then
    pass "install-tools.sh exists"

    if [ -x "$install_script" ] || head -1 "$install_script" | grep -q "^#!/"; then
        pass "install-tools.sh is executable"
    else
        fail "install-tools.sh is not executable"
    fi

    # Windows detection
    if grep -q "MINGW\|MSYS\|CYGWIN" "$install_script" 2>/dev/null; then
        pass "install-tools.sh contains Windows detection (MINGW/MSYS/CYGWIN)"
    else
        fail "install-tools.sh missing Windows detection"
    fi

    # All 3 package manager families
    for mgr in "brew" "apt" "winget"; do
        if grep -q "$mgr" "$install_script" 2>/dev/null; then
            pass "install-tools.sh supports $mgr package manager"
        else
            fail "install-tools.sh missing $mgr package manager support"
        fi
    done

    # Tool registry includes key tools
    for tool in "git" "kubectl" "terraform" "kustomize" "trivy" "gitleaks"; do
        if grep -q "\"$tool|" "$install_script" 2>/dev/null; then
            pass "install-tools.sh includes $tool in registry"
        else
            fail "install-tools.sh missing $tool from registry"
        fi
    done
else
    fail "install-tools.sh missing"
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo "═══════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════"
echo -e "  ${GREEN}PASS:${NC} $PASS"
echo -e "  ${RED}FAIL:${NC} $FAIL"
echo -e "  ${YELLOW}WARN:${NC} $WARN"
echo "  TOTAL: $TOTAL"
echo "═══════════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    echo -e "  ${RED}RESULT: FAILED${NC}"
    exit 1
else
    echo -e "  ${GREEN}RESULT: PASSED${NC}"
    exit 0
fi
