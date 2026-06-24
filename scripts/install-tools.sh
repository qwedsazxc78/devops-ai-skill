#!/usr/bin/env bash
# =============================================================================
# DevOps AI Skill Pack — Tool Installer
# =============================================================================
# Installs required and recommended tools for Horus (IaC) and Zeus (GitOps).
#
# Usage:
#   ./scripts/install-tools.sh              # Interactive: check + prompt install
#   ./scripts/install-tools.sh check        # Check tool availability only
#   ./scripts/install-tools.sh install       # Install all missing tools
#   ./scripts/install-tools.sh install zeus  # Install Zeus (GitOps) tools only
#   ./scripts/install-tools.sh install horus # Install Horus (IaC) tools only
# =============================================================================

set -uo pipefail

# --- Colors ----------------------------------------------------------------
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# --- Platform detection ----------------------------------------------------
detect_platform() {
  ARCH="$(uname -m)"
  PKG_MANAGER=""

  # Detect OS (including Windows environments)
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) OS="Windows" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        OS="WSL"  # treat as Linux with Windows fallback
      else
        OS="Linux"
      fi ;;
    Darwin) OS="Darwin" ;;
    *) OS="$(uname -s)" ;;
  esac

  # Detect package manager
  if command -v brew &>/dev/null; then
    PKG_MANAGER="brew"
  elif command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
  elif command -v winget &>/dev/null; then
    PKG_MANAGER="winget"
  elif command -v choco &>/dev/null; then
    PKG_MANAGER="choco"
  elif command -v scoop &>/dev/null; then
    PKG_MANAGER="scoop"
  fi

  # Python package installer: prefer uv > pip3 > pip
  if command -v uv &>/dev/null; then
    PIP="uv"
  elif command -v pip3 &>/dev/null; then
    PIP="pip3"
  elif command -v pip &>/dev/null; then
    PIP="pip"
  else
    PIP=""
  fi

  printf "${BLUE}Platform:${NC} %s (%s) | Package manager: %s | Python installer: %s\n\n" \
    "$OS" "$ARCH" "${PKG_MANAGER:-none}" "${PIP:-none}"
}

# --- Tool registry ---------------------------------------------------------
# Format: "binary_name|category|tier|brew_cmd|apt_cmd|pip_cmd|winget_cmd"
# category: shared, zeus, horus
# tier: required, recommended
TOOLS=(
  # Shared
  "node|shared|required|brew install node|apt-get install -y nodejs||winget install OpenJS.NodeJS.LTS"
  "git|shared|required|brew install git|apt-get install -y git||winget install Git.Git"
  "kubectl|shared|required|brew install kubectl|snap install kubectl --classic||winget install Kubernetes.kubectl"
  "jq|shared|required|brew install jq|apt-get install -y jq||winget install jqlang.jq"
  "yq|shared|recommended|brew install yq|snap install yq||winget install MikeFarah.yq"
  "python3|shared|recommended|brew install python3|apt-get install -y python3||winget install Python.Python.3.12"
  "curl|shared|recommended|brew install curl|apt-get install -y curl||winget install cURL.cURL"

  # Zeus (GitOps) — Required
  "kustomize|zeus|required|brew install kustomize|snap install kustomize||winget install Kubernetes.kustomize"

  # Zeus (GitOps) — Recommended
  "yamllint|zeus|recommended|||pip install yamllint|"
  "kubeconform|zeus|recommended|brew install kubeconform|||winget install YannHamon.kubeconform"
  # ingress2gateway — upstream Kubernetes SIG-Network tool.
  # Used by gateway-api-migration skill Step 4c (second opinion) AND
  # Step 4d validator (scripts/validate_generated.py check #11). Missing tool
  # → validator falls back to offline-only checks. Fallback install via `go`
  # is handled by get_install_cmd() below when no system package manager is
  # available. Source: https://github.com/kubernetes-sigs/ingress2gateway
  "ingress2gateway|zeus|recommended|brew install ingress2gateway|||winget install Kubernetes.ingress2gateway"
  "kube-score|zeus|recommended|brew install kube-score|||"
  "kube-linter|zeus|recommended|brew install kube-linter|||winget install stackrox.kube-linter"
  "polaris|zeus|recommended|brew install FairwindsOps/tap/polaris|||scoop install polaris"
  "pluto|zeus|recommended|brew install FairwindsOps/tap/pluto|||scoop install pluto"
  "conftest|zeus|recommended|brew install conftest|||"
  "checkov|zeus|recommended|||pip install checkov|"
  "trivy|zeus|recommended|brew install trivy|||winget install AquaSecurity.Trivy"
  "gitleaks|zeus|recommended|brew install gitleaks|||winget install Gitleaks.Gitleaks"
  "d2|zeus|recommended|brew install d2|||scoop install d2"

  # Horus (IaC) — Required
  "terraform|horus|required|brew install terraform|||winget install Hashicorp.Terraform"
  "helm|horus|required|brew install helm|snap install helm --classic||winget install Helm.Helm"

  # Horus (IaC) — Recommended
  "tflint|horus|recommended|brew install tflint|||winget install TerraformLinters.tflint"
  "tfsec|horus|recommended|brew install tfsec|||"
  "pre-commit|horus|recommended|||pip install pre-commit|"
)

