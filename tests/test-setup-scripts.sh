#!/usr/bin/env bash
# =============================================================================
# DevOps AI Skill Pack — Setup Script Tests
# =============================================================================
# Runs each platform setup script in an isolated temp directory and validates
# that symlinks, directories, and verification outputs are correct.
#
# Usage:
#   bash tests/test-setup-scripts.sh
# =============================================================================

set -euo pipefail

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
NC='\033[0m'

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

# --- Sandbox Setup ----------------------------------------------------------
# Create a temp directory that mimics the repo structure needed by setup scripts.
# Each test gets a fresh copy.

SANDBOX=""

create_sandbox() {
    SANDBOX=$(mktemp -d)

    # Skills directory with SKILL.md in each
    local skills=(
        cicd-enhancer helm-scaffold helm-version-upgrade
        kustomize-resource-validation repo-detect
        terraform-security terraform-validate yaml-fix-suggestions
    )
    for skill in "${skills[@]}"; do
        mkdir -p "$SANDBOX/skills/$skill"
        cat > "$SANDBOX/skills/$skill/SKILL.md" <<EOF
---
name: $skill
version: 1.1.0
description: Test skill
---
# $skill
EOF
    done

    # Prompts directory (horus + zeus + shared)
    local horus_prompts=(full-pipeline upgrade security validate new-module cicd health)
    for p in "${horus_prompts[@]}"; do
        mkdir -p "$SANDBOX/prompts/horus"
        echo "# $p" > "$SANDBOX/prompts/horus/$p.md"
    done

    local zeus_prompts=(full-pipeline pre-merge health-check review onboard diagram status)
    for p in "${zeus_prompts[@]}"; do
        mkdir -p "$SANDBOX/prompts/zeus"
        echo "# $p" > "$SANDBOX/prompts/zeus/$p.md"
    done

    local shared_prompts=(repo-detect report-format tool-check)
    for p in "${shared_prompts[@]}"; do
        mkdir -p "$SANDBOX/prompts/shared"
        echo "# $p" > "$SANDBOX/prompts/shared/$p.md"
    done

    # Platform stubs needed by verification scripts
    mkdir -p "$SANDBOX/.claude/agents"
    mkdir -p "$SANDBOX/.codex"
    mkdir -p "$SANDBOX/.gemini/agents"
    mkdir -p "$SANDBOX/.gemini/extensions/devops"
    mkdir -p "$SANDBOX/.agents/skills/horus"
    mkdir -p "$SANDBOX/.agents/skills/zeus"
    mkdir -p "$SANDBOX/.agents/rules"

    echo "# CLAUDE" > "$SANDBOX/CLAUDE.md"
    echo "# AGENTS" > "$SANDBOX/AGENTS.md"
    echo "# GEMINI" > "$SANDBOX/GEMINI.md"
    mkdir -p "$SANDBOX/docs"
    echo "# docs/PROJECT.md" > "$SANDBOX/docs/PROJECT.md"

    echo "# horus agent" > "$SANDBOX/.claude/agents/horus.md"
    echo "# zeus agent" > "$SANDBOX/.claude/agents/zeus.md"
    echo "# horus agent" > "$SANDBOX/.gemini/agents/horus.md"
    echo "# zeus agent" > "$SANDBOX/.gemini/agents/zeus.md"
    echo '{"name":"devops"}' > "$SANDBOX/.gemini/extensions/devops/gemini-extension.json"
    echo "# devops rules" > "$SANDBOX/.agents/rules/devops.md"

    cat > "$SANDBOX/.agents/skills/horus/SKILL.md" <<EOF
---
name: horus
version: 1.1.0
description: Horus agent wrapper
---
# Horus
EOF
    cat > "$SANDBOX/.agents/skills/zeus/SKILL.md" <<EOF
---
name: zeus
version: 1.1.0
description: Zeus agent wrapper
---
# Zeus
EOF

    # Copy setup scripts into sandbox (preserving relative path structure)
    mkdir -p "$SANDBOX/scripts/setup"
    cp "$ROOT_DIR/scripts/setup/setup-claude.sh" "$SANDBOX/scripts/setup/"
    cp "$ROOT_DIR/scripts/setup/setup-codex.sh" "$SANDBOX/scripts/setup/"
    cp "$ROOT_DIR/scripts/setup/setup-gemini.sh" "$SANDBOX/scripts/setup/"
    cp "$ROOT_DIR/scripts/setup/setup-antigravity.sh" "$SANDBOX/scripts/setup/"
}

cleanup_sandbox() {
    if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
        rm -rf "$SANDBOX"
    fi
    SANDBOX=""
}

# ============================================
# TEST 1: setup-claude.sh
# ============================================
section "Setup Claude Code (setup-claude.sh)"

create_sandbox
output=$(bash "$SANDBOX/scripts/setup/setup-claude.sh" 2>&1) || true

