# Tool Installation Check

Standalone tool status checker — works without agent session or external scripts.

## Platform Detection

```bash
uname -s          # OS (Darwin / Linux)
command -v brew    # Homebrew?
command -v apt-get # apt?
command -v uv      # uv? (preferred over pip)
command -v pip3    # pip? (fallback)
```

## Shared Tools (required for both agents)

| Tool | Version Command | brew | apt/snap | uv/pip |
|------|----------------|------|----------|--------|
| git | `git --version` | `brew install git` | `sudo apt-get install -y git` | — |
| kubectl | `kubectl version --client` | `brew install kubectl` | `sudo snap install kubectl --classic` | — |
| jq | `jq --version` | `brew install jq` | `sudo apt-get install -y jq` | — |
| yq | `yq --version` | `brew install yq` | `sudo snap install yq` | — |

## Horus — IaC (required)

| Tool | Version Command | brew | apt/snap | uv/pip |
|------|----------------|------|----------|--------|
| terraform | `terraform version` | `brew install terraform` | `sudo snap install terraform --classic` | — |

## Horus — IaC (recommended)

| Tool | Version Command | brew | apt/snap | uv/pip |
|------|----------------|------|----------|--------|
| tflint | `tflint --version` | `brew install tflint` | `brew install tflint` | — |
| tfsec | `tfsec --version` | `brew install tfsec` | `brew install tfsec` | — |
| pre-commit | `pre-commit --version` | — | — | `uv tool install pre-commit` |

## Zeus — GitOps (required)

| Tool | Version Command | brew | apt/snap | uv/pip |
|------|----------------|------|----------|--------|
| kustomize | `kustomize version` | `brew install kustomize` | `sudo snap install kustomize` | — |

## Zeus — GitOps (recommended)

| Tool | Version Command | brew | apt/snap | uv/pip |
|------|----------------|------|----------|--------|
| yamllint | `yamllint --version` | — | — | `uv tool install yamllint` |
| kubeconform | `kubeconform -v` | `brew install kubeconform` | `brew install kubeconform` | — |
| kube-score | `kube-score version` | `brew install kube-score` | `brew install kube-score` | — |
| kube-linter | `kube-linter version` | `brew install kube-linter` | `brew install kube-linter` | — |
| polaris | `polaris version` | `brew install FairwindsOps/tap/polaris` | `brew install FairwindsOps/tap/polaris` | — |
| pluto | `pluto version` | `brew install FairwindsOps/tap/pluto` | `brew install FairwindsOps/tap/pluto` | — |
| conftest | `conftest --version` | `brew install conftest` | `brew install conftest` | — |
| checkov | `checkov --version` | — | — | `uv tool install checkov` |
| trivy | `trivy --version` | `brew install trivy` | `sudo snap install trivy` | — |
| gitleaks | `gitleaks version` | `brew install gitleaks` | `brew install gitleaks` | — |
| d2 | `d2 --version` | `brew install d2` | `brew install d2` | — |

## Output Format

```text
+-------------------------------------------------------------+
| DevOps Skill Pack — Tool Status                             |
+-------------------------------------------------------------+
| Tool Status:                                                |
|   OK:      kustomize kubectl git kube-score kube-linter     |
|   MISSING: yamllint checkov d2 kubeconform                  |
+-------------------------------------------------------------+
```

## Installation

- Group all brew installs into one command
- Group all uv/pip installs into one command
- Prefer `uv tool install` over `pip3 install`
- Required tools missing → ERROR
- Recommended tools missing → WARN
- Never block — always show full status
