---
name: release-validate
description: >
  Validates package release readiness across version consistency, cross-platform
  link integrity, npm package content, and setup script smoke testing. Use before
  running `pnpm release` to catch issues that structure tests may miss.
version: "1.0.0"
---

# Release Validation Skill

## Purpose

Pre-release quality gate that validates the devops-ai-skill pack is ready to publish. Covers three areas that existing tests do not fully address:

1. **Package release checks** — version sync, changelog, npm pack content, git state
2. **Cross-platform link validation** — all 4 platforms correctly reference skills, prompts, and agents
3. **Setup script smoke testing** — dry-run validation of setup scripts in a sandboxed temp directory

## Activation

This skill activates when the user:
- Asks to validate a release before publishing
- Runs a pre-release check or readiness assessment
- Wants to verify cross-platform consistency
- Asks to smoke-test the setup scripts

## Phase 1: Package Release Checks

### 1a: Version Consistency

Run the existing version consistency check and interpret results:
```bash
bash scripts/version-consistency.sh
```

Verify these 5 files all contain the same version:
- `VERSION` (source of truth)
- `package.json`
- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.gemini/extensions/devops/gemini-extension.json`

### 1b: Changelog Validation

```bash
VERSION=$(cat VERSION | tr -d '[:space:]')
```

Check that `CHANGELOG.md` contains:
- An entry header matching `## [$VERSION]` (required by `release.sh`)
- A date in the entry (format: `YYYY-MM-DD`)
- At least one bullet point describing changes

### 1c: npm Pack Dry-Run

Simulate what `npm publish` would include:
```bash
pnpm pack --dry-run 2>&1
```

Validate the packed tarball would contain:
- All skill directories: `skills/*/SKILL.md`
- All prompt files: `prompts/horus/*.md`, `prompts/zeus/*.md`, `prompts/shared/*.md`
- Agent definitions: `.claude/agents/horus.md`, `.claude/agents/zeus.md`
- Plugin config: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Setup scripts: `scripts/setup.sh`, `install-global.sh`
- Core docs: `docs/PROJECT.md`
- No secrets or unwanted files (`.env`, `node_modules/`, `.DS_Store`)

Cross-reference with `.npmignore` or `package.json` `files` field to ensure nothing critical is excluded.

### 1d: Git State Check

Verify the repository is in a clean state for release:
- No uncommitted changes: `git status --porcelain` should be empty
- Current branch is `main`
- Tag `v$VERSION` does not already exist
- Local `main` is up-to-date with `origin/main` (no unpushed commits)

## Phase 2: Cross-Platform Link Validation

### 2a: Discover All Cross-References

Build a reference graph by scanning these entry-point files:

| Platform | Entry File | References To |
|----------|-----------|---------------|
| Claude Code | `CLAUDE.md` | `docs/PROJECT.md`, `prompts/`, `.claude/agents/` |
| Claude Plugin | `.claude-plugin/plugin.json` | skills, agents, commands |
| Codex | `AGENTS.md` | `docs/PROJECT.md`, `prompts/`, `skills/` |
| Gemini | `GEMINI.md` | `docs/PROJECT.md`, `.gemini/commands/`, `.gemini/agents/` |
| Antigravity | `.agents/rules/devops.md` | `docs/PROJECT.md`, `prompts/`, `.agents/skills/` |

### 2b: Validate All Referenced Paths Exist

For each cross-reference found in Step 2a:
1. Extract file paths from markdown links: `[text](path)` and inline references
2. Extract paths from code blocks and configuration
3. Verify each referenced file or directory exists on disk

Report:
```
Cross-Platform Link Validation
===============================
Scanning: CLAUDE.md
  ✓ docs/PROJECT.md
  ✓ prompts/horus/full-pipeline.md
  ✗ prompts/horus/migrate.md (NOT FOUND)

Scanning: .claude-plugin/plugin.json
  ✓ skills/terraform-validate/SKILL.md
  ...
```

### 2c: Validate Skill Registration Parity

Ensure all skills are registered across all platforms that support them:

1. **Canonical skill list**: Read all directories under `skills/`
2. **Claude Code**: Check `.claude-plugin/plugin.json` registers all skills
3. **Gemini**: Check `.gemini/commands/devops/` has a TOML command for each skill
4. **Antigravity**: Check `.agents/skills/` has entries for each skill
5. **Codex**: Check `AGENTS.md` references all skills

Report any skill that exists in `skills/` but is missing from a platform.

### 2d: Validate Pipeline Registration Parity

Ensure all pipelines are documented consistently:

1. **Canonical pipeline list**: Read all `.md` files under `prompts/horus/` and `prompts/zeus/`
2. **CLAUDE.md**: Check command table lists all pipelines
3. **docs/PROJECT.md**: Check pipeline section matches
4. **Gemini commands**: Check `.gemini/commands/devops/` TOML files cover all pipelines
5. **Antigravity workflows**: Check `.agents/skills/` workflow files cover all pipelines

Report any pipeline that exists on disk but is missing from a platform's documentation.

## Phase 3: Setup Script Smoke Testing

### 3a: Create Sandboxed Test Environment

