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
  cmd_name=$(grep -E "^\| \*[a-zA-Z0-9_-]+[[:space:]]*\|[[:space:]]*\`prompts/zeus/$cmd\.md\`" \
    "$REPO_ROOT/CLAUDE.md" 2>/dev/null \
    | sed -E 's/^\| \*([a-zA-Z0-9_-]+).*/\1/' \
    | head -1)
  [[ -z "$cmd_name" ]] && cmd_name="$cmd"

  pipeline=$([[ -f "$REPO_ROOT/prompts/zeus/$cmd.md" ]] && echo true || echo false)
  tomlMirror=$([[ -f "$REPO_ROOT/.gemini/commands/devops/pipelines/zeus-$cmd_name.toml" ]] && echo true || echo false)
  claude=$(grep -q -E "\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/CLAUDE.md" 2>/dev/null && echo true || echo false)
  agents=$(grep -q -E "\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/AGENTS.md" 2>/dev/null && echo true || echo false)
  gemini=$(grep -q -E "\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/GEMINI.md" 2>/dev/null && echo true || echo false)
  project=$(grep -q -E "\*$cmd_name[^a-zA-Z0-9-]" "$REPO_ROOT/docs/PROJECT.md" 2>/dev/null && echo true || echo false)

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
