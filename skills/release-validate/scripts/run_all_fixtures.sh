#!/usr/bin/env bash
# run_all_fixtures.sh — execute every tests/*/run-fixtures.sh and aggregate.
#
# Iterates every fixture runner under tests/, captures exit code + last
# "PASS: N FAIL: N" line, and emits structured JSON to stdout.
#
# Output (stdout, JSON):
#   {
#     "suites": [
#       {"name": "nginx-to-traefik", "pass": 4, "fail": 0, "exitCode": 0, "verdict": "OK"},
#       ...
#     ],
#     "totalPass": 18,
#     "totalFail": 0,
#     "totalSuites": 6,
#     "verdict": "OK" | "FAIL"
#   }
#
# Exit codes:
#   0   all suites pass
#   1   at least one suite failed
#   2   tooling missing
set -uo pipefail   # not -e — we want to capture failures, not abort

REPO_ROOT="${1:-.}"
cd "$REPO_ROOT"

command -v jq >/dev/null 2>&1 || { echo "jq not on PATH" >&2; exit 2; }

SUITES=()
TOTAL_PASS=0
TOTAL_FAIL=0
OVERALL_OK=true

for runner in tests/*/run-fixtures.sh; do
  [[ -f "$runner" ]] || continue
  suite_name=$(basename "$(dirname "$runner")")
  out=$(bash "$runner" 2>&1) || true
  rc=$?

  # Parse the last line that looks like "name: N passed, N failed" OR
  # "PASS: N  FAIL: N" OR "Total: N, Passed: N, Failed: N"
  pass_count=$(echo "$out" | grep -oE '([0-9]+) passed|PASS: ([0-9]+)|Passed: ([0-9]+)' | tail -1 | grep -oE '[0-9]+' | tail -1 || echo 0)
  fail_count=$(echo "$out" | grep -oE '([0-9]+) failed|FAIL: ([0-9]+)|Failed: ([0-9]+)' | tail -1 | grep -oE '[0-9]+' | tail -1 || echo 0)
  pass_count=${pass_count:-0}
  fail_count=${fail_count:-0}

  if [[ "$rc" -eq 0 && "$fail_count" -eq 0 ]]; then
    verdict="OK"
  else
    verdict="FAIL"
    OVERALL_OK=false
  fi

  TOTAL_PASS=$((TOTAL_PASS + pass_count))
  TOTAL_FAIL=$((TOTAL_FAIL + fail_count))

  SUITES+=("$(jq -n \
    --arg name "$suite_name" \
    --argjson pass "$pass_count" \
    --argjson fail "$fail_count" \
    --argjson rc "$rc" \
    --arg verdict "$verdict" \
    '{name: $name, pass: $pass, fail: $fail, exitCode: $rc, verdict: $verdict}')")
done

SUITE_COUNT=${#SUITES[@]}
OVERALL_VERDICT="OK"; [[ "$OVERALL_OK" == "false" ]] && OVERALL_VERDICT="FAIL"

if (( SUITE_COUNT == 0 )); then
  jq -n '{suites: [], totalPass: 0, totalFail: 0, totalSuites: 0, verdict: "NONE"}'
  exit 0
fi

printf '%s\n' "${SUITES[@]}" | jq -s \
  --argjson tp "$TOTAL_PASS" \
  --argjson tf "$TOTAL_FAIL" \
  --argjson tc "$SUITE_COUNT" \
  --arg verdict "$OVERALL_VERDICT" \
  '{suites: ., totalPass: $tp, totalFail: $tf, totalSuites: $tc, verdict: $verdict}'

[[ "$OVERALL_OK" == "true" ]] && exit 0 || exit 1