# --- Helpers ---------------------------------------------------------------
total_ok=0
total_missing=0

check_tool() {
  local name="$1"
  local ver=""

  if command -v "$name" &>/dev/null; then
    ver=$("$name" --version 2>/dev/null | head -1 || "$name" version 2>/dev/null | head -1 || echo "installed")
    # Trim long version strings
    ver="${ver:0:40}"
    printf "  ${GREEN}[OK]${NC}  %-18s %s\n" "$name" "$ver"
    ((total_ok++))
    return 0
  else
    printf "  ${RED}[--]${NC}  %-18s ${YELLOW}not installed${NC}\n" "$name"
    ((total_missing++))
    return 1
  fi
}

# Known-good `go install` paths for tools that only ship via Homebrew or via
# `go install` upstream. Used as a fallback when the platform package manager
# has no entry for a tool (Linux without Homebrew, for example). Bash 3.2
# (default on macOS) has no associative arrays, so this is a plain function.
get_go_install_path() {
  case "$1" in
    ingress2gateway) echo "github.com/kubernetes-sigs/ingress2gateway@latest" ;;
    kube-score)      echo "github.com/zegl/kube-score/cmd/kube-score@latest" ;;
    kubeconform)     echo "github.com/yannh/kubeconform/cmd/kubeconform@latest" ;;
    conftest)        echo "github.com/open-policy-agent/conftest@latest" ;;
    tfsec)           echo "github.com/aquasecurity/tfsec/cmd/tfsec@latest" ;;
    *) echo "" ;;
  esac
}

get_install_cmd() {
  local entry="$1"
  IFS='|' read -r name category tier brew_cmd apt_cmd pip_cmd winget_cmd <<< "$entry"

  # Python tools first (cross-platform). Prefer an existing pip; otherwise emit
  # the uv command. We emit it even when neither uv nor pip is present — the
  # installer (ensure_installer) bootstraps uv before running it.
  # uv tool install → ~/.local/bin/ ; pip install --user → ~/.local/bin/
  if [[ -n "$pip_cmd" ]]; then
    local pkg="${pip_cmd##pip install }"
    if [[ "$PIP" == "pip3" || "$PIP" == "pip" ]]; then
      echo "$PIP install --user $pkg"
    else
      echo "uv tool install $pkg"
    fi
    return
  fi

  # Platform package manager
  case "$PKG_MANAGER" in
    brew)   [[ -n "$brew_cmd" ]]   && echo "$brew_cmd" && return ;;
    apt)    [[ -n "$apt_cmd" ]]    && echo "$apt_cmd" && return ;;
    winget) [[ -n "$winget_cmd" ]] && echo "$winget_cmd" && return ;;
    choco)
      echo "choco install ${name}" && return ;;
    scoop)
      echo "scoop install ${name}" && return ;;
  esac

  # `go install` fallback for Go-native tools without a platform package. The
  # Go toolchain is bootstrapped by ensure_installer() when absent, so emit the
  # command regardless of whether `go` is currently on PATH.
  local go_path
  go_path=$(get_go_install_path "$name")
  if [[ -n "$go_path" ]]; then
    echo "go install $go_path"
    return
  fi

  # No valid install command available — return empty
  echo ""
}

# Returns a human-readable hint when no install command is available
get_install_hint() {
  local entry="$1"
  IFS='|' read -r name category tier brew_cmd apt_cmd pip_cmd winget_cmd <<< "$entry"

  [[ -n "$brew_cmd" ]] && echo "$brew_cmd (needs Homebrew)" && return
  [[ -n "$winget_cmd" ]] && echo "$winget_cmd (needs winget)" && return
  [[ -n "$pip_cmd" ]] && echo "uv tool install ${pip_cmd##pip install } (needs uv or pip)" && return
  # Go-native tools: surface the upstream go install path
  local go_path
  go_path=$(get_go_install_path "$name")
  if [[ -n "$go_path" ]]; then
    echo "go install $go_path (needs Go toolchain)"
    return
  fi
  echo "see https://github.com/search?q=${name} for install instructions"
}

# Tracks installers we've already attempted to bootstrap this run (space-padded).
BOOTSTRAPPED=" "

