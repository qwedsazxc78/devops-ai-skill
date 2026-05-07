# 5 分鐘快速上手 — DevOps AI Skill Pack

> 零基礎也能在 5 分鐘內讓 AI Agent 幫你做 DevOps！

[English](quick-start.md) | 繁體中文 | [简体中文](quick-start.zh-CN.md)

---

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

**macOS / Linux：**

```bash
# 下載
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill

# 全域安裝（自動偵測你的 AI CLI）
bash scripts/install-global.sh
```

**Windows（一鍵安裝）：**

```powershell
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
.\install.bat                      # 互動式選單，選 [1] Skills
```

看到 `Global install complete!` 就完成了。

![全域安裝執行中](guide/01-install-global-run.png)
![全域安裝完成](guide/03-install-global-complete.png)

## Step 2：啟動 Agent（30 秒）

切換到你的 DevOps 專案目錄，啟動 AI CLI：

```bash
cd ~/your-project        # 你的 Terraform/Kustomize 專案
claude                   # Claude Code
# gemini                 # Google Gemini CLI
# codex                  # OpenAI Codex CLI
# antigravity            # Google Antigravity（IDE 內啟動）
```

Agent 會自動偵測你的專案類型：
- 有 `*.tf` 檔案 → **Horus**（IaC 專家）自動啟動
- 有 `kustomization.yaml` → **Zeus**（GitOps 專家）自動啟動

**Gemini CLI 範例** — skills 和 commands 會自動偵測：

![Gemini Skills 清單](guide/06-gemini-skills-list.png)
![Gemini Commands 與 Pipelines](guide/07-gemini-commands-pipelines.png)

**Zeus Agent 啟動** — Agent 自我介紹並列出可用 pipelines：

![Zeus Agent 啟動](guide/08-zeus-agent-activation.png)

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
> *health
```

Zeus 會檢查你的 GitOps 儲存庫：
- Kustomize overlay 是否正確
- YAML 格式是否合規
- 有沒有孤立的資源檔案

![Zeus Full Pipeline 執行](guide/09-zeus-full-pipeline-run.png)

## Step 4：試試更多功能（2 分鐘）

### 常用指令速查

| 你想做的事 | Horus 指令 | Zeus 指令 |
|-----------|-----------|-----------|
| 完整健檢 | `*full` | `*full` |
| 安全掃描 | `*security` | `*full`（含安全） |
| 驗證格式 | `*validate` | `*pre-merge` |
| 升級版本 | `*upgrade` | — |
| 建置新模組 | `*scaffold` | `*scaffold` |
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

![工具狀態檢查](guide/04-install-tools-status.png)
![Horus 工具安裝](guide/05-install-tools-horus.png)

**macOS / Linux：**

```bash
# 互動模式：逐一確認安裝
./scripts/install-tools.sh

# 一鍵安裝你的 Agent 所需工具
./scripts/install-tools.sh install horus   # Terraform + Helm 工具
./scripts/install-tools.sh install zeus    # Kustomize + GitOps 工具
```

**Windows：**

```powershell
.\scripts\install-tools.ps1
.\scripts\install-tools.ps1 install horus
.\scripts\install-tools.ps1 install zeus
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
claude    # 啟動 Agent（或 gemini/codex），輸入 *health
```

### Q: 我用 Windows，怎麼辦？

原生 PowerShell 安裝，不需要 Git Bash 或 WSL：

```powershell
# 一鍵安裝（互動式選單）
.\install.bat

# 或非互動執行
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1
powershell -ExecutionPolicy Bypass -File scripts\install-tools.ps1 install
```

針對 PowerShell 5.1（Windows 10 / 11 / Server 2016+ 內建），開箱即用。如果你還是偏好用 bash，Git Bash 與 WSL 仍可搭配 `.sh` 腳本：

```bash
# Git Bash
bash scripts/install-global.sh

# WSL
wsl bash scripts/install-global.sh
```

### Q: 安裝後什麼都沒反應？

確認你有用 `--status` 檢查安裝狀態：

```bash
bash scripts/install-global.sh --status
```

![安裝狀態](guide/02-install-global-status.png)

### Q: 可以同時用多個平台嗎？

可以！全域安裝會自動偵測所有已安裝的 AI CLI 並全部設定。

## 下一步

- 📖 [完整安裝指南](setup.md) — 進階安裝選項
- 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill) — Star 支持我們！
- 📂 [docs/guide/](guide/) — 教學截圖
