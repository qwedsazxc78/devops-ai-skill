#!/usr/bin/env bash
# validate_cross_consistency.sh — 4-way cross-check for nginx-to-traefik.
#
# Statically parses the host arrays declared in:
#   1. <dns-script>            : HOSTS_<ENV>_<BATCH>=( "host" "host" ... )
#   2. <verify-script>         : URLS_<ENV>_<BATCH>=( "https://host/" ... )
#   3. <ingress-dir>/*-traefik-ingress.yaml  via yq
#   4. <app-ingress>           : .spec.tls[].hosts[]    via yq
#
# Reports any host appearing in fewer than all 4 sources. Exit non-zero on
# divergence. No `source`, no `eval` — the dns/verify scripts may be
# arbitrary operator-supplied bash and must be treated as untrusted text.
#
# Usage:
#   validate_cross_consistency.sh --env dev --batch b1 \
#     --dns-script SCRIPT --verify-script SCRIPT \
#     --ingress-dir DIR --app-ingress FILE

set -euo pipefail

ENV=""; BATCH=""; DNS_SCRIPT=""; VERIFY_SCRIPT=""
INGRESS_DIR=""; APP_INGRESS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV="$2"; shift 2 ;;
    --batch) BATCH="$2"; shift 2 ;;
    --dns-script) DNS_SCRIPT="$2"; shift 2 ;;
    --verify-script) VERIFY_SCRIPT="$2"; shift 2 ;;
    --ingress-dir) INGRESS_DIR="$2"; shift 2 ;;
    --app-ingress) APP_INGRESS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

env_upper="$(printf '%s' "$ENV" | tr '[:lower:]' '[:upper:]')"
batch_upper="$(printf '%s' "$BATCH" | tr '[:lower:]' '[:upper:]')"
hosts_var="HOSTS_${env_upper}_${batch_upper}"
urls_var="URLS_${env_upper}_${batch_upper}"

# Extract a bash array literal `NAME=( "a" "b" ... )` as one host per line.
# awk reads the file as plain text — no sourcing, no command execution.
extract_array() {
  local var="$1" file="$2"
  awk -v var="$var" '
    $0 ~ "^" var "=\\(" { inside=1; sub("^" var "=\\(", ""); }
    inside {
      gsub(/[()"\\\047]/, "", $0)
      n = split($0, toks, /[[:space:]]+/)
      for (i=1; i<=n; i++) if (toks[i] != "") print toks[i]
      if ($0 ~ /\)/) { exit }
    }
  ' "$file"
}

dns_hosts=()
while IFS= read -r line; do
  [[ -n "$line" ]] && dns_hosts+=("$line")
done < <(extract_array "$hosts_var" "$DNS_SCRIPT")

verify_raw=()
while IFS= read -r line; do
  [[ -n "$line" ]] && verify_raw+=("$line")
done < <(extract_array "$urls_var" "$VERIFY_SCRIPT")
verify_hosts=()
for u in "${verify_raw[@]}"; do
  h="${u#https://}"; h="${h#http://}"; h="${h%%/*}"
  [[ -n "$h" ]] && verify_hosts+=("$h")
done

ingress_hosts=()
shopt -s nullglob
for f in "$INGRESS_DIR"/*-traefik-ingress.yaml; do
  while IFS= read -r h; do
    [[ -n "$h" && "$h" != "null" ]] && ingress_hosts+=("$h")
  done < <(yq -r '.spec.rules[].host' "$f" 2>/dev/null || true)
done
shopt -u nullglob

cert_hosts=()
while IFS= read -r h; do
  [[ -n "$h" && "$h" != "null" ]] && cert_hosts+=("$h")
done < <(yq -r '.spec.tls[].hosts[]' "$APP_INGRESS" 2>/dev/null || true)

_in_list() {
  local h="$1"; shift
  printf '%s\n' "$@" | grep -qxF "$h"
}

all_hosts=$(printf '%s\n' "${dns_hosts[@]}" "${verify_hosts[@]}" "${ingress_hosts[@]}" "${cert_hosts[@]}" | sort -u)

bad=0
while IFS= read -r h; do
  [[ -z "$h" ]] && continue
  missing=""
  _in_list "$h" "${dns_hosts[@]+"${dns_hosts[@]}"}"     || missing+="dns "
  _in_list "$h" "${verify_hosts[@]+"${verify_hosts[@]}"}" || missing+="verify "
  _in_list "$h" "${ingress_hosts[@]+"${ingress_hosts[@]}"}" || missing+="ingress "
  _in_list "$h" "${cert_hosts[@]+"${cert_hosts[@]}"}"   || missing+="cert "
  if [[ -n "$missing" ]]; then
    echo "stale host: $h (missing from: $missing)" >&2
    bad=1
  fi
done <<< "$all_hosts"

exit "$bad"