# ensure_installer: bootstrap a missing installer/toolchain on demand so tools
# that depend on it (go install / uv / pip) become installable without the user
# pre-installing it. $1 is the leading token of an install command. Returns 0 if
# the installer is available afterwards, 1 otherwise. System package managers
# (brew/apt/winget) are assumed present and never bootstrapped here.
ensure_installer() {
  local mgr="$1"
  command -v "$mgr" &>/dev/null && return 0
  case "$BOOTSTRAPPED" in *" $mgr "*) command -v "$mgr" &>/dev/null; return $? ;; esac
  BOOTSTRAPPED="${BOOTSTRAPPED}${mgr} "

  printf "  ${BOLD}[bootstrap]${NC} %s not found — installing it ...\n" "$mgr"
  case "$mgr" in
    go)
      case "$PKG_MANAGER" in
        brew) brew install go &>/dev/null ;;
        apt)  sudo apt-get install -y golang-go &>/dev/null ;;
      esac
      # go-installed binaries land in $(go env GOPATH)/bin (default ~/go/bin)
      export PATH="${HOME}/go/bin:$PATH" ;;
    uv)
      curl -LsSf https://astral.sh/uv/install.sh | sh &>/dev/null
      export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:$PATH" ;;
    pip|pip3)
      { python3 -m ensurepip --upgrade || python -m ensurepip --upgrade; } &>/dev/null
      PIP="$mgr" ;;
    *) : ;;  # scoop/choco are Windows-only; nothing to bootstrap on this OS
  esac
  command -v "$mgr" &>/dev/null
}

# --- Commands ---------------------------------------------------------------

do_check() {
  local filter="${1:-all}"

  # Make per-user tool bin dirs visible so detection sees tools installed since
  # this shell opened (go install -> ~/go/bin, uv tool install -> ~/.local/bin).
  export PATH="${HOME}/go/bin:${HOME}/.local/bin:$PATH"

  printf "${BOLD}DevOps Plugin — Tool Status${NC}\n"
  printf "============================\n"

  local current_section=""
  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r name category tier _ _ _ _ <<< "$entry"

    # Filter by agent
    if [[ "$filter" != "all" && "$category" != "shared" && "$category" != "$filter" ]]; then
      continue
    fi

    local section="${category} (${tier})"
    if [[ "$section" != "$current_section" ]]; then
      current_section="$section"
      local label
      case "$category" in
        shared) label="Shared Tools" ;;
        zeus)   label="Zeus — GitOps" ;;
        horus)  label="Horus — IaC" ;;
      esac
      printf "\n${BOLD}%s (%s)${NC}\n" "$label" "$tier"
      printf "%.0s─" {1..45}; echo
    fi

    check_tool "$name" || {
      local cmd
      cmd=$(get_install_cmd "$entry")
      if [[ -z "$cmd" ]]; then
        cmd=$(get_install_hint "$entry")
      fi
      printf "         recommendation: ${YELLOW}%s${NC}\n" "$cmd"
    }
  done

  echo
  printf "Summary: ${GREEN}%d installed${NC}, ${RED}%d missing${NC}\n" "$total_ok" "$total_missing"

  if [[ $total_missing -gt 0 ]]; then
    echo
    printf "To install missing tools:\n"
    printf "  ${BOLD}./scripts/install-tools.sh install${NC}        # all\n"
    printf "  ${BOLD}./scripts/install-tools.sh install zeus${NC}   # GitOps only\n"
    printf "  ${BOLD}./scripts/install-tools.sh install horus${NC}  # IaC only\n"
  fi
}