```bash
TEST_DIR=$(mktemp -d)
# Simulate a target repository with the skill pack installed
mkdir -p "$TEST_DIR/target-repo"
cp -r . "$TEST_DIR/target-repo/devops-ai-skill"
cd "$TEST_DIR/target-repo"
```

### 3b: Test setup.sh for Each Platform

Run each platform flag in the sandboxed directory and verify expected outputs:

**Claude Code** (`--claude`):
```bash
bash devops-ai-skill/scripts/setup.sh --claude
```
Verify:
- `.claude/agents/horus.md` and `.claude/agents/zeus.md` are symlinks
- All 8 skill symlinks exist under expected locations
- No `[fail]` in output
- Exit code is 0

**Codex** (`--codex`):
```bash
bash devops-ai-skill/scripts/setup.sh --codex
```
Verify:
- `AGENTS.md` exists or is symlinked
- Skill references are accessible
- Exit code is 0

**Gemini** (`--gemini`):
```bash
bash devops-ai-skill/scripts/setup.sh --gemini
```
Verify:
- `.gemini/commands/devops/` directory has TOML command files
- `.gemini/agents/` has agent definitions
- Exit code is 0

**Antigravity** (`--antigravity`):
```bash
bash devops-ai-skill/scripts/setup.sh --antigravity
```
Verify:
- `.agents/skills/` has skill entries
- `.agents/skills/` has workflow entries
- Exit code is 0

### 3c: Test Idempotency

Run each setup command a second time and verify:
- All items show `[skip]` (not `[link]` or `[fail]`)
- Exit code is still 0
- No duplicate symlinks or files created

### 3d: Test Uninstall

```bash
bash devops-ai-skill/scripts/setup.sh --uninstall
```
Verify:
- All symlinks created in 3b are removed
- No `[fail]` in output
- Original target repo files (if any) are preserved

### 3e: Cleanup

```bash
rm -rf "$TEST_DIR"
```

Always clean up the temp directory, even on failure (use `trap`).

## Output Format

Present results as a release readiness report:

```
Release Validation Report — v1.5.0
====================================

Phase 1: Package Release Checks
  ✓ Version consistency (5/5 files match)
  ✓ CHANGELOG.md has entry for 1.5.0
  ✓ npm pack includes 47 expected files
  ✗ Git: 2 uncommitted changes detected

Phase 2: Cross-Platform Links
  ✓ CLAUDE.md: 12/12 links valid
  ✓ AGENTS.md: 8/8 links valid
  ✗ GEMINI.md: 9/10 links valid (1 broken)
  ✓ Antigravity: 26/26 links valid
  ✓ Skill parity: 8/8 skills registered on all platforms
  ✗ Pipeline parity: 13/14 pipelines registered (missing: zeus/status in Gemini)

Phase 3: Setup Script Smoke Tests
  ✓ --claude: 10 items linked, idempotent, uninstall clean
  ✓ --codex: 9 items linked, idempotent, uninstall clean
  ✗ --gemini: exit code 1 (missing .gemini/agents/ source)
  ✓ --antigravity: 26 items linked, idempotent, uninstall clean

====================================
Result: 3 issues found — fix before release
  1. 2 uncommitted changes (run: git status)
  2. GEMINI.md broken link: prompts/zeus/migrate.md
  3. --gemini setup failed (check .gemini/agents/ directory)
```

## Scope Flags

The user can run specific phases:
- `--all` (default): Run all 3 phases
- `--package`: Phase 1 only (version, changelog, npm, git)
- `--links`: Phase 2 only (cross-platform reference validation)
- `--smoke`: Phase 3 only (setup script smoke tests)
- `--quick`: Phase 1 + 2 only (skip slow smoke tests)

## Error Handling

### Discovery Failures
- **Missing VERSION file**: Report "Cannot determine version — VERSION file not found" and stop.
- **Missing scripts**: If `version-consistency.sh` or `setup.sh` is missing, report and skip that check.
- **pnpm not installed**: Fall back to `npm pack --dry-run` for package content check.

### Smoke Test Failures
- **mktemp fails**: Skip Phase 3, report that smoke testing requires a writable temp directory.
- **setup.sh crashes mid-run**: Capture stderr, report the failure, continue with remaining platforms.
- **Symlink target doesn't exist**: Report which source file is missing (this usually indicates a file was deleted but not cleaned up from setup scripts).

### Edge Cases
- **New skill added but not registered**: Phase 2c catches this — report which platforms are missing the registration.
- **Pipeline renamed but old name in docs**: Phase 2d catches stale references.
- **Version already tagged**: Phase 1d reports this — user must either bump version or delete the existing tag.

## Dry-Run Support

This skill is **read-only** for Phases 1 and 2. Phase 3 creates a temporary directory but does not modify the source repository. All changes are isolated to the sandboxed `$TEST_DIR`.

## Dependencies

- `scripts/version-consistency.sh` — Reused for version checks
- `scripts/setup.sh` — Tested in Phase 3
- `pnpm` or `npm` — For pack dry-run
- `git` — For state checks
- `mktemp` — For sandboxed smoke tests