# Directory created
if [ -d "$SANDBOX/.claude/skills" ]; then
    pass ".claude/skills/ directory created"
else
    fail ".claude/skills/ directory not created"
fi

# All 8 skills symlinked
expected_skills=(
    cicd-enhancer helm-scaffold helm-version-upgrade
    kustomize-resource-validation repo-detect
    terraform-security terraform-validate yaml-fix-suggestions
)
for skill in "${expected_skills[@]}"; do
    target="$SANDBOX/.claude/skills/$skill"
    if [ -L "$target" ]; then
        # Verify symlink resolves to a valid directory
        if [ -d "$target" ]; then
            pass "Symlink $skill resolves correctly"
        else
            fail "Symlink $skill exists but target is broken"
        fi
    else
        fail "Symlink $skill not created"
    fi
done

# Count matches expected
count=$(find "$SANDBOX/.claude/skills" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
if [ "$count" -eq 8 ]; then
    pass "Correct skill count: $count"
else
    fail "Expected 8 skills, got $count"
fi

# Output contains completion message
if echo "$output" | grep -q "Claude Code setup complete"; then
    pass "Output contains completion message"
else
    fail "Missing completion message in output"
fi

# Idempotent: run again, should skip all
output2=$(bash "$SANDBOX/scripts/setup/setup-claude.sh" 2>&1) || true
skip_count=$(echo "$output2" | grep -c "\[skip\]" || true)
if [ "$skip_count" -eq 8 ]; then
    pass "Idempotent: all 8 skills skipped on re-run"
else
    fail "Idempotent check: expected 8 skips, got $skip_count"
fi

cleanup_sandbox

# ============================================
# TEST 2: setup-codex.sh
# ============================================
section "Setup Codex CLI (setup-codex.sh)"

create_sandbox
output=$(bash "$SANDBOX/scripts/setup/setup-codex.sh" 2>&1) || true

# Directory created
if [ -d "$SANDBOX/.codex/skills" ]; then
    pass ".codex/skills/ directory created"
else
    fail ".codex/skills/ directory not created"
fi

# All 8 skills symlinked
for skill in "${expected_skills[@]}"; do
    target="$SANDBOX/.codex/skills/$skill"
    if [ -L "$target" ] && [ -d "$target" ]; then
        pass "Symlink $skill resolves correctly"
    else
        fail "Symlink $skill missing or broken"
    fi
done

# Count matches
count=$(find "$SANDBOX/.codex/skills" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
if [ "$count" -eq 8 ]; then
    pass "Correct skill count: $count"
else
    fail "Expected 8 skills, got $count"
fi

# AGENTS.md check: exists → no warn
if echo "$output" | grep -q "\[warn\]"; then
    fail "Unexpected warning (AGENTS.md should exist in sandbox)"
else
    pass "No warnings (AGENTS.md present)"
fi

# Output contains completion message
if echo "$output" | grep -q "Codex CLI setup complete"; then
    pass "Output contains completion message"
else
    fail "Missing completion message in output"
fi

# Idempotent
output2=$(bash "$SANDBOX/scripts/setup/setup-codex.sh" 2>&1) || true
skip_count=$(echo "$output2" | grep -c "\[skip\]" || true)
if [ "$skip_count" -eq 8 ]; then
    pass "Idempotent: all 8 skills skipped on re-run"
else
    fail "Idempotent check: expected 8 skips, got $skip_count"
fi

cleanup_sandbox

# ============================================
# TEST 3: setup-gemini.sh
# ============================================
section "Setup Gemini CLI (setup-gemini.sh)"

create_sandbox
output=$(bash "$SANDBOX/scripts/setup/setup-gemini.sh" 2>&1) || true

# Verification checks — all should pass (files exist in sandbox)
if echo "$output" | grep -q "\[ok\] GEMINI.md found"; then
    pass "GEMINI.md verified"
else
    fail "GEMINI.md verification failed"
fi

for agent in horus zeus; do
    if echo "$output" | grep -q "\[ok\] .gemini/agents/$agent.md found"; then
        pass ".gemini/agents/$agent.md verified"
    else
        fail ".gemini/agents/$agent.md verification failed"
    fi
done

if echo "$output" | grep -q "\[ok\] gemini-extension.json found"; then
    pass "gemini-extension.json verified"
else
    fail "gemini-extension.json verification failed"
fi

# No warnings when all files present
warn_count=$(echo "$output" | grep -c "\[warn\]" || true)
if [ "$warn_count" -eq 0 ]; then
    pass "No warnings (all files present)"
else
    fail "Unexpected $warn_count warning(s)"
fi

# Output contains completion message
if echo "$output" | grep -q "Gemini CLI setup complete"; then
    pass "Output contains completion message"
else
    fail "Missing completion message in output"
fi

# Test with missing files — should warn, not fail
cleanup_sandbox
create_sandbox
rm -f "$SANDBOX/GEMINI.md"
rm -f "$SANDBOX/.gemini/agents/horus.md"
output_missing=$(bash "$SANDBOX/scripts/setup/setup-gemini.sh" 2>&1) || true
warn_count=$(echo "$output_missing" | grep -c "\[warn\]" || true)
if [ "$warn_count" -ge 2 ]; then
    pass "Graceful degradation: $warn_count warnings for missing files"
else
    fail "Expected at least 2 warnings for missing files, got $warn_count"
fi

cleanup_sandbox

# ============================================
# TEST 4: setup-antigravity.sh
# ============================================
section "Setup Antigravity (setup-antigravity.sh)"

create_sandbox
output=$(bash "$SANDBOX/scripts/setup/setup-antigravity.sh" 2>&1) || true

# Agent wrapper verification
if echo "$output" | grep -q "\[ok\] .agents/skills/horus/SKILL.md found"; then
    pass "Horus agent wrapper verified"
else
    fail "Horus agent wrapper verification failed"
fi

if echo "$output" | grep -q "\[ok\] .agents/skills/zeus/SKILL.md found"; then
    pass "Zeus agent wrapper verified"
else
    fail "Zeus agent wrapper verification failed"
fi

# Rules file verification
if echo "$output" | grep -q "\[ok\] .agents/rules/devops.md found"; then
    pass "devops.md rules file verified"
else
    fail "devops.md rules file verification failed"
fi

# Skill symlinks (8 skills)
for skill in "${expected_skills[@]}"; do
    target="$SANDBOX/.agents/skills/$skill"
    if [ -L "$target" ] && [ -d "$target" ]; then
        pass "Skill symlink $skill resolves correctly"
    else
        fail "Skill symlink $skill missing or broken"
    fi
done

# Workflow symlinks — 7 horus + 7 zeus + 3 shared = 17 total
horus_workflows=(horus-full horus-upgrade horus-security horus-validate horus-new-module horus-cicd horus-health)
zeus_workflows=(zeus-full zeus-pre-merge zeus-health-check zeus-review zeus-onboard zeus-diagram zeus-status)
shared_workflows=(shared-repo-detect shared-report-format shared-tool-check)

for wf in "${horus_workflows[@]}" "${zeus_workflows[@]}" "${shared_workflows[@]}"; do
    target="$SANDBOX/.agents/workflows/${wf}.md"
    if [ -L "$target" ]; then
        # Verify symlink resolves
        if [ -f "$target" ]; then
            pass "Workflow $wf resolves correctly"
        else
            fail "Workflow $wf symlink broken"
        fi
    else
        fail "Workflow $wf not created"
    fi
done

# Workflow count
wf_count=$(find "$SANDBOX/.agents/workflows" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
if [ "$wf_count" -eq 17 ]; then
    pass "Correct workflow count: $wf_count"
else
    fail "Expected 17 workflows, got $wf_count"
fi

# Output contains completion message
if echo "$output" | grep -q "Antigravity setup complete"; then
    pass "Output contains completion message"
else
    fail "Missing completion message in output"
fi

# Idempotent
output2=$(bash "$SANDBOX/scripts/setup/setup-antigravity.sh" 2>&1) || true
skip_count=$(echo "$output2" | grep -c "\[skip\]" || true)
# 8 skills + 17 workflows = 25 skips
if [ "$skip_count" -eq 25 ]; then
    pass "Idempotent: all 25 items skipped on re-run"
else
    fail "Idempotent check: expected 25 skips, got $skip_count"
fi

cleanup_sandbox

# ============================================
# TEST 5: Script Portability
# ============================================
section "Script Portability Checks"

# All setup scripts should use set -euo pipefail
for script in setup-claude.sh setup-codex.sh setup-gemini.sh setup-antigravity.sh; do
    path="$ROOT_DIR/scripts/setup/$script"
    if grep -q "set -euo pipefail" "$path"; then
        pass "$script uses strict mode (set -euo pipefail)"
    else
        fail "$script missing strict mode"
    fi
done

# All setup scripts should use SCRIPT_DIR/ROOT_DIR pattern (not hardcoded paths)
for script in setup-claude.sh setup-codex.sh setup-gemini.sh setup-antigravity.sh; do
    path="$ROOT_DIR/scripts/setup/$script"
    if grep -q 'SCRIPT_DIR=' "$path" && grep -q 'ROOT_DIR=' "$path"; then
        pass "$script uses dynamic path resolution"
    else
        fail "$script missing dynamic path resolution"
    fi
done

# All setup scripts should have shebangs
for script in setup-claude.sh setup-codex.sh setup-gemini.sh setup-antigravity.sh; do
    path="$ROOT_DIR/scripts/setup/$script"
    if head -1 "$path" | grep -q "^#!/"; then
        pass "$script has shebang"
    else
        fail "$script missing shebang"
    fi
done

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