do_install() {
  local filter="${1:-all}"

  printf "${BOLD}DevOps Plugin — Installing Tools${NC}\n"
  printf "=================================\n"

  # Pre-flight checks
  if [[ -z "$PKG_MANAGER" && -z "$PIP" ]]; then
    printf "${RED}No package manager found.${NC}\n"
    if [[ "$OS" == "Windows" ]]; then
      printf "Install winget: https://aka.ms/getwinget\n"
      printf "Or install Chocolatey: https://chocolatey.org/install\n"
      printf "Or install Scoop: https://scoop.sh\n"
    else
      printf "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n"
    fi
    printf "Or install uv: curl -LsSf https://astral.sh/uv/install.sh | sh\n"
    printf "Or install pip: python3 -m ensurepip --upgrade\n"
    exit 1
  fi

  if [[ -z "$PKG_MANAGER" ]]; then
    printf "${YELLOW}Warning: No system package manager (brew/apt/winget) found.${NC}\n"
    printf "Only Python-based tools (via uv/pip) will be installed.\n"
    if [[ "$OS" == "Windows" ]]; then
      printf "Install winget: https://aka.ms/getwinget\n\n"
    else
      printf "Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n\n"
    fi
  fi

  if [[ -z "$PIP" ]]; then
    printf "${YELLOW}Warning: No Python installer (uv/pip) found. Python-based tools will be skipped.${NC}\n"
    printf "Install uv (recommended): curl -LsSf https://astral.sh/uv/install.sh | sh\n"
    printf "Or install pip: python3 -m ensurepip --upgrade\n\n"
  fi

  local current_section=""
  local installed=0
  local skipped=0
  local failed=0

  for entry in "${TOOLS[@]}"; do
    IFS='|' read -r name category tier _ _ _ _ <<< "$entry"

    # Filter by agent
    if [[ "$filter" != "all" && "$category" != "shared" && "$category" != "$filter" ]]; then
      continue
    fi

    local section="${category} (${tier})"
    if [[ "$section" != "$current_section" ]]; then
      current_section="$section"
      local label
      case "$category" in
        shared) label="Shared Tools" ;;
        zeus)   label="Zeus — GitOps" ;;
        horus)  label="Horus — IaC" ;;
      esac
      printf "\n${BOLD}%s (%s)${NC}\n" "$label" "$tier"
    fi

    if command -v "$name" &>/dev/null; then
      printf "  ${GREEN}[OK]${NC}  %s (already installed)\n" "$name"
      ((skipped++))
      continue
    fi

    local cmd
    cmd=$(get_install_cmd "$entry")

    # No valid install command — show hint and skip
    if [[ -z "$cmd" ]]; then
      local hint
      hint=$(get_install_hint "$entry")
      printf "  ${YELLOW}[SKIP]${NC}  %s — no installer available\n" "$name"
      printf "          hint: %s\n" "$hint"
      ((failed++))
      continue
    fi

    # Bootstrap the installer this command needs (go/uv/pip) if it is missing.
    local mgr="${cmd%% *}"
    if ! ensure_installer "$mgr"; then
      printf "  ${YELLOW}[SKIP]${NC}  %s — could not bootstrap '%s'\n" "$name" "$mgr"
      printf "          hint: %s\n" "$(get_install_hint "$entry")"
      ((failed++))
      continue
    fi

    printf "  Installing ${BOLD}%s${NC} via: %s ... " "$name" "$cmd"

    local success=false
    for attempt in 1 2 3; do
      if eval "$cmd" &>/dev/null 2>&1; then
        success=true
        break
      fi
      if [[ $attempt -lt 3 ]]; then
        printf "retry %d/3 ... " "$((attempt + 1))"
        sleep 1
      fi
    done

    if $success; then
      printf "${GREEN}OK${NC}\n"
      ((installed++))
    else
      printf "${RED}FAILED${NC} (3 attempts)\n"
      ((failed++))
    fi
  done

  echo
  printf "Done: ${GREEN}%d installed${NC}, %d already present" "$installed" "$skipped"
  if [[ $failed -gt 0 ]]; then
    printf ", ${RED}%d failed${NC}" "$failed"
  fi
  echo
  echo
  if [[ $installed -gt 0 ]]; then
    printf "${YELLOW}Note:${NC} freshly installed tools (and any bootstrapped go/uv) may need a\n"
    printf "      new shell or 'source ~/.profile' to land on PATH. Open a new terminal,\n"
    printf "      then run ${BOLD}./scripts/install-tools.sh check${NC} to verify.\n"
  else
    printf "Run ${BOLD}./scripts/install-tools.sh check${NC} to verify.\n"
  fi
}

do_interactive() {
  do_check "${1:-all}"

  if [[ $total_missing -gt 0 ]]; then
    echo
    printf "Install missing tools now? [y/N] "
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      # Reset counters
      total_ok=0; total_missing=0
      do_install "${1:-all}"
    fi
  fi
}

do_help() {
  cat <<'EOF'

DevOps AI Skill Pack -- Tool Installer
======================================

Usage:
  ./scripts/install-tools.sh [command] [agent]

Commands:
  (none)     Interactive: check, then offer to install missing tools
  check      Show tool status only (never installs)
  install    Install all missing tools
  help       Show this help

Agent filter (optional 2nd arg):
  all        Shared + Zeus + Horus tools (default)
  zeus       Shared + Zeus (GitOps) tools
  horus      Shared + Horus (IaC) tools

Examples:
  ./scripts/install-tools.sh check
  ./scripts/install-tools.sh install zeus

Auto-bootstrap:
  Uses the platform package manager (brew/apt/winget). When a tool needs Go /
  uv / pip and it is missing, the installer bootstraps it automatically. On
  Windows, scoop/choco are bootstrapped too (per-user where possible). go/uv-
  installed tools land in ~/go/bin and ~/.local/bin -- make sure those are on
  PATH (open a new shell or 'source ~/.profile') after install.
EOF
}

# --- Main -------------------------------------------------------------------
detect_platform

case "${1:-}" in
  check)
    do_check "${2:-all}"
    ;;
  install)
    do_install "${2:-all}"
    ;;
  help|-h|--help)
    do_help
    ;;
  *)
    do_interactive "${1:-all}"
    ;;
esac
