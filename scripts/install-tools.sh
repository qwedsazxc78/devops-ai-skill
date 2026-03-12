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
  "kustomize|zeus|required|brew install kustomize|snap install kustomize||scoop install kustomize"

  # Zeus (GitOps) — Recommended
  "yamllint|zeus|recommended|||pip install yamllint|"
  "kubeconform|zeus|recommended|brew install kubeconform|||scoop install kubeconform"
  "kube-score|zeus|recommended|brew install kube-score|||"
  "kube-linter|zeus|recommended|brew install kube-linter|||"
  "polaris|zeus|recommended|brew install FairwindsOps/tap/polaris|||"
  "pluto|zeus|recommended|brew install FairwindsOps/tap/pluto|||"
  "conftest|zeus|recommended|brew install conftest|||"
  "checkov|zeus|recommended|||pip install checkov|"
  "trivy|zeus|recommended|brew install trivy|||choco install trivy"
  "gitleaks|zeus|recommended|brew install gitleaks|||choco install gitleaks"
  "d2|zeus|recommended|brew install d2|||scoop install d2"

  # Horus (IaC) — Required
  "terraform|horus|required|brew install terraform|||winget install Hashicorp.Terraform"
  "helm|horus|required|brew install helm|snap install helm --classic||winget install Helm.Helm"

  # Horus (IaC) — Recommended
  "tflint|horus|recommended|brew install tflint|||choco install tflint"
  "tfsec|horus|recommended|brew install tfsec|||choco install tfsec"
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

get_install_cmd() {
  local entry="$1"
  IFS='|' read -r name category tier brew_cmd apt_cmd pip_cmd winget_cmd <<< "$entry"

  # Python tools first (cross-platform): uv > pip3 > pip
  # uv tool install → ~/.local/bin/ (globally accessible)
  # pip install --user → ~/.local/bin/ (user-level, avoids sudo)
  if [[ -n "$pip_cmd" && -n "$PIP" ]]; then
    local pkg="${pip_cmd##pip install }"
    if [[ "$PIP" == "uv" ]]; then
      echo "uv tool install $pkg"
    else
      echo "$PIP install --user $pkg"
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
  echo "see https://github.com/search?q=${name} for install instructions"
}

# --- Commands ---------------------------------------------------------------

do_check() {
  local filter="${1:-all}"

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
  printf "Run ${BOLD}./scripts/install-tools.sh check${NC} to verify.\n"
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

# --- Main -------------------------------------------------------------------
detect_platform

case "${1:-}" in
  check)
    do_check "${2:-all}"
    ;;
  install)
    do_install "${2:-all}"
    ;;
  *)
    do_interactive "${1:-all}"
    ;;
esac
