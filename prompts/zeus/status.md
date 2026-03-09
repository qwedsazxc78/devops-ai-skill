# Tool Installation Check

Verify all required and optional tools are installed. Works standalone — no agent session needed.

## Tool Categories

### Required

| Tool | Version Command | Install (macOS) | Install (Linux/WSL2) |
|------|----------------|-----------------|---------------------|
| kustomize | `kustomize version` | `brew install kustomize` | `sudo snap install kustomize` |
| kubectl | `kubectl version --client` | `brew install kubectl` | `sudo snap install kubectl --classic` |
| git | `git --version` | `brew install git` | `sudo apt-get install -y git` |

### Recommended

| Tool | Version Command | Install (macOS) | Install (Linux/WSL2) |
|------|----------------|-----------------|---------------------|
| kubeconform | `kubeconform -v` | `brew install kubeconform` | `brew install kubeconform` |
| kube-score | `kube-score version` | `brew install kube-score` | `brew install kube-score` |
| kube-linter | `kube-linter version` | `brew install kube-linter` | `brew install kube-linter` |
| yamllint | `yamllint --version` | `uv tool install yamllint` | `uv tool install yamllint` |
| gitleaks | `gitleaks version` | `brew install gitleaks` | `brew install gitleaks` |

### Full Suite

| Tool | Version Command | Install (macOS) | Install (Linux/WSL2) |
|------|----------------|-----------------|---------------------|
| checkov | `checkov --version` | `uv tool install checkov` | `uv tool install checkov` |
| trivy | `trivy --version` | `brew install trivy` | `sudo snap install trivy` |
| polaris | `polaris version` | `brew install FairwindsOps/tap/polaris` | `brew install FairwindsOps/tap/polaris` |
| pluto | `pluto version` | `brew install FairwindsOps/tap/pluto` | `brew install FairwindsOps/tap/pluto` |
| conftest | `conftest --version` | `brew install conftest` | `brew install conftest` |
| d2 | `d2 --version` | `brew install d2` | `brew install d2` |
| pre-commit | `pre-commit --version` | `uv tool install pre-commit` | `uv tool install pre-commit` |

## Steps

1. Detect platform (`uname -s`, check `brew`/`apt-get`/`uv`/`pip3`)
2. Check each tool with `command -v <tool>`
3. Show status dashboard
4. Offer to install missing tools (grouped by package manager)
5. Verify after install

## Graceful Degradation

- Required tools missing → ERROR (blocks pipelines)
- Recommended tools missing → WARN (pipelines skip those checks)
- Never block — always show full status table
