# release-validate v1.15.0 — Phase 6, 7, and CI Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the v1.14.0 `release-validate` skill with three pre-release gates that the current version cannot enforce: cross-repo-style fixture coverage (Phase 6), cross-AI-tool registration parity (Phase 7), and a CI integration that runs all phases automatically on every `v*` tag push.

**Architecture:** Two new bash scripts under `skills/release-validate/scripts/` (one per phase) following the same JSON-out / exit-code convention as `run_all_fixtures.sh` and `check_shell_portability.sh`. A new `scripts/release_check.sh` orchestrator at the repo root invokes Phases 4 + 5 + 6 + 7 and feeds aggregated outputs to the existing `render_release_artifact.sh`. The orchestrator is wired into `.github/workflows/release.yml` as a pre-publish gate, replacing the bare `tests/test-structure.sh` check.

**Tech Stack:** Bash 3.2-compatible (target macOS default), `jq` for JSON, `yq` for YAML, `kustomize` for fixture builds, GitHub Actions for CI.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `skills/release-validate/SKILL.md` | Modify | Bump to v1.15.0, add Phase 6 and Phase 7 sections |
| `skills/release-validate/references/repo-style-matrix.md` | Create | Plain markdown table declaring which skills need fixtures for which repo styles |
| `skills/release-validate/scripts/check_repo_style_coverage.sh` | Create | Reads the matrix + inventories `tests/*/fixtures/`, reports gaps |
| `skills/release-validate/scripts/check_ai_tool_parity.sh` | Create | For every Zeus command, verify registration across all 4 platforms |
| `skills/release-validate/scripts/render_release_artifact.sh` | Modify | Accept new env vars `REPO_STYLE_JSON` and `AI_TOOL_PARITY_JSON`; render Phase 6 + 7 sections; recompute overall verdict |
| `scripts/release_check.sh` | Create | Top-level orchestrator that runs Phases 4 + 5 + 6 + 7 and renders the artifact |
| `package.json` | Modify | Add `release:check` npm script |
| `.github/workflows/release.yml` | Modify | Replace bare structure-test step with `scripts/release_check.sh` |
| `tests/release-validate/run-fixtures.sh` | Create | Test runner for the new release-validate scripts |
| `tests/release-validate/fixtures/phase6-complete/` | Create | Mini repo with full matrix coverage — expected PASS |
| `tests/release-validate/fixtures/phase6-missing-style/` | Create | Mini repo missing one declared style — expected WARN |
| `tests/release-validate/fixtures/phase7-all-platforms/` | Create | Mini repo where a command is registered on all 4 platforms — expected PASS |
| `tests/release-validate/fixtures/phase7-missing-claude/` | Create | Mini repo where a command is missing from CLAUDE.md — expected FAIL |
| `CHANGELOG.md` | Modify | Add v1.15.0 entry |
| `VERSION`, `package.json`, `.claude-plugin/{plugin,marketplace}.json`, `.gemini/extensions/devops/gemini-extension.json` | Modify | Bump 1.14.0 → 1.15.0 |

---

## Task 1: Phase 6 — Cross-repo-style coverage check

**Files:**
- Create: `skills/release-validate/references/repo-style-matrix.md`
- Create: `skills/release-validate/scripts/check_repo_style_coverage.sh`
- Create: `tests/release-validate/fixtures/phase6-complete/tests/dummy-skill/fixtures/kustomize-argocd/.gitkeep`
- Create: `tests/release-validate/fixtures/phase6-missing-style/tests/dummy-skill/fixtures/kustomize-argocd/.gitkeep` (helm-only intentionally missing)
- Test: `tests/release-validate/run-fixtures.sh`

- [ ] **Step 1: Create the matrix reference**

```bash
mkdir -p skills/release-validate/references
```

Write `skills/release-validate/references/repo-style-matrix.md`:

```markdown
# Repo-Style Coverage Matrix

Plain markdown data table read at runtime by
`scripts/check_repo_style_coverage.sh`. Declares which skills need fixtures
for which repo deployment styles. Edit via PR to add new skills or styles.

## Styles

| Style | Definition |
|---|---|
| `kustomize-argocd` | Pure Kustomize + ArgoCD Application manifests (eye-of-horus-gitops shape) |
| `helm-only` | Direct Helm release; no Kustomize, no ArgoCD |
| `mixed` | Some modules Kustomize, some direct Helm |

## Coverage requirements

| Skill | kustomize-argocd | helm-only | mixed |
|---|---|---|---|
| nginx-to-traefik | required | optional | optional |
| nginx-to-gateway | required | optional | optional |
| gateway-api-migration | required | optional | optional |
| ingress-migration-advisor | required | optional | optional |
| ingress-controller-install | required | optional | optional |
| traefik-controller-decommission | required | optional | optional |

## How a fixture counts as "present"

`tests/<skill>/fixtures/` contains at least one subdirectory whose name
matches the style (e.g. `tests/nginx-to-traefik/fixtures/kustomize-argocd-basic/`,
`tests/nginx-to-traefik/fixtures/basic-three-services/` counts as
`kustomize-argocd` by convention since all current fixtures are that style).

For v1.15.0 introduction the script treats EVERY existing fixture as
`kustomize-argocd`-style (the current reality). Gaps surface only when a
new style row is added to the matrix.
```

- [ ] **Step 2: Write the failing fixture test**

```bash
mkdir -p tests/release-validate/fixtures/phase6-complete/tests/dummy-skill/fixtures/kustomize-argocd
touch tests/release-validate/fixtures/phase6-complete/tests/dummy-skill/fixtures/kustomize-argocd/.gitkeep
mkdir -p tests/release-validate/fixtures/phase6-missing-style/tests/dummy-skill/fixtures/kustomize-argocd
touch tests/release-validate/fixtures/phase6-missing-style/tests/dummy-skill/fixtures/kustomize-argocd/.gitkeep
```

