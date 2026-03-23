# 5 分鐘快速上手 — DevOps AI Skill Pack

> 零基礎也能在 5 分鐘內讓 AI Agent 幫你做 DevOps！

[繁體中文](#繁體中文) | [English](#english)

---

<a id="繁體中文"></a>

## 前置條件

你只需要：

- **Git** — 版本控制（你應該已經有了）
- **一個 AI CLI 工具**（任選一個）：
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — `npm install -g @anthropic-ai/claude-code`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @anthropic-ai/gemini-cli`
  - [OpenAI Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [Google Antigravity](https://developers.google.com/antigravity) — IDE 內建

> 不需要先安裝 Terraform、Helm 等 DevOps 工具！Agent 會在需要時提示你安裝。

## Step 1：安裝 Skill Pack（1 分鐘）

```bash
# 下載
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill

# 全域安裝（自動偵測你的 AI CLI）
bash scripts/install-global.sh
```

看到 `✅ Installation complete!` 就完成了。

## Step 2：啟動 Agent（30 秒）

切換到你的 DevOps 專案目錄，啟動 AI CLI：

```bash
cd ~/your-project        # 你的 Terraform/Kustomize 專案
claude                   # 或 gemini、codex
```

Agent 會自動偵測你的專案類型：
- 有 `*.tf` 檔案 → **Horus**（IaC 專家）自動啟動
- 有 `kustomization.yaml` → **Zeus**（GitOps 專家）自動啟動

## Step 3：跑你的第一個指令（1 分鐘）

### 情境 A：Terraform + Helm 專案（Horus）

```
> *health
```

Horus 會掃描你的專案並產生健康報告，告訴你：
- 哪些工具已安裝、哪些缺少
- 專案結構是否正確
- 有沒有常見的配置問題

### 情境 B：Kustomize + ArgoCD 專案（Zeus）

```
> *health-check
```

Zeus 會檢查你的 GitOps 儲存庫：
- Kustomize overlay 是否正確
- YAML 格式是否合規
- 有沒有孤立的資源檔案

## Step 4：試試更多功能（2 分鐘）

### 常用指令速查

| 你想做的事 | Horus 指令 | Zeus 指令 |
|-----------|-----------|-----------|
| 完整健檢 | `*full` | `*full` |
| 安全掃描 | `*security` | `*full`（含安全） |
| 驗證格式 | `*validate` | `*pre-merge` |
| 升級版本 | `*upgrade` | — |
| 新增模組 | `*new-module` | `*onboard` |
| 產生架構圖 | — | `*diagram` |
| 檢查工具 | `*health` | `*status` |

### 實戰範例

```
> *validate
# → Horus 自動跑 terraform fmt + validate + tflint，產出報告

> *security
# → Horus 分析你的 .tf 檔案，找出安全風險

> *upgrade
# → Horus 查詢 ArtifactHub，列出可升級的 Helm Charts
```

## Step 5：安裝 DevOps 工具（選做）

Agent 在執行過程中會告訴你缺少哪些工具，你也可以一次安裝：

```bash
# 互動模式：逐一確認安裝
./scripts/install-tools.sh

# 一鍵安裝你的 Agent 所需工具
./scripts/install-tools.sh install horus   # Terraform + Helm 工具
./scripts/install-tools.sh install zeus    # Kustomize + GitOps 工具
```

## 常見問題

### Q: 我沒有 Terraform 專案，可以先試玩嗎？

可以！建一個最小專案來體驗：

```bash
mkdir demo-iac && cd demo-iac
cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.0"
}

resource "null_resource" "demo" {}
EOF
claude    # 啟動 Agent，輸入 *health
```

### Q: 我用 Windows，怎麼辦？

用 Git Bash、WSL 或 MSYS2 執行安裝腳本：

```powershell
# Git Bash（推薦）
bash scripts/install-global.sh

# WSL
wsl bash scripts/install-global.sh
```

### Q: 安裝後什麼都沒反應？

確認你有用 `--status` 檢查安裝狀態：

```bash
bash scripts/install-global.sh --status
```

### Q: 可以同時用多個平台嗎？

可以！全域安裝會自動偵測所有已安裝的 AI CLI 並全部設定。

## 下一步

- 📖 [完整安裝指南](setup.md) — 進階安裝選項
- 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill) — Star 支持我們！
- 📂 [docs/guide/](guide/) — 教學截圖（持續更新中）

---

<a id="english"></a>

## English

### Prerequisites

You only need:

- **Git**
- **One AI CLI tool** (pick any):
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — `npm install -g @anthropic-ai/claude-code`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @anthropic-ai/gemini-cli`
  - [OpenAI Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [Google Antigravity](https://developers.google.com/antigravity) — Built into IDE

> No need to install Terraform, Helm, etc. first! The agent will prompt you when needed.

### Step 1: Install the Skill Pack (1 min)

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh
```

Done when you see `✅ Installation complete!`

### Step 2: Launch the Agent (30 sec)

```bash
cd ~/your-project        # Your Terraform/Kustomize project
claude                   # Or gemini, codex
```

The agent auto-detects your project type:
- Has `*.tf` files → **Horus** (IaC expert) activates
- Has `kustomization.yaml` → **Zeus** (GitOps expert) activates

### Step 3: Run Your First Command (1 min)

**Terraform + Helm** (Horus): `*health`
**Kustomize + ArgoCD** (Zeus): `*health-check`

### Step 4: Try More Commands (2 min)

| Goal | Horus | Zeus |
|------|-------|------|
| Full check | `*full` | `*full` |
| Security scan | `*security` | `*full` (includes security) |
| Validate format | `*validate` | `*pre-merge` |
| Upgrade versions | `*upgrade` | — |
| New module | `*new-module` | `*onboard` |
| Architecture diagram | — | `*diagram` |
| Tool check | `*health` | `*status` |

### Step 5: Install DevOps Tools (optional)

```bash
./scripts/install-tools.sh install horus   # Terraform + Helm tools
./scripts/install-tools.sh install zeus    # Kustomize + GitOps tools
```

### FAQ

**Q: No Terraform project to test with?**

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

**Q: Windows?** Use Git Bash, WSL, or MSYS2.

**Q: Nothing happens after install?** Run `bash scripts/install-global.sh --status` to verify.

### Next Steps

- 📖 [Full Setup Guide](setup.md)
- 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill)
- 📂 [docs/guide/](guide/) — Tutorial screenshots (coming soon)
