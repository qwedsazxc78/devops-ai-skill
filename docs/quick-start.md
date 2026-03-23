# 5-Minute Quick Start — DevOps AI Skill Pack

> Zero to AI-powered DevOps in 5 minutes!

English | [繁體中文](quick-start.zh-TW.md) | [简体中文](quick-start.zh-CN.md)

---

## Prerequisites

You only need:

- **Git**
- **One AI CLI tool** (pick any):
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — `npm install -g @anthropic-ai/claude-code`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @anthropic-ai/gemini-cli`
  - [OpenAI Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [Google Antigravity](https://developers.google.com/antigravity) — Built into IDE

> No need to install Terraform, Helm, etc. first! The agent will prompt you when needed.

## Step 1: Install the Skill Pack (1 min)

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh
```

Done when you see `✅ Installation complete!`

## Step 2: Launch the Agent (30 sec)

```bash
cd ~/your-project        # Your Terraform/Kustomize project
claude                   # Or gemini, codex
```

The agent auto-detects your project type:
- Has `*.tf` files → **Horus** (IaC expert) activates
- Has `kustomization.yaml` → **Zeus** (GitOps expert) activates

## Step 3: Run Your First Command (1 min)

### Scenario A: Terraform + Helm (Horus)

```
> *health
```

Horus scans your project and generates a health report:
- Which tools are installed / missing
- Project structure validation
- Common configuration issues

### Scenario B: Kustomize + ArgoCD (Zeus)

```
> *health
```

Zeus checks your GitOps repository:
- Kustomize overlay correctness
- YAML format compliance
- Orphaned resource detection

## Step 4: Try More Commands (2 min)

### Command Quick Reference

| Goal | Horus | Zeus |
|------|-------|------|
| Full check | `*full` | `*full` |
| Security scan | `*security` | `*full` (includes security) |
| Validate format | `*validate` | `*pre-merge` |
| Upgrade versions | `*upgrade` | — |
| Scaffold new module | `*scaffold` | `*scaffold` |
| Architecture diagram | — | `*diagram` |
| Tool check | `*health` | `*status` |

### Examples

```
> *validate
# → Horus runs terraform fmt + validate + tflint, generates report

> *security
# → Horus analyzes your .tf files for security risks

> *upgrade
# → Horus queries ArtifactHub, lists upgradable Helm Charts
```

## Step 5: Install DevOps Tools (optional)

The agent tells you which tools are missing during execution. You can also install them all at once:

```bash
# Interactive: confirm each install
./scripts/install-tools.sh

# One-click install for your agent
./scripts/install-tools.sh install horus   # Terraform + Helm tools
./scripts/install-tools.sh install zeus    # Kustomize + GitOps tools
```

## FAQ

### Q: No Terraform project to test with?

Create a minimal project:

```bash
mkdir demo-iac && cd demo-iac
cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.0"
}

resource "null_resource" "demo" {}
EOF
claude    # Start agent, type *health
```

### Q: Windows?

Use Git Bash, WSL, or MSYS2:

```powershell
# Git Bash (recommended)
bash scripts/install-global.sh

# WSL
wsl bash scripts/install-global.sh
```

### Q: Nothing happens after install?

Check install status:

```bash
bash scripts/install-global.sh --status
```

### Q: Can I use multiple platforms at once?

Yes! Global install auto-detects all installed AI CLIs and configures them all.

## Next Steps

- 📖 [Full Setup Guide](setup.md) — Advanced install options
- 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill) — Star us!
- 📂 [docs/guide/](guide/) — Tutorial screenshots (coming soon)