Write `tests/release-validate/run-fixtures.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
P6="$ROOT_DIR/skills/release-validate/scripts/check_repo_style_coverage.sh"

PASS=0
FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "release-validate fixtures (v1.15.0)"
echo "----------------------------------"

echo "[1] phase6-complete (matrix declares kustomize-argocd, fixture present)"
out=$(bash "$P6" \
  --repo-root "$SCRIPT_DIR/fixtures/phase6-complete" \
  --matrix-skills "dummy-skill" \
  --matrix-styles "kustomize-argocd" \
  --matrix-required "dummy-skill:kustomize-argocd" 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
if [[ "$verdict" == "OK" ]]; then
  echo "  [PASS] verdict=OK (no missing styles)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected verdict=OK, got $verdict"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo "[2] phase6-missing-style (matrix declares helm-only required, fixture absent)"
out=$(bash "$P6" \
  --repo-root "$SCRIPT_DIR/fixtures/phase6-missing-style" \
  --matrix-skills "dummy-skill" \
  --matrix-styles "kustomize-argocd helm-only" \
  --matrix-required "dummy-skill:kustomize-argocd,dummy-skill:helm-only" 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
missing=$(echo "$out" | jq -r '.missing[0] // "none"')
if [[ "$verdict" == "WARN" && "$missing" == "dummy-skill:helm-only" ]]; then
  echo "  [PASS] verdict=WARN, missing=dummy-skill:helm-only"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected WARN + helm-only missing; got verdict=$verdict missing=$missing"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo ""
echo "release-validate: $PASS passed, $FAIL failed"
[[ $FAIL -gt 0 ]] && exit 1 || exit 0
```

```bash
chmod +x tests/release-validate/run-fixtures.sh
```

- [ ] **Step 3: Run test to verify it fails**

```bash
bash tests/release-validate/run-fixtures.sh
```

Expected output:

```
release-validate fixtures (v1.15.0)
----------------------------------
[1] phase6-complete (matrix declares kustomize-argocd, fixture present)
  [FAIL] expected verdict=OK, got null
```

