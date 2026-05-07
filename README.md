# ⚡ DevOps AI Skill Pack

[![npm version](https://img.shields.io/npm/v/devops-ai-skill?style=flat-square&color=cb3837)](https://www.npmjs.com/package/devops-ai-skill)
[![GitHub Release](https://img.shields.io/github/v/release/qwedsazxc78/devops-ai-skill?style=flat-square&color=2ea44f)](https://github.com/qwedsazxc78/devops-ai-skill/releases)
[![DEVOPS](https://img.shields.io/badge/DEVOPS-SKILL-blue?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill)
[![LICENSE](https://img.shields.io/badge/LICENSE-MIT-green?style=flat-square)](https://github.com/qwedsazxc78/devops-ai-skill/blob/main/LICENSE)
[![FILES](https://img.shields.io/badge/FILES-65+-orange?style=flat-square)](#project-structure)
[![SKILLS](https://img.shields.io/badge/SKILLS-10-blueviolet?style=flat-square)](#skills)
[![PIPELINES](https://img.shields.io/badge/PIPELINES-15-ff6f61?style=flat-square)](#horus-pipelines-iac)
[![AGENTS](https://img.shields.io/badge/AGENTS-2-critical?style=flat-square)](#agents)
[![PLATFORMS](https://img.shields.io/badge/PLATFORMS-4-teal?style=flat-square)](#platform-support)

> Cross-platform DevOps AI Skill Pack — two AI-powered DevOps agents and shared pipeline workflows for **Claude Code**, **OpenAI Codex CLI**, **Google Gemini CLI**, and **Google Antigravity**.

🚀 [Quick Start](#quick-start) · 🤖 [Agents](#agents) · 🔧 [Tool Installation](#tool-installation) · 🛠️ [Skills](#skills) · 📖 [Setup Guide](docs/setup.md) · ⚡ [5-Min Guide](docs/quick-start.md) · 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)

English | [繁體中文](docs/README.zh-TW.md) | [简体中文](docs/README.zh-CN.md)

---

## Agents

| Agent | Focus | Platforms |
|-------|-------|-----------|
| **Horus** — IaC Operations Engineer | Terraform + Helm + GKE | All |
| **Zeus** — GitOps Engineer | Kustomize + ArgoCD | All |

## Quick Start

### Global Install (recommended)

Install once, available across ALL projects.

**macOS / Linux:**

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh          # Auto-detect installed CLIs
```

**Windows (one-click):**

```powershell
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
.\install.bat                            # Interactive menu: skills / tools / both
```

Or non-interactive on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1
```

All paths auto-detect Claude Code / Codex CLI / Gemini CLI / Antigravity and install to their global config paths. The Windows scripts target PowerShell 5.1 (built-in on Windows 10/11) — no Git Bash, no WSL, no extra dependencies.

![Global Install](docs/guide/01-install-global-run.png)

> 🆕 **New here?** Check out the [5-minute quick start guide](docs/quick-start.md) — zero prior knowledge required!

<details>
<summary><strong>Global Install Options</strong></summary>

**macOS / Linux:**

```bash
bash scripts/install-global.sh --all            # Force all platforms
bash scripts/install-global.sh --claude         # Claude Code only
bash scripts/install-global.sh --codex          # Codex CLI only
bash scripts/install-global.sh --gemini         # Gemini CLI only
bash scripts/install-global.sh --antigravity    # Antigravity only
bash scripts/install-global.sh --status         # Check install status
bash scripts/install-global.sh --uninstall      # Remove global installs
```

**Windows (PowerShell):**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -All
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Claude
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Codex
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Gemini
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Antigravity
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Status
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1 -Uninstall
```

Or use `install.bat` from the repo root for an interactive menu (skills / tools / both / status / uninstall).

</details>

<details>
<summary><strong>Updating Installed Skills</strong></summary>

```bash
cd devops-ai-skill
git pull origin main                          # Pull latest
bash scripts/install-global.sh                # Re-run (skips unchanged files)
```

> Re-run `install-global.sh` after updating source files to sync changes to all platforms.

</details>

<details>
<summary><strong>Per-repo Install (legacy)</strong></summary>

Run from your project root (macOS / Linux only — uses symlinks):

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
bash devops-ai-skill/scripts/setup.sh --all    # Install all platforms
bash devops-ai-skill/scripts/setup.sh          # Or interactive selection
```

```bash
bash devops-ai-skill/scripts/setup.sh --claude
bash devops-ai-skill/scripts/setup.sh --codex
bash devops-ai-skill/scripts/setup.sh --gemini
bash devops-ai-skill/scripts/setup.sh --antigravity
bash devops-ai-skill/scripts/setup.sh --uninstall
```

> **Windows users:** the per-repo flow relies on Unix symlinks (require Administrator or Developer Mode on Windows). Use **Global Install** (`install.bat`) instead — it gives you all four platforms with no admin rights required.

</details>

<details>
<summary><strong>Marketplace (Claude Code only)</strong></summary>

```bash
/plugin marketplace add qwedsazxc78/devops-ai-skill
/plugin install devops@devops-ai-skill
```

</details>

<details>
<summary><strong>Cross-Platform (npx skills) — Skills only</strong></summary>

```bash
# Auto-detects installed AI agents and routes skills accordingly
npx skills add qwedsazxc78/devops-ai-skill

# Update
npx skills update
```

> **⚠️ Note: This method installs only the 9 Skills (SKILL.md), not the full pack:**
>
> | Feature | npx skills | Global Install |
> |---------|:----------:|:--------------:|
> | 9 Skills (SKILL.md) | ✅ | ✅ |
> | 2 Agents (Horus / Zeus) | ❌ | ✅ |
> | 14 Pipelines (`*full`, `*security`, etc.) | ❌ | ✅ |
> | Command palette (Gemini CLI) | ❌ | ✅ |
> | Workflows (Antigravity) | ❌ | ✅ |
>
> For the full experience, use **Global Install** or **Marketplace** above.

</details>

## Platform Support

| Feature | Claude Code | OpenAI Codex | Gemini CLI | Antigravity |
|---------|-------------|--------------|------------|-------------|
| Global Agents | `~/.claude/agents/` | `~/.codex/instructions.md` | `~/.gemini/agents/` | `~/.agents/skills/` |
| Global Skills | `~/.claude/skills/` | `~/.codex/skills/` | `~/.gemini/skills/` | shared `~/.gemini/skills/` |
| Command palette | — | — | `~/.gemini/commands/devops/` | — |
| Workflows | — | — | — | `~/.agents/workflows/` |
| Entry file | `CLAUDE.md` | `AGENTS.md` | `GEMINI.md` | `.agents/rules/` |
| Skills format | SKILL.md (native) | SKILL.md (native) | SKILL.md (native) | SKILL.md (native) |
| Pipeline trigger | `*cmd` | `*cmd` | command palette `devops:` | `/workflow-name` |
| Bash execution | Yes | Yes (`!cmd`) | Yes (`run_shell_command`) | Yes |

## Tool Installation

One-command installer supporting macOS (Homebrew), Linux (apt/snap), Windows (winget/choco/scoop), and Python (uv/pip).

**macOS / Linux:**

```bash
# Interactive: check + prompt install
./scripts/install-tools.sh

# Check tool status only
./scripts/install-tools.sh check

# Install all missing tools
./scripts/install-tools.sh install

# Install tools for a specific agent
./scripts/install-tools.sh install horus   # IaC tools
./scripts/install-tools.sh install zeus    # GitOps tools
```

**Windows (PowerShell, native — no Git Bash / WSL needed):**

```powershell
# Interactive: check + prompt install
.\scripts\install-tools.ps1

# Check tool status only
.\scripts\install-tools.ps1 check

# Install all missing tools
.\scripts\install-tools.ps1 install

# Install tools for a specific agent
.\scripts\install-tools.ps1 install horus
.\scripts\install-tools.ps1 install zeus
```

Or double-click `install.bat` from the repo root and choose `[2] Tools`. Requires `winget` (built into Windows 10 1809+ / Windows 11) or `choco` / `scoop`.

### Shared Tools

| Tool | Tier | macOS (brew) | Linux (apt/snap) | Windows (winget) | Purpose |
|------|------|-------------|-------------------|------------------|---------|
| node | Required | `brew install node` | `apt-get install nodejs` | `winget install OpenJS.NodeJS.LTS` | postinstall runtime |
| git | Required | `brew install git` | `apt-get install git` | `winget install Git.Git` | Version control |
| kubectl | Required | `brew install kubectl` | `snap install kubectl` | `winget install Kubernetes.kubectl` | K8s CLI |
| jq | Required | `brew install jq` | `apt-get install jq` | `winget install jqlang.jq` | JSON processor |
| yq | Recommended | `brew install yq` | `snap install yq` | `winget install MikeFarah.yq` | YAML processor |
| python3 | Recommended | `brew install python3` | `apt-get install python3` | `winget install Python.Python.3.12` | Version check scripts |
| curl | Recommended | `brew install curl` | `apt-get install curl` | `winget install cURL.cURL` | Remote version check |

### Horus Tools (IaC)

| Tool | Tier | macOS (brew) | Windows (winget/choco) | pip | Purpose |
|------|------|-------------|------------------------|-----|---------|
| terraform | Required | `brew install terraform` | `winget install Hashicorp.Terraform` | — | IaC engine |
| helm | Required | `brew install helm` | `winget install Helm.Helm` | — | Helm chart management |
| tflint | Recommended | `brew install tflint` | `choco install tflint` | — | Terraform linter |
| tfsec | Recommended | `brew install tfsec` | `choco install tfsec` | — | Terraform security scanner |
| pre-commit | Recommended | — | — | `pip install pre-commit` | Git hook manager |

### Zeus Tools (GitOps)

| Tool | Tier | macOS (brew) | Windows (choco/scoop) | pip | Purpose |
|------|------|-------------|------------------------|-----|---------|
| kustomize | Required | `brew install kustomize` | `scoop install kustomize` | — | Kustomize build |
| yamllint | Recommended | — | — | `pip install yamllint` | YAML linter |
| kubeconform | Recommended | `brew install kubeconform` | `scoop install kubeconform` | — | K8s resource validation |
| kube-score | Recommended | `brew install kube-score` | — | — | K8s best practices |
| kube-linter | Recommended | `brew install kube-linter` | — | — | K8s linter |
| polaris | Recommended | `brew install FairwindsOps/tap/polaris` | — | — | K8s policy check |
| pluto | Recommended | `brew install FairwindsOps/tap/pluto` | — | — | Deprecated API detection |
| conftest | Recommended | `brew install conftest` | — | — | Policy testing |
| checkov | Recommended | — | — | `pip install checkov` | IaC security scanner |
| trivy | Recommended | `brew install trivy` | `choco install trivy` | — | Vulnerability scanner |
| gitleaks | Recommended | `brew install gitleaks` | `choco install gitleaks` | — | Secret detection |
| d2 | Recommended | `brew install d2` | `scoop install d2` | — | Architecture diagrams |

## Horus Pipelines (IaC)

| Pipeline | Description |
|----------|-------------|
| `*help` | Show available pipelines |
| `*full` | Full check (RUNS CLI tools) + report |
| `*upgrade` | Upgrade Helm chart versions |
| `*security` | Security audit (file analysis) |
| `*validate` | Validation (fmt + file analysis) |
| `*scaffold` | Scaffold new Helm module |
| `*cicd` | Improve CI/CD pipeline |
| `*health` | Platform health check |

## Zeus Pipelines (GitOps)

| Pipeline | Description |
|----------|-------------|
| `*help` | Show available pipelines |
| `*full` | Full pipeline + YAML/MD reports |
| `*pre-merge` | Pre-MR essential checks |
| `*health` | Repository health assessment |
| `*review` | MR review pipeline |
| `*scaffold` | Service scaffold (interactive) |
| `*diagram` | Generate architecture diagrams |
| `*status` | Tool installation check |
| `*gateway-migrate` | NGINX Ingress → Gateway API migration (default Traefik, opt-in GKE via `--gateway-class gke-l7-*`; master/minion or standalone) |

## Skills

All skills follow the [Open Agent Skills](https://agentskills.io/specification) standard (SKILL.md with YAML frontmatter):

| Skill | Used By | Purpose |
|-------|---------|---------|
| terraform-validate | Horus | Validation and linting |
| terraform-security | Horus | Security scanning |
| helm-version-upgrade | Horus | Helm chart version management |
| helm-scaffold | Horus | New module generation |
| cicd-enhancer | Horus | CI/CD pipeline improvement |
| kustomize-resource-validation | Zeus | Kustomize build + validation |
| yaml-fix-suggestions | Zeus | YAML formatting |
| gateway-api-migration | Zeus | NGINX Ingress → Gateway API migration with state tracking. Dual-target since v1.2.0: default Traefik, opt-in GKE Gateway. |
| repo-detect | Both | Repository type detection |
| release-validate | Shared | Release readiness validation |

## Hooks

Auto-loaded by Claude Code v2.1+ — wires existing skills + agents into Claude's tool-use loop for deterministic, event-driven feedback. See [`hooks/README.md`](hooks/README.md) for full details.

| # | Event | Purpose | Mode |
|---|---|---|---|
| H1 | `SessionStart` | Detect IaC/GitOps repo and suggest agent (Horus or Zeus) | advisory |
| H2 | `PostToolUse` Edit/Write | YAML lint after edits in Kustomize trees | advisory |
| H3 | `PostToolUse` Edit/Write | `terraform fmt` + `tflint` after `.tf` edits | advisory |
| H4 | `PreToolUse` Bash | Ask before `terraform apply`, `kubectl delete`, etc. | gate (`ask`) |

**Companion repos** (workshop demo branches: `demo-conditioned/2026-ithome-devopsday`):

- IaC template (Horus): <https://github.com/qwedsazxc78/iac-template-ai-skill>
- GitOps template (Zeus): <https://github.com/qwedsazxc78/gitops-template-ai-skill>
- Skill pack (this repo): <https://github.com/qwedsazxc78/devops-ai-skill>

## Example: NGINX → Gateway API Migration

The `*gateway-migrate` pipeline migrates an NGINX Ingress GitOps repo to Gateway API resources. **Dual-target since v1.2.0**: the default GatewayClass is `traefik` (Traefik v3.1+), and `--gateway-class gke-l7-global-external-managed` opts into GKE Gateway. Both targets share the same pipeline; the skill emits provider-specific CRDs (Traefik `Middleware` / `ServersTransport`, or GKE `GCPBackendPolicy` / `HealthCheckPolicy`) only when the target family is one it knows. It handles the common **master/minion** topology where:

- `common.ingress/` declares hosts + TLS (the "master")
- `common.service/overlays/<env>/<svc>-nginx-ingress.yaml` declares paths + backends per service (the "minions")

This pattern maps cleanly onto Gateway API's persona model: the master becomes a `Gateway` resource, each minion becomes an `HTTPRoute`.

### Prerequisites

Before running `*gateway-migrate`, ensure:

**On the GKE cluster**
- Gateway API CRDs installed (the skill checks but does not install them):
  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
  ```
- GKE Gateway controller add-on enabled (applies to Standard or Autopilot):
  ```bash
  gcloud container clusters update <CLUSTER> --region <REGION> --gateway-api=standard
  ```

**On your workstation** (the machine running Zeus)
- `kustomize` — required. `brew install kustomize`
- `yq` — required (used for idempotent in-place kustomization.yaml edits). `brew install yq`
- `kubeconform` — optional, for schema validation. `brew install kubeconform`
- `ingress2gateway` — optional, for cross-check validation. `brew install ingress2gateway`
- `devops-ai-skill` installed via [one-click install](#global-install-recommended) or per-repo `setup.sh`

**In the target GitOps repo**
- Kustomize `base/` + `overlays/{dev,stg,prd}/` layout (standard pattern)
- At least one `kind: Ingress` manifest with `apiVersion: networking.k8s.io/v1`
- For master/minion topology: master declares hosts only (no `http.paths`), minions have paths + backends in separate Kustomize modules

### Workflow

```bash
# 1. cd into your GitOps repo
cd /path/to/your-gitops-repo
claude    # or gemini / codex / antigravity

# 2. Run the pipeline (interactive)
> *gateway-migrate

# Zeus will:
#   - Detect master/minion or standalone topology
#   - Show annotation classification (portable / convertible / manual review)
#   - Ask for confirmation before generating any files
#   - Create a new `common.gateway/` Kustomize module (Gateway resource)
#   - Add HTTPRoutes alongside existing minions in `common.service/overlays/`
#   - Run `kustomize build` validation
#   - Write a state YAML + markdown report under `docs/reports/gateway-migration/`
#   - Print a per-hostname DNS cutover runbook

# 3. Review the generated module
ls common.gateway/
cat docs/reports/gateway-migration/<module>/report.md

# 4. Stage and commit
git add common.gateway/ common.service/overlays/ docs/reports/gateway-migration/
git commit
```

### Session walkthrough

When you run `*gateway-migrate` inside a Zeus session, expect output like this:

```
Zeus › *gateway-migrate

Step 0 · Tool check
  ✓ kustomize v5.4.2
  ✓ yq v4.44.1
  ✓ kubeconform v0.6.7
  ✓ ingress2gateway v0.3.0

Step 1 · Discovery

Discovered migration unit: master/minion topology
  Master:  common.ingress/                 (4 files, 14 hostnames declared)
  Minions: common.service/overlays/        (11 services × 3 envs = 33 files)
    ✓ argocd      → dev/stg/prd-argocd.awoo.org     → argocd-server:80
    ✓ grafana     → dev/stg/prd-grafana.awoo.org    → grafana:80
    ✓ airflow     → dev/stg/prd-airflow.awoo.org    → airflow-webserver:8080
    ... (11 services total)
  Orphan hosts:   2  (dev-alertmanager, dev-n8n — declared in master, no minion)
  Orphan minions: 0

Proceed with end-to-end master + minion migration? [y/N] y

Step 2 · Annotation analysis
  portable:              3
  portable-GKE:          4  (ManagedCertificate refs)
  convertible:           4  (→ GCPBackendPolicy resources)
  split-category (auto): 3  (X-* headers → responseHeaderModifier filter)
  split-category (stub): 2  (Set-Cookie rewrites, path denylists)
  drop-info:             1  (mergeable-ingress-type)

Proceed with conversion? [y/N] y

Step 3 · Convert
  Phase 3A: generating common.gateway/...
    ✓ common.gateway/base/kustomization.yaml
    ✓ common.gateway/base/gateway.yaml              (14 listeners)
    ✓ common.gateway/overlays/{dev,stg,prd}/...
    ✓ common.gateway/argocd/{dev,stg,prd}.yaml
    ✓ common.gateway/MIGRATION.md
  Phase 3B: HTTPRoutes + kustomization.yaml edits
    ✓ common.service/overlays/dev/argocd-httproute.yaml
    ✓ common.service/overlays/dev/kustomization.yaml (in-place, idempotent)
    ... (33 HTTPRoutes across 3 envs)

Step 4 · Validate
  ✓ kustomize build common.gateway/overlays/dev
  ✓ kustomize build common.gateway/overlays/stg
  ✓ kustomize build common.gateway/overlays/prd
  ✓ kustomize build common.service/overlays/dev
  ✓ kustomize build common.service/overlays/stg
  ✓ kustomize build common.service/overlays/prd
  ✓ kubeconform: 0 errors
  ✓ ingress2gateway second-opinion: 2 divergences (GKE-specific extensions)

Step 5 · Render report
  ✓ docs/reports/gateway-migration/common-ingress/state.yaml
  ✓ docs/reports/gateway-migration/common-ingress/report.md

Step 6 · Runbook
  See common.gateway/MIGRATION.md for per-hostname DNS cutover steps.

Step 7 · Pre-commit hints
  Suggested commit message ready. Files to stage listed below.
```

### Invocation forms

| Form | What it does |
|------|--------------|
| `*gateway-migrate` | Interactive discovery — Zeus finds Ingress modules and asks which to migrate |
| `*gateway-migrate <module-path>` | Skip discovery, target a known module directly |
| `*gateway-migrate <module-path> --resume` | Resume from a previously failed run via the state YAML |
| `*gateway-migrate <module-path> --force` | Bypass the never-clobber check on the target module |

### What gets generated

- **`common.gateway/`** — new Kustomize module with the Gateway resource, per-env overlays, ArgoCD `Application` manifests
- **`common.service/overlays/<env>/<svc>-httproute.yaml`** — one HTTPRoute per minion, side-by-side with existing minion files
- **`common.service/overlays/<env>/kustomization.yaml`** — idempotent in-place edit registering the new HTTPRoute resources
- **`docs/reports/gateway-migration/<module>/state.yaml`** — resumable migration state (audit trail)
- **`docs/reports/gateway-migration/<module>/report.md`** — human report with cutover runbook + manual-review TODO list

### Before / After — concrete YAML example

**Input — master Ingress (`common.ingress/overlays/prd/app.ingress.yaml`):**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-nginx
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress/mergeable-ingress-type: master
    networking.gke.io/managed-certificates: prd-argocd-ingress-nginx-crt
    nginx.ingress.kubernetes.io/server-snippet: |
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-Frame-Options "SAMEORIGIN" always;
spec:
  rules:
    - host: argocd.awoo.org    # host-only, no paths (this is the "master" pattern)
  tls:
    - hosts: [argocd.awoo.org]
      secretName: prd-argocd-ingress-nginx-crt
```

**Input — minion Ingress (`common.service/overlays/prd/argocd-nginx-ingress.yaml`):**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-nginx-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: argocd.awoo.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port: { number: 80 }
```

**Output — generated Gateway (`common.gateway/base/gateway.yaml`):**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: common-gateway
  namespace: ingress-nginx
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: argocd-https
      port: 443
      protocol: HTTPS
      hostname: argocd.awoo.org
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: ingress-nginx
      tls:
        mode: Terminate
        certificateRefs:
          - group: networking.gke.io
            kind: ManagedCertificate
            name: prd-argocd-ingress-nginx-crt
```

**Output — generated HTTPRoute (`common.service/overlays/prd/argocd-httproute.yaml`):**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-server
  namespace: argocd
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: common-gateway
      namespace: ingress-nginx
      sectionName: argocd-https
  hostnames:
    - argocd.awoo.org
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      filters:
        - type: ResponseHeaderModifier
          responseHeaderModifier:
            add:
              - name: X-Content-Type-Options
                value: nosniff
              - name: X-Frame-Options
                value: SAMEORIGIN
      backendRefs:
        - name: argocd-server
          port: 80
```

**Notes on the transformation:**

- `mergeable-ingress-type: master` **dropped** — HTTPRoute attachment via `parentRef` is the native Gateway API equivalent
- `networking.gke.io/managed-certificates` **preserved** — the same `ManagedCertificate` resource is referenced from the listener's `certificateRefs`
- `server-snippet` X-* headers **auto-converted** to a `responseHeaderModifier` filter (loss-free)
- Any `add_header Set-Cookie "..."` or `location ~ ... { return 404; }` blocks in the snippet would be **stubbed** with `# TODO(gateway-migrate):` comments pointing at `docs/reports/gateway-migration/<module>/report.md` for manual review (Cloud Armor territory)
- Cross-namespace routing (`ingress-nginx` Gateway → `argocd` namespace HTTPRoute) is enabled via `allowedRoutes.namespaces.from: Selector` with the `gateway-access: ingress-nginx` label — **you must label target namespaces before the HTTPRoutes attach** (see "Post-migration steps" below)

### Cutover strategy

The skill never modifies the master Ingress and never overwrites minion Ingress files — both stacks coexist. The runbook walks through a **per-hostname DNS cutover**: deploy the new Gateway, deploy HTTPRoutes alongside minions, then flip DNS one hostname at a time. Rollback is a DNS flip back; old stack remains live throughout.

### Post-migration steps

After `*gateway-migrate` exits successfully, the generated files are on disk but **nothing has been deployed yet**. Here's the operational sequence:

**1. Label target namespaces** (required for cross-namespace routing to work)

```bash
# List all namespaces the HTTPRoutes live in (derived from your minions)
kubectl label namespace argocd monitoring airflow --overwrite \
  gateway-access=ingress-nginx
```

The exact namespace list appears in `common.gateway/MIGRATION.md`'s "Pre-cutover setup" section with the correct `kubectl` command pre-filled.

**2. Review the generated report**

```bash
less docs/reports/gateway-migration/<module>/report.md
```

Pay attention to the **Manual Review Required** section — any `TODO(gateway-migrate)` stubs need to be addressed before traffic-flipping (typically Cloud Armor policies for `server-snippet` path denylists).

**3. Commit the generated changes**

The skill's Step 7 prints a suggested commit message. Or:

```bash
git add common.gateway/ \
        common.service/overlays/ \
        docs/reports/gateway-migration/
git commit -m "feat(ingress): migrate common.ingress to Gateway API"
git push
```

**4. Deploy the Gateway first** (Phase 1 of the runbook)

Sync the `common.gateway/` ArgoCD Application for the target environment. The Gateway resource will acquire an external IP:

```bash
kubectl get gateway common-gateway -n ingress-nginx -o wide
# NAME             CLASS                             ADDRESS          READY
# common-gateway   gke-l7-global-external-managed    34.120.XX.XX     True
```

Nothing points at this IP yet — safe to deploy without traffic impact.

**5. Deploy the HTTPRoutes** (Phase 2)

Sync the `common.service/` ArgoCD Application. HTTPRoutes attach to the Gateway listeners. Both stacks now serve the same hostnames: old stack via DNS, new stack via the new Gateway IP only.

```bash
kubectl get httproute -A
kubectl describe httproute argocd-server -n argocd
# Look for: `Parents: ... Conditions: Accepted=True, ResolvedRefs=True`
```

If you see `Accepted=False` with a reason like `NotAllowedByListeners`, the target namespace is missing the `gateway-access=ingress-nginx` label (see step 1).

**6. Per-hostname DNS cutover** (Phase 3, gradual)

For each hostname, one at a time:

```bash
# Smoke-test the new path via curl before touching DNS
curl --resolve argocd.awoo.org:443:<new-gateway-ip> https://argocd.awoo.org

# If healthy, update the DNS A/AAAA record to point at the new Gateway IP
# Wait for TTL + 15 minutes of monitoring (error rates, latency, cert serving)

# If unhealthy, DNS-revert to the old ingress-nginx LB — old stack is still live
```

**7. Clean up** (Phase 4, after 1+ week stable)

Delete the old `common.ingress/` module and remove the minion `*-nginx-ingress.yaml` files from `common.service/overlays/`. Update `common.service/overlays/<env>/kustomization.yaml` to drop those entries. Commit.

### Reference docs

- [`docs/gateway/annotation-map.md`](docs/gateway/annotation-map.md) — Canonical 13-row Ingress → Gateway API translation table
- [`docs/gateway/master-minion-topology.md`](docs/gateway/master-minion-topology.md) — Detection rules and pairing algorithm
- [`docs/gateway/gke-gateway-notes.md`](docs/gateway/gke-gateway-notes.md) — GKE GatewayClasses, GCPBackendPolicy, ManagedCertificate
- [`docs/gateway/http-routing-guide.md`](docs/gateway/http-routing-guide.md) — HTTPRoute reference
- [`docs/gateway/migrate-from-ingress.md`](docs/gateway/migrate-from-ingress.md) — Concepts and worked example
- [`docs/gateway/ingress2gateway-integration.md`](docs/gateway/ingress2gateway-integration.md) — Optional second-opinion tool
- [`docs/gateway/ingress-nginx-welcome.md`](docs/gateway/ingress-nginx-welcome.md) — Migration welcome page

### Optional second opinion

Install the upstream [`kubernetes-sigs/ingress2gateway`](https://github.com/kubernetes-sigs/ingress2gateway) tool and the skill will run it as a cross-check during validation, surfacing any divergence between its output and the skill's output in the report:

```bash
brew install ingress2gateway
```

Without it, the skill still works fine — the second-opinion check is just skipped (graceful degradation).

### Troubleshooting

**`kustomize build` fails after in-place edit**
- The skill automatically restores `common.service/overlays/<env>/kustomization.yaml` from the pre-edit SHA256 snapshot and halts. Read the error output, fix the underlying issue (usually a stale resource ref), then re-run with `--resume`.

**HTTPRoute shows `Accepted=False` after deploy**
- Check the condition's `Reason` and `Message`:
  - `NotAllowedByListeners` → target namespace missing the `gateway-access=ingress-nginx` label. Run `kubectl label namespace <ns> gateway-access=ingress-nginx`.
  - `InvalidKind` → verify the Gateway's listener `allowedRoutes.kinds` accepts HTTPRoute (default does).
  - `HostnameNotMatching` → the HTTPRoute's `hostnames[]` doesn't match any listener's `hostname`. Usually means the master declared the host but the minion's declared host differs (typo).

**ManagedCertificate stays in `Provisioning` state**
- GKE `ManagedCertificate` needs DNS validation. Check `kubectl describe managedcertificate <name> -n ingress-nginx` — usually shows "Waiting for DNS records". Ensure the domain's A record points at something routable during provisioning.

**State YAML says `status: failed` at Step 3B**
- The in-place edit failed post-validation. Look at `state.yaml` → `steps[3].modified[]` for the pre-edit hash and the env where failure occurred. Fix the source minion's YAML, then `*gateway-migrate <module> --resume`.

**Re-running the skill on an already-migrated module**
- Use `--resume` if you want to pick up from the last successful step. Use `--force` if you want to regenerate everything (the skill's never-clobber check will be bypassed). Without flags, the skill refuses to proceed if `common.gateway/` already exists.

**Gemini CLI users: skill not appearing in the skills list**
- `gateway-api-migration` needs to be registered in `.gemini/extensions/devops/gemini-extension.json`. v1.7.0 shipped with a gap — fixed on `main` post-release. Update to the next published version, or manually run `scripts/setup/setup-gemini.sh` which re-syncs the extension.

## Project Structure

```
devops-ai-skill/
├── CLAUDE.md                    # Claude Code entry
├── AGENTS.md                    # OpenAI Codex entry
├── GEMINI.md                    # Gemini CLI entry
├── VERSION                      # Version source
│
├── .claude/                     # Claude Code platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   └── skills/ → symlink to skills/
│
├── .codex/                      # OpenAI Codex platform
│   ├── config.toml
│   └── skills/ → symlink to skills/
│
├── .gemini/                     # Google Gemini platform
│   ├── settings.json
│   ├── agents/
│   │   ├── horus.md
│   │   └── zeus.md
│   ├── commands/devops/          # Command palette TOML
│   │   ├── agents/               # 2 agent start commands
│   │   └── pipelines/            # 17 pipeline commands
│   └── extensions/devops/
│       └── gemini-extension.json
│
├── .agents/                     # Google Antigravity platform
│   ├── rules/devops.md
│   ├── skills/
│   │   ├── horus/SKILL.md
│   │   ├── zeus/SKILL.md
│   │   └── (10 skill symlinks)
│   └── workflows/               # symlinks → prompts/
│
├── skills/                      # Shared skills (Open Agent Skills standard)
│   ├── terraform-validate/
│   ├── terraform-security/
│   ├── helm-version-upgrade/
│   ├── helm-scaffold/
│   ├── cicd-enhancer/
│   ├── kustomize-resource-validation/
│   ├── yaml-fix-suggestions/
│   ├── gateway-api-migration/
│   └── repo-detect/
│
├── prompts/                     # Platform-neutral pipeline definitions
│   ├── horus/                   # 7 pipelines
│   ├── zeus/                    # 8 pipelines
│   └── shared/                  # repo-detect, report-format, tool-check, help
│
├── docs/
│   ├── quick-start.md           # 5-minute quick start
│   ├── setup.md                 # Detailed setup guide
│   ├── gateway/                 # NGINX → Gateway API migration reference
│   ├── guide/                   # Tutorial screenshots
│   ├── reports/                 # Generated pipeline reports (*full output)
│   └── diagrams/                # Generated architecture diagrams (*diagram output)
│
├── scripts/
│   ├── setup.sh                    # Unified install script (recommended)
│   ├── install-tools.sh
│   ├── version-check.sh
│   └── setup/
│       ├── setup-claude.sh         # Platform-specific (internal)
│       ├── setup-codex.sh
│       ├── setup-gemini.sh
│       └── setup-antigravity.sh
│
├── .claude-plugin/              # Claude Code marketplace
│   ├── plugin.json
│   └── marketplace.json
│
└── tests/
    └── test-structure.sh        # 334 structure + parity tests
```

## Version Check

```bash
bash scripts/version-check.sh
```

## Update

```bash
# Git
git pull origin main

# Or specific version
git checkout v<version>

# Or npx skills
npx skills update
```

## Design Principles

- **No hardcoded paths** — Both agents discover directories dynamically
- **Graceful degradation** — Missing tools skip the check and show install commands
- **User-controlled** — Critical operations (e.g., terraform init) always ask the user
- **Dynamic discovery** — Each skill defines "Step 0: Discover Repository Layout"

## License

MIT