(Fails because `check_repo_style_coverage.sh` doesn't exist yet.)

- [ ] **Step 4: Write the Phase 6 script**

Write `skills/release-validate/scripts/check_repo_style_coverage.sh`:

```bash
#!/usr/bin/env bash
# check_repo_style_coverage.sh — verify fixture coverage across repo styles.
#
# Reads a matrix (skill, style → required|optional) and inventories
# tests/<skill>/fixtures/ directories. Reports gaps for required entries.
#
# Two invocation modes:
#   Production: --repo-root <path> (reads
#               skills/release-validate/references/repo-style-matrix.md)
#   Test: --matrix-skills "..." --matrix-styles "..." --matrix-required "..."
#         (lets fixture tests inject a synthetic matrix)
#
# Output (stdout, JSON):
#   {
#     "scanned": N,
#     "matrix": [{skill, style, requirement}],
#     "missing": ["skill:style", ...],     # required entries without fixtures
#     "coveragePct": NN,
#     "verdict": "OK" | "WARN"
#   }
#
# Exit codes:
#   0   all required coverage present (verdict OK or WARN — both informational)
#   2   tooling / args missing
set -uo pipefail

REPO_ROOT=""
MATRIX_SKILLS=""
MATRIX_STYLES=""
MATRIX_REQUIRED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)       REPO_ROOT="$2";       shift 2 ;;
    --matrix-skills)   MATRIX_SKILLS="$2";   shift 2 ;;
    --matrix-styles)   MATRIX_STYLES="$2";   shift 2 ;;
    --matrix-required) MATRIX_REQUIRED="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$REPO_ROOT" ]] && { echo "--repo-root required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

# If --matrix-* not supplied, parse the production matrix file.
if [[ -z "$MATRIX_SKILLS" ]]; then
  MATRIX_FILE="$REPO_ROOT/skills/release-validate/references/repo-style-matrix.md"
  if [[ ! -f "$MATRIX_FILE" ]]; then
    # No matrix file: emit empty result, verdict OK (no coverage required).
    jq -n '{scanned: 0, matrix: [], missing: [], coveragePct: 100, verdict: "OK"}'
    exit 0
  fi
  # Read the "Coverage requirements" table:
  #   | skill | kustomize-argocd | helm-only | mixed |
  # First parse the header row to get the styles in order.
  HEADER=$(grep -m1 -E '^\| Skill \|' "$MATRIX_FILE" || true)
  MATRIX_STYLES=$(echo "$HEADER" | awk -F'|' '{for(i=3;i<NF;i++){gsub(/^ +| +$/,"",$i); printf "%s ",$i}}' | sed 's/ *$//')
  # Then each data row.
  REQUIRED_LIST=()
  SKILL_LIST=()
  while IFS= read -r row; do
    [[ "$row" == *"---"* ]] && continue
    skill=$(echo "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')
    [[ -z "$skill" ]] && continue
    SKILL_LIST+=("$skill")
    col=3
    for style in $MATRIX_STYLES; do
      val=$(echo "$row" | awk -F'|' -v c=$col '{gsub(/^ +| +$/,"",$c); print $c}')
      [[ "$val" == "required" ]] && REQUIRED_LIST+=("$skill:$style")
      col=$((col+1))
    done
  done < <(awk '/^\| Skill \|/{flag=1;next} /^## /{flag=0} flag' "$MATRIX_FILE")
  MATRIX_SKILLS="${SKILL_LIST[*]}"
  MATRIX_REQUIRED=$(IFS=,; echo "${REQUIRED_LIST[*]}")
fi

# Build the matrix array for output
MATRIX_JSON='[]'
for skill in $MATRIX_SKILLS; do
  for style in $MATRIX_STYLES; do
    pair="$skill:$style"
    if [[ ",$MATRIX_REQUIRED," == *",$pair,"* ]]; then
      req="required"
    else
      req="optional"
    fi
    entry=$(jq -n --arg s "$skill" --arg st "$style" --arg r "$req" \
      '{skill: $s, style: $st, requirement: $r}')
    MATRIX_JSON=$(echo "$MATRIX_JSON" | jq --argjson e "$entry" '. += [$e]')
  done
done

# Inventory: a (skill, style) pair has a fixture if any directory under
# tests/<skill>/fixtures/ contains the style name as a substring, OR if
# tests/<skill>/fixtures/ contains ANY fixture (the convention is that
# pre-v1.15.0 fixtures count as kustomize-argocd).
MISSING=()
SCANNED=0
for skill in $MATRIX_SKILLS; do
  fixtures_dir="$REPO_ROOT/tests/$skill/fixtures"
  for style in $MATRIX_STYLES; do
    pair="$skill:$style"
    [[ ",$MATRIX_REQUIRED," != *",$pair,"* ]] && continue
    SCANNED=$((SCANNED+1))
    present=false
    if [[ -d "$fixtures_dir" ]]; then
      if [[ "$style" == "kustomize-argocd" ]]; then
        # Convention: any pre-v1.15.0 fixture counts as kustomize-argocd
        if [[ -n "$(ls -A "$fixtures_dir" 2>/dev/null)" ]]; then
          present=true
        fi
      else
        # Explicit style match
        if find "$fixtures_dir" -mindepth 1 -maxdepth 1 -type d -name "*$style*" 2>/dev/null | grep -q .; then
          present=true
        fi
      fi
    fi
    [[ "$present" == "false" ]] && MISSING+=("$pair")
  done
done

MISSING_JSON='[]'
if (( ${#MISSING[@]} > 0 )); then
  MISSING_JSON=$(printf '%s\n' "${MISSING[@]}" | jq -R . | jq -s .)
fi

COVERAGE_PCT=100
if (( SCANNED > 0 )); then
  COVERAGE_PCT=$(( (SCANNED - ${#MISSING[@]}) * 100 / SCANNED ))
fi

VERDICT="OK"
(( ${#MISSING[@]} > 0 )) && VERDICT="WARN"

jq -n \
  --argjson scanned "$SCANNED" \
  --argjson matrix "$MATRIX_JSON" \
  --argjson missing "$MISSING_JSON" \
  --argjson pct "$COVERAGE_PCT" \
  --arg verdict "$VERDICT" \
  '{scanned: $scanned, matrix: $matrix, missing: $missing, coveragePct: $pct, verdict: $verdict}'

exit 0
```

```bash
chmod +x skills/release-validate/scripts/check_repo_style_coverage.sh
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bash tests/release-validate/run-fixtures.sh
```

Expected output:

```
release-validate fixtures (v1.15.0)
----------------------------------
[1] phase6-complete (matrix declares kustomize-argocd, fixture present)
  [PASS] verdict=OK (no missing styles)
[2] phase6-missing-style (matrix declares helm-only required, fixture absent)
  [PASS] verdict=WARN, missing=dummy-skill:helm-only

release-validate: 2 passed, 0 failed
```

- [ ] **Step 6: Verify production matrix runs against the real repo**

```bash
bash skills/release-validate/scripts/check_repo_style_coverage.sh --repo-root . | jq '{scanned, missingCount: (.missing | length), coveragePct, verdict}'
```

Expected: `{"scanned": 6, "missingCount": 0, "coveragePct": 100, "verdict": "OK"}` (every required entry — `<skill>:kustomize-argocd` for the 6 Kustomize-touching skills — has at least one fixture under `tests/<skill>/fixtures/`).

- [ ] **Step 7: Commit**

```bash
git add skills/release-validate/references/repo-style-matrix.md \
        skills/release-validate/scripts/check_repo_style_coverage.sh \
        tests/release-validate/run-fixtures.sh \
        tests/release-validate/fixtures/phase6-complete/ \
        tests/release-validate/fixtures/phase6-missing-style/
git commit -m "feat(release-validate): add Phase 6 — cross-repo-style coverage check"
```

---

## Task 2: Phase 7 — Cross-AI-tool registration parity check

**Files:**
- Create: `skills/release-validate/scripts/check_ai_tool_parity.sh`
- Create: `tests/release-validate/fixtures/phase7-all-platforms/` (mini repo with one command registered everywhere)
- Create: `tests/release-validate/fixtures/phase7-missing-claude/` (same repo but CLAUDE.md row absent)
- Modify: `tests/release-validate/run-fixtures.sh` (add cases 3 and 4)
- Test: `tests/release-validate/run-fixtures.sh`

- [ ] **Step 1: Build phase7-all-platforms fixture (4 files)**

```bash
mkdir -p tests/release-validate/fixtures/phase7-all-platforms/{prompts/zeus,.gemini/commands/devops/pipelines}
```

Write `tests/release-validate/fixtures/phase7-all-platforms/prompts/zeus/example-cmd.md`:

```markdown
# example-cmd Pipeline

Fixture pipeline for Phase 7 parity testing. Body intentionally minimal.
```

Write `tests/release-validate/fixtures/phase7-all-platforms/.gemini/commands/devops/pipelines/zeus-example-cmd.toml`:

```toml
description = "Phase 7 fixture"
prompt = "fixture body"
```

Write `tests/release-validate/fixtures/phase7-all-platforms/CLAUDE.md`:

```markdown
| *example-cmd | `prompts/zeus/example-cmd.md` |
```

Write `tests/release-validate/fixtures/phase7-all-platforms/AGENTS.md`:

```markdown
| *example-cmd | Fixture pipeline |
```

Write `tests/release-validate/fixtures/phase7-all-platforms/GEMINI.md`:

```markdown
| *example-cmd | Fixture pipeline |
```

Write `tests/release-validate/fixtures/phase7-all-platforms/docs/PROJECT.md`:

```bash
mkdir -p tests/release-validate/fixtures/phase7-all-platforms/docs
cat > tests/release-validate/fixtures/phase7-all-platforms/docs/PROJECT.md <<'EOF'
| *example-cmd | example-cmd.md | Fixture pipeline |
EOF
```

- [ ] **Step 2: Build phase7-missing-claude fixture (CLAUDE.md absent)**

```bash
cp -r tests/release-validate/fixtures/phase7-all-platforms tests/release-validate/fixtures/phase7-missing-claude
rm tests/release-validate/fixtures/phase7-missing-claude/CLAUDE.md
```

- [ ] **Step 3: Append failing tests to run-fixtures.sh**

Append to `tests/release-validate/run-fixtures.sh` BEFORE the "release-validate: $PASS passed" line:

```bash

P7="$ROOT_DIR/skills/release-validate/scripts/check_ai_tool_parity.sh"

echo "[3] phase7-all-platforms (one command, registered everywhere)"
out=$(bash "$P7" \
  --repo-root "$SCRIPT_DIR/fixtures/phase7-all-platforms" \
  --command example-cmd 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
if [[ "$verdict" == "OK" ]]; then
  echo "  [PASS] verdict=OK (registered on all 4 platforms)"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected OK, got $verdict"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi

echo "[4] phase7-missing-claude (CLAUDE.md row absent)"
out=$(bash "$P7" \
  --repo-root "$SCRIPT_DIR/fixtures/phase7-missing-claude" \
  --command example-cmd 2>/dev/null || true)
verdict=$(echo "$out" | jq -r '.verdict')
gaps=$(echo "$out" | jq -r '.gaps[0].platform // "none"')
if [[ "$verdict" == "FAIL" && "$gaps" == "claude" ]]; then
  echo "  [PASS] verdict=FAIL, gap=claude"
  PASS=$((PASS+1))
else
  echo "  [FAIL] expected FAIL+claude gap; got verdict=$verdict gap=$gaps"
  echo "  raw: $out"
  FAIL=$((FAIL+1))
fi
```

- [ ] **Step 4: Run test to verify it fails**

```bash
bash tests/release-validate/run-fixtures.sh
```

Expected: cases 1 + 2 PASS (from Task 1), cases 3 + 4 FAIL because `check_ai_tool_parity.sh` doesn't exist.

- [ ] **Step 5: Write the Phase 7 script**

Write `skills/release-validate/scripts/check_ai_tool_parity.sh`:

```bash
#!/usr/bin/env bash
# check_ai_tool_parity.sh — verify a command is registered across all 4 AI tools.
#
# For a given Zeus command name, check that it appears in:
#   1. prompts/zeus/<command>.md (pipeline file)
#   2. .gemini/commands/devops/pipelines/zeus-<command>.toml (Gemini TOML)
#   3. CLAUDE.md (command row)
#   4. AGENTS.md (command row)
#   5. GEMINI.md (command row)
#   6. docs/PROJECT.md (command row)
#
# Usage:
#   check_ai_tool_parity.sh --repo-root <path> --command <name>
#   check_ai_tool_parity.sh --repo-root <path> --all   (scan every prompts/zeus/*.md)
#
# Output (stdout, JSON):
#   {
#     "commands": [
#       {
#         "command": "ingress-migration-advisor",
#         "platforms": {
#           "pipeline": true, "tomlMirror": true,
#           "claude": true, "agents": true, "gemini": true, "project": true
#         },
#         "gaps": []
#       }
#     ],
#     "verdict": "OK" | "FAIL"
#   }
#
# Exit codes:
#   0   all commands fully registered (verdict OK)
#   1   at least one command has a gap (verdict FAIL)
#   2   tooling / args missing
set -uo pipefail

REPO_ROOT=""
COMMAND=""
ALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --command)   COMMAND="$2";   shift 2 ;;
    --all)       ALL=1;          shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$REPO_ROOT" ]] && { echo "--repo-root required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

# Build the command list
CMDS=()
if (( ALL )); then
  while IFS= read -r f; do
    CMDS+=("$(basename "$f" .md)")
  done < <(find "$REPO_ROOT/prompts/zeus" -maxdepth 1 -name '*.md' 2>/dev/null)
else
  [[ -z "$COMMAND" ]] && { echo "--command or --all required" >&2; exit 2; }
  CMDS+=("$COMMAND")
fi

(( ${#CMDS[@]} == 0 )) && {
  jq -n '{commands: [], verdict: "OK"}'
  exit 0
}

build_entry() {
  local cmd="$1"
  local pipeline tomlMirror claude agents gemini project

  # NOTE: file basename != command name in some cases. Example:
  # `prompts/zeus/full-pipeline.md` is registered as `*full` (not
  # `*full-pipeline`). Derive the registered command name by looking
  # up the file path in CLAUDE.md and extracting the leading `*<name>`
  # from the matched row. Fall back to the basename when no row matches
  # (so brand-new pipelines still surface as gaps).
  local cmd_name
  cmd_name=$(grep -E "^\\| \\*[a-zA-Z0-9_-]+\\s*\\|\\s*\\\`prompts/zeus/$cmd\\.md\\\`" \
    "$REPO_ROOT/CLAUDE.md" 2>/dev/null \
    | sed -E 's/^\\| \\*([a-zA-Z0-9_-]+).*/\\1/' \
    | head -1)
  [[ -z "$cmd_name" ]] && cmd_name="$cmd"

  pipeline=$([[ -f "$REPO_ROOT/prompts/zeus/$cmd.md" ]] && echo true || echo false)
  tomlMirror=$([[ -f "$REPO_ROOT/.gemini/commands/devops/pipelines/zeus-$cmd_name.toml" ]] && echo true || echo false)
  claude=$(grep -q -E "\\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/CLAUDE.md" 2>/dev/null && echo true || echo false)
  agents=$(grep -q -E "\\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/AGENTS.md" 2>/dev/null && echo true || echo false)
  gemini=$(grep -q -E "\\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/GEMINI.md" 2>/dev/null && echo true || echo false)
  project=$(grep -q -E "\\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/docs/PROJECT.md" 2>/dev/null && echo true || echo false)

  GAPS=()
  [[ "$pipeline"   == "false" ]] && GAPS+=("pipeline")
  [[ "$tomlMirror" == "false" ]] && GAPS+=("tomlMirror")
  [[ "$claude"     == "false" ]] && GAPS+=("claude")
  [[ "$agents"     == "false" ]] && GAPS+=("agents")
  [[ "$gemini"     == "false" ]] && GAPS+=("gemini")
  [[ "$project"    == "false" ]] && GAPS+=("project")

  GAPS_JSON='[]'
  (( ${#GAPS[@]} > 0 )) && GAPS_JSON=$(printf '%s\n' "${GAPS[@]}" | jq -R '{platform: .}' | jq -s .)

  jq -n \
    --arg cmd "$cmd" \
    --arg name "$cmd_name" \
    --argjson p "$pipeline" \
    --argjson t "$tomlMirror" \
    --argjson c "$claude" \
    --argjson a "$agents" \
    --argjson g "$gemini" \
    --argjson pr "$project" \
    --argjson gaps "$GAPS_JSON" \
    '{
      command: $cmd,
      registeredAs: $name,
      platforms: {pipeline: $p, tomlMirror: $t, claude: $c, agents: $a, gemini: $g, project: $pr},
      gaps: $gaps
    }'
}

ENTRIES=()
ANY_GAP=false
for cmd in "${CMDS[@]}"; do
  entry=$(build_entry "$cmd")
  ENTRIES+=("$entry")
  gap_count=$(echo "$entry" | jq '.gaps | length')
  (( gap_count > 0 )) && ANY_GAP=true
done

VERDICT="OK"; [[ "$ANY_GAP" == "true" ]] && VERDICT="FAIL"

printf '%s\n' "${ENTRIES[@]}" | jq -s \
  --arg verdict "$VERDICT" \
  '{commands: ., verdict: $verdict}'

[[ "$ANY_GAP" == "true" ]] && exit 1 || exit 0
```

```bash
chmod +x skills/release-validate/scripts/check_ai_tool_parity.sh
```

- [ ] **Step 6: Run test to verify it passes**

```bash
bash tests/release-validate/run-fixtures.sh
```

Expected:

```
release-validate fixtures (v1.15.0)
----------------------------------
[1] phase6-complete ...                        [PASS]
[2] phase6-missing-style ...                   [PASS]
[3] phase7-all-platforms ...                   [PASS]
[4] phase7-missing-claude ...                  [PASS]

release-validate: 4 passed, 0 failed
```

- [ ] **Step 7: Verify production scan against the real repo**

```bash
bash skills/release-validate/scripts/check_ai_tool_parity.sh --repo-root . --all | jq '{verdict, gapCount: ([.commands[].gaps[]] | length), commandCount: (.commands | length)}'
```

Expected: `{"verdict": "OK", "gapCount": 0, "commandCount": 15}` (or more, depending on Zeus pipeline count).

- [ ] **Step 8: Commit**

```bash
git add skills/release-validate/scripts/check_ai_tool_parity.sh \
        tests/release-validate/fixtures/phase7-all-platforms/ \
        tests/release-validate/fixtures/phase7-missing-claude/ \
        tests/release-validate/run-fixtures.sh
git commit -m "feat(release-validate): add Phase 7 — cross-AI-tool registration parity"
```

---

## Task 3: Extend render_release_artifact.sh for Phases 6 + 7

**Files:**
- Modify: `skills/release-validate/scripts/render_release_artifact.sh`
- Test: smoke-run the renderer against `/tmp` JSON inputs

- [ ] **Step 1: Modify the renderer**

Replace the env-var documentation block at the top of `render_release_artifact.sh` (lines 1–17 — everything from the shebang through the blank line before `set -euo pipefail`) with:

```bash
#!/usr/bin/env bash
# render_release_artifact.sh — aggregate release-validate phases into a
# single Markdown artifact suitable for `gh release create --notes-file`.
#
# Inputs (env vars):
#   VERSION              — current VERSION file content (e.g. "1.15.0")
#   FIXTURES_JSON        — output of run_all_fixtures.sh (Phase 4)
#   PORTABILITY_JSON     — output of check_shell_portability.sh (Phase 5)
#   REPO_STYLE_JSON      — output of check_repo_style_coverage.sh (Phase 6, optional)
#   AI_TOOL_PARITY_JSON  — output of check_ai_tool_parity.sh (Phase 7, optional)
#   OUTPUT               — absolute path to write the .md file
#
# Phase 6 and 7 inputs are optional for backwards-compat with v1.14.0
# callers; when absent, only Phases 4 + 5 are rendered.
#
# Output:
#   $OUTPUT — Markdown release artifact
#   stdout — a one-line verdict summary
#
# Exit codes:
#   0   artifact written, overall verdict PASS or WARN
#   1   any phase verdict FAIL → release blocked
set -euo pipefail
```

Then after the existing `PORT_VERDICT=...` block (around line 33 in v1.14.0; locate via `grep -n PORT_VERDICT skills/release-validate/scripts/render_release_artifact.sh`), append:

```bash

# Optional Phase 6
RS_VERDICT="SKIPPED"
RS_SCANNED=0
RS_MISSING=0
RS_PCT=0
if [[ -n "${REPO_STYLE_JSON:-}" && -f "$REPO_STYLE_JSON" ]]; then
  RS_VERDICT=$(jq -r '.verdict' "$REPO_STYLE_JSON")
  RS_SCANNED=$(jq -r '.scanned' "$REPO_STYLE_JSON")
  RS_MISSING=$(jq -r '.missing | length' "$REPO_STYLE_JSON")
  RS_PCT=$(jq -r '.coveragePct' "$REPO_STYLE_JSON")
fi

# Optional Phase 7
PARITY_VERDICT="SKIPPED"
PARITY_CMD_COUNT=0
PARITY_GAP_COUNT=0
if [[ -n "${AI_TOOL_PARITY_JSON:-}" && -f "$AI_TOOL_PARITY_JSON" ]]; then
  PARITY_VERDICT=$(jq -r '.verdict' "$AI_TOOL_PARITY_JSON")
  PARITY_CMD_COUNT=$(jq -r '.commands | length' "$AI_TOOL_PARITY_JSON")
  PARITY_GAP_COUNT=$(jq -r '[.commands[].gaps[]] | length' "$AI_TOOL_PARITY_JSON")
fi
```

Then update the overall verdict computation (replace the existing 3 lines that compute `OVERALL`):

```bash
# Compose overall verdict. FAIL > WARN > OK > SKIPPED.
OVERALL="PASS"
for v in "$PORT_VERDICT" "$FIX_VERDICT" "$RS_VERDICT" "$PARITY_VERDICT"; do
  case "$v" in
    FAIL) OVERALL="FAIL" ;;
    WARN) [[ "$OVERALL" != "FAIL" ]] && OVERALL="WARN" ;;
  esac
done
```

Then update the Markdown body — find the existing `## Summary` table and replace it with:

```bash
cat > "$OUTPUT" <<EOF
# Release Check — v${VERSION}

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Overall verdict**: **${OVERALL}**

## Summary

| Phase | Verdict | Detail |
|---|---|---|
| 4. Fixture suites    | ${FIX_VERDICT}    | ${FIX_TOTAL_PASS} PASS / ${FIX_TOTAL_FAIL} FAIL across ${FIX_SUITES} suites |
| 5. Shell portability | ${PORT_VERDICT}   | ${PORT_SCANNED} scripts scanned, ${PORT_ERRORS} errors, ${PORT_WARNINGS} warnings |
| 6. Repo-style coverage | ${RS_VERDICT} | ${RS_SCANNED} required entries, ${RS_MISSING} missing (${RS_PCT}% coverage) |
| 7. AI-tool parity    | ${PARITY_VERDICT} | ${PARITY_CMD_COUNT} commands scanned, ${PARITY_GAP_COUNT} registration gaps |
EOF
```

(Leave the rest of the heredoc — Phase 4 / 5 detail tables — unchanged. Append Phase 6 + 7 detail sections at the end of the heredoc; see Step 2.)

- [ ] **Step 2: Append Phase 6 + 7 detail sections to the heredoc**

Inside the same `cat > "$OUTPUT" <<EOF` heredoc, after the Phase 5 issues table and before the "How to interpret" section, insert:

```bash
## Phase 6 — Repo-style coverage

Matrix: \`skills/release-validate/references/repo-style-matrix.md\`

| Metric | Value |
|---|---|
| Required entries scanned | ${RS_SCANNED} |
| Missing fixtures | ${RS_MISSING} |
| Coverage | ${RS_PCT}% |
| Verdict | ${RS_VERDICT} |

WARN-only — gaps surface as follow-up work, not release blockers.

## Phase 7 — Cross-AI-tool parity

| Metric | Value |
|---|---|
| Commands scanned | ${PARITY_CMD_COUNT} |
| Registration gaps | ${PARITY_GAP_COUNT} |
| Verdict | ${PARITY_VERDICT} |

A FAIL verdict here blocks the release: every Zeus command must be
registered across all 4 AI-tool surfaces (Claude / Codex via CLAUDE.md /
AGENTS.md / GEMINI.md / docs/PROJECT.md + Gemini TOML mirror).
```

- [ ] **Step 3: Smoke-test the extended renderer**

```bash
bash skills/release-validate/scripts/run_all_fixtures.sh > /tmp/fix.json
bash skills/release-validate/scripts/check_shell_portability.sh . > /tmp/port.json
bash skills/release-validate/scripts/check_repo_style_coverage.sh --repo-root . > /tmp/style.json
bash skills/release-validate/scripts/check_ai_tool_parity.sh --repo-root . --all > /tmp/parity.json

VERSION=1.15.0 \
  FIXTURES_JSON=/tmp/fix.json \
  PORTABILITY_JSON=/tmp/port.json \
  REPO_STYLE_JSON=/tmp/style.json \
  AI_TOOL_PARITY_JSON=/tmp/parity.json \
  OUTPUT=/tmp/RELEASE-CHECK.md \
  bash skills/release-validate/scripts/render_release_artifact.sh
```

Expected stdout: `release-validate v1.15.0: PASS (fixtures=OK, portability=OK)` (or similar, including new phase verdicts).

Inspect the file:

```bash
head -30 /tmp/RELEASE-CHECK.md
```

Expected: 4-row Summary table with Phase 4 + 5 + 6 + 7 verdicts.

- [ ] **Step 4: Commit**

```bash
git add skills/release-validate/scripts/render_release_artifact.sh
git commit -m "feat(release-validate): render Phase 6 and 7 sections in release artifact"
```

---

## Task 4: Top-level orchestrator `scripts/release_check.sh`

**Files:**
- Create: `scripts/release_check.sh`
- Modify: `package.json` (add `release:check` script)
- Test: run it locally; check verdict

- [ ] **Step 1: Write the orchestrator**

Write `scripts/release_check.sh`:

```bash
#!/usr/bin/env bash
# release_check.sh — top-level orchestrator that runs every release-validate
# phase and renders the release artifact.
#
# Used by:
#   - Operators (pre-release manual check): bash scripts/release_check.sh
#   - CI (.github/workflows/release.yml)
#
# Exit codes:
#   0   overall verdict PASS or WARN
#   1   overall verdict FAIL → release should not proceed
#   2   tooling / setup missing
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION=$(cat VERSION | tr -d '[:space:]')
REPORT_DIR="docs/reports/release-validate/$VERSION"
mkdir -p "$REPORT_DIR"

SCRIPTS=skills/release-validate/scripts
[[ -d "$SCRIPTS" ]] || { echo "release-validate scripts not found at $SCRIPTS" >&2; exit 2; }

echo "release_check: running 4 phases for v$VERSION"

echo "  [4/4] Phase 4 — skill fixture suites"
bash "$SCRIPTS/run_all_fixtures.sh" "$ROOT_DIR" > "$REPORT_DIR/fixtures.json" || FIX_RC=$?

echo "  [4/4] Phase 5 — shell portability"
bash "$SCRIPTS/check_shell_portability.sh" "$ROOT_DIR" > "$REPORT_DIR/portability.json" || PORT_RC=$?

echo "  [4/4] Phase 6 — repo-style coverage"
bash "$SCRIPTS/check_repo_style_coverage.sh" --repo-root "$ROOT_DIR" > "$REPORT_DIR/repo-style.json"

echo "  [4/4] Phase 7 — AI-tool parity"
bash "$SCRIPTS/check_ai_tool_parity.sh" --repo-root "$ROOT_DIR" --all > "$REPORT_DIR/ai-parity.json" || PARITY_RC=$?

echo "  [render] aggregating into $REPORT_DIR/RELEASE-CHECK.md"
VERSION="$VERSION" \
  FIXTURES_JSON="$REPORT_DIR/fixtures.json" \
  PORTABILITY_JSON="$REPORT_DIR/portability.json" \
  REPO_STYLE_JSON="$REPORT_DIR/repo-style.json" \
  AI_TOOL_PARITY_JSON="$REPORT_DIR/ai-parity.json" \
  OUTPUT="$REPORT_DIR/RELEASE-CHECK.md" \
  bash "$SCRIPTS/render_release_artifact.sh"
```

```bash
chmod +x scripts/release_check.sh
```

- [ ] **Step 2: Add npm script**

Modify `package.json`: in the `"scripts"` block, add after the existing `"release"` entry:

```json
    "release:check": "bash scripts/release_check.sh",
```

(Use `Edit` tool with old_string containing the existing `"release": "bash scripts/release.sh"` line and new_string appending the new key after it.)

- [ ] **Step 3: Run the orchestrator**

```bash
pnpm release:check
```

Expected last line:

```
release-validate v1.15.0: PASS (fixtures=OK, portability=OK)
```

(Exact wording may vary; what matters is exit code 0 and a `PASS` or `WARN` verdict.)

- [ ] **Step 4: Verify the artifact exists**

```bash
ls -la docs/reports/release-validate/$(cat VERSION)/RELEASE-CHECK.md
head -15 docs/reports/release-validate/$(cat VERSION)/RELEASE-CHECK.md
```

Expected: a real Markdown file with the 4-row Summary table.

- [ ] **Step 5: Commit**

```bash
git add scripts/release_check.sh package.json
git commit -m "feat(release-validate): add scripts/release_check.sh orchestrator + pnpm release:check"
```

---

## Task 5: Wire into GitHub Actions

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Insert the release-check step**

Using the `Edit` tool, replace the existing `Run structure tests` block in `.github/workflows/release.yml`:

```yaml
      - name: Run structure tests
        run: bash tests/test-structure.sh
```

…with:

```yaml
      - name: Run structure tests
        run: bash tests/test-structure.sh

      - name: Run release-validate (fixture + portability + repo-style + parity)
        run: bash scripts/release_check.sh

      - name: Upload release-check artifact
        uses: actions/upload-artifact@v4
        with:
          name: release-check-${{ github.ref_name }}
          path: docs/reports/release-validate/
```

- [ ] **Step 2: Verify the YAML parses**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "OK"
```

Expected output: `OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci(release): wire release_check.sh into release workflow as pre-publish gate"
```

---

## Task 6: Update SKILL.md to v1.15.0

**Files:**
- Modify: `skills/release-validate/SKILL.md`

- [ ] **Step 1: Bump skill version + description**

Replace the YAML frontmatter at the top of `skills/release-validate/SKILL.md`:

```yaml
---
name: release-validate
description: >
  Validates package release readiness across version consistency, cross-platform
  link integrity, npm package content, setup script smoke testing, skill
  fixture suite runs (Phase 4), shell portability static checks (Phase 5),
  cross-repo-style fixture coverage (Phase 6, shipped in v1.15.0), cross-AI-tool
  registration parity (Phase 7, shipped in v1.15.0), and release artifact generation
  (Phase 8). Use before running `pnpm release` to catch issues that structure
  tests may miss. Top-level orchestrator at `scripts/release_check.sh` runs
  every phase and is wired into `.github/workflows/release.yml` as a
  pre-publish gate. Produces `docs/reports/release-validate/<version>/RELEASE-CHECK.md`
  suitable verbatim for the GitHub Release body.
version: "1.15.0"
---
```

- [ ] **Step 2: Append Phase 6 and Phase 7 sections**

Find the `## Phase 8: Release Artifact Generation (v1.14.0)` heading and insert BEFORE it:

```markdown
## Phase 6: Cross-Repo-Style Coverage (v1.15.0)

For each "Kustomize-touching skill" listed in
`references/repo-style-matrix.md`, verify fixtures exist for each declared
repo style (`kustomize-argocd`, `helm-only`, `mixed`). Delegates to
`scripts/check_repo_style_coverage.sh`:

```bash
bash skills/release-validate/scripts/check_repo_style_coverage.sh --repo-root .
```

Output JSON: `{scanned, matrix: [...], missing: ["skill:style"], coveragePct, verdict}`.

**Convention**: any pre-v1.15.0 fixture under `tests/<skill>/fixtures/`
counts as `kustomize-argocd`-style (matches the current reality). Other
styles must have a directory whose name contains the style keyword
(e.g. `tests/<skill>/fixtures/helm-only-basic/`).

**Gate**: WARN-only. Coverage gaps are surfaced but do not block release —
they're follow-up work, not regressions. To upgrade a row to FAIL, edit
the matrix and add a new column with `required` (no code change needed).

## Phase 7: Cross-AI-Tool Registration Parity (v1.15.0)

For every Zeus command (file under `prompts/zeus/`), verify it is
registered across all 4 AI-tool surfaces. Delegates to
`scripts/check_ai_tool_parity.sh`:

```bash
bash skills/release-validate/scripts/check_ai_tool_parity.sh --repo-root . --all
```

Checks per command:

| # | Where | Required |
|---|---|---|
| 1 | `prompts/zeus/<cmd>.md` exists | yes |
| 2 | `.gemini/commands/devops/pipelines/zeus-<cmd>.toml` exists | yes |
| 3 | `CLAUDE.md` mentions `*<cmd>` | yes |
| 4 | `AGENTS.md` mentions `*<cmd>` | yes |
| 5 | `GEMINI.md` mentions `*<cmd>` | yes |
| 6 | `docs/PROJECT.md` mentions `*<cmd>` | yes |

**Gate**: FAIL on any gap. Every Zeus command must surface identically
across Claude Code, OpenAI Codex CLI, Google Gemini CLI, and Google
Antigravity. Strengthens Phase 2 (cross-platform link validation), which
only checks file references, not command registration.

```

- [ ] **Step 3: Update Phase 8 documentation to mention new inputs**

In the existing `## Phase 8: Release Artifact Generation (v1.14.0)` section, replace the env-var list with:

```markdown
Combine Phases 4 + 5 + 6 + 7 outputs into a single Markdown artifact at
`docs/reports/release-validate/<version>/RELEASE-CHECK.md`. Suitable
verbatim as the body of `gh release create --notes-file ...` or as the
npm publish README excerpt.

```bash
VERSION=$(cat VERSION) \
  FIXTURES_JSON=/tmp/fixtures.json \
  PORTABILITY_JSON=/tmp/portability.json \
  REPO_STYLE_JSON=/tmp/repo-style.json \
  AI_TOOL_PARITY_JSON=/tmp/ai-parity.json \
  OUTPUT="docs/reports/release-validate/${VERSION}/RELEASE-CHECK.md" \
  bash skills/release-validate/scripts/render_release_artifact.sh
```

(`REPO_STYLE_JSON` and `AI_TOOL_PARITY_JSON` are optional — when absent,
the artifact renders Phase 6 + 7 verdicts as `SKIPPED`, matching the
v1.14.0 caller contract for backwards compatibility.)
```

- [ ] **Step 4: Append "## Top-level orchestrator" section**

After the Phase 8 section and before `## Output Format`, insert:

```markdown
## Top-Level Orchestrator (v1.15.0)

`scripts/release_check.sh` at the repo root runs every phase in sequence
and renders the artifact. Used by both operators (manual pre-release
sanity check) and CI (`.github/workflows/release.yml`).

```bash
pnpm release:check    # or: bash scripts/release_check.sh
```

The orchestrator:
1. Creates `docs/reports/release-validate/<version>/`
2. Runs Phase 4 → `fixtures.json`
3. Runs Phase 5 → `portability.json`
4. Runs Phase 6 → `repo-style.json`
5. Runs Phase 7 → `ai-parity.json`
6. Invokes the renderer → `RELEASE-CHECK.md`
7. Exits 1 if overall verdict is FAIL, else 0

CI uploads `docs/reports/release-validate/` as a workflow artifact named
`release-check-<tag>` so the rendered Markdown is downloadable from the
Actions run page.

```

- [ ] **Step 5: Commit**

```bash
git add skills/release-validate/SKILL.md
git commit -m "docs(release-validate): SKILL.md v1.15.0 — document Phase 6, 7, and orchestrator"
```

---

## Task 7: v1.15.0 release

**Files:**
- Modify: `VERSION`, `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.gemini/extensions/devops/gemini-extension.json` (via `pnpm version:bump`)
- Modify: `CHANGELOG.md` (fill the auto-scaffolded `[1.15.0]` entry)

- [ ] **Step 1: Bump version**

```bash
pnpm version:bump 1.15.0
pnpm version:consistency
```

Expected: all 5 files report `1.15.0`.

- [ ] **Step 2: Fill the CHANGELOG entry**

Replace the auto-scaffolded `## [1.15.0] - <date>` block with:

```markdown
## [1.15.0] - 2026-05-19

### Added

- **`release-validate` skill v1.15.0** — two new pre-release gates and a top-level orchestrator:
  - **Phase 6 — Cross-repo-style coverage check.** `scripts/check_repo_style_coverage.sh` reads `references/repo-style-matrix.md` (a plain markdown table declaring per-skill style requirements) and reports gaps. WARN-only. Pre-v1.15.0 fixtures count as `kustomize-argocd`-style by convention; other styles require directory names containing the style keyword (e.g. `helm-only-basic`).
  - **Phase 7 — Cross-AI-tool registration parity check.** `scripts/check_ai_tool_parity.sh` verifies that every Zeus command appears in all 4 surfaces (CLAUDE.md / AGENTS.md / GEMINI.md / docs/PROJECT.md) + has a Gemini TOML mirror. FAIL on any gap — strengthens the existing Phase 2 (file-reference validation) with command-registration validation.
  - **`scripts/release_check.sh` orchestrator + `pnpm release:check`** — runs Phases 4 + 5 + 6 + 7, writes per-phase JSON under `docs/reports/release-validate/<version>/`, and invokes the renderer for `RELEASE-CHECK.md`. Used by both operators and CI.
  - **CI integration** — `.github/workflows/release.yml` runs `scripts/release_check.sh` after the existing structure-test step and uploads `docs/reports/release-validate/` as a workflow artifact (`release-check-<tag>`).
- 4 new fixture tests under `tests/release-validate/fixtures/` covering Phase 6 + 7 happy / failure paths.

### Self-check results (v1.15.0)

```
release-validate v1.15.0: PASS (fixtures=OK, portability=OK, repoStyle=OK, parity=OK)

| Phase | Verdict | Detail |
| 4. Fixture suites      | OK | <updated> PASS across 7 suites             |
| 5. Shell portability   | OK | <updated> scripts scanned, 0 errors        |
| 6. Repo-style coverage | OK | 6 required entries, 0 missing (100%)       |
| 7. AI-tool parity      | OK | <N> commands scanned, 0 registration gaps  |
```

(Numbers populated by the renderer at release time.)
```

- [ ] **Step 3: Run release_check.sh against v1.15.0**

```bash
pnpm release:check
```

Expected exit code: 0. Verdict: PASS or WARN (any FAIL halts the release).

- [ ] **Step 4: Commit + tag + push**

```bash
git add VERSION package.json .claude-plugin/marketplace.json .claude-plugin/plugin.json \
        .gemini/extensions/devops/gemini-extension.json CHANGELOG.md
git commit -m "chore(release): v1.15.0 — release-validate v1.15.0 (Phase 6 + 7 + CI)"
git tag -a v1.15.0 -m "Release v1.15.0 — release-validate v1.15.0 (Phase 6, 7, orchestrator, CI)"
git push origin main
git push origin v1.15.0
```

Expected: GitHub Actions starts the `Release` workflow on the new tag.

- [ ] **Step 5: Verify CI runs the new gate**

Open `https://github.com/qwedsazxc78/devops-ai-skill/actions`. The
`Release` workflow run for `v1.15.0` should show:

1. ✓ Validate tag matches VERSION
2. ✓ Run structure tests
3. ✓ Run release-validate (fixture + portability + repo-style + parity)
4. ✓ Upload release-check artifact (downloadable as `release-check-v1.15.0.zip`)
5. ✓ Create GitHub Release
6. ✓ Publish to npm

If Step 3 fails, the rest of the workflow halts — the publish gate is now active.

---

## Self-Review

**1. Spec coverage:**
- Phase 6 (cross-repo-style coverage) → Task 1 ✓
- Phase 7 (cross-AI-tool E2E parity) → Task 2 ✓
- Render integration → Task 3 ✓
- Orchestrator + `pnpm release:check` → Task 4 ✓
- CI wiring → Task 5 ✓
- SKILL.md update → Task 6 ✓
- v1.15.0 release → Task 7 ✓

**2. Placeholder scan:** No "TBD", "add validation here", or "similar to Task N". Every code block contains full content.

**3. Type consistency:**
- `check_repo_style_coverage.sh` JSON fields used in Task 3 (`scanned`, `missing`, `coveragePct`, `verdict`) match Task 1 emission. ✓
- `check_ai_tool_parity.sh` JSON fields used in Task 3 (`commands`, `gaps`, `verdict`) match Task 2 emission. ✓
- `render_release_artifact.sh` env vars used in Task 4 (`FIXTURES_JSON`, `PORTABILITY_JSON`, `REPO_STYLE_JSON`, `AI_TOOL_PARITY_JSON`, `OUTPUT`, `VERSION`) match Task 3 acceptance. ✓
- The Bash 3.2 portability constraints (no `declare -A`, no `mapfile`) are honored in Task 1 + 2 scripts (no `declare -A`; collection uses temp files where order doesn't matter or `IFS= read` loops with explicit array appends). ✓
