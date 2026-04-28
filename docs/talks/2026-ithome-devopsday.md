---
title: "iThome DevOps Day 2026 學員手冊"
subtitle: "我把 IaC 痛點丟給 AI — Horus & Zeus 上班這檔事"
talk_date: "TBD"
speaker: "Alex Hsieh"
published_at: "TBD-after-talk"
status: "pre-talk-draft"
source_repo: "private — content-asset-system/assets/course-2026-ithome-devopsday/student-handbook.md"
---

> 👋 這是 iThome DevOps Day 2026 60-min keynote「我把 IaC 痛點丟給 AI — Horus & Zeus 上班這檔事」的學員自學手冊。
> 包含 3 個練習（Horus IaC / Zeus GitOps / Pipeline 串連），完整指令可直接 copy-paste。
> Talk 結束後會更新 `published_at` 與 recording 連結。

# iThome DevOps Day 2026 學員手冊

> 這是 QR Code 掃進來的那份手冊。花 30 分鐘把環境裝好、跑完 3 個練習，你就把今天台上演示的 AI 技能帶回家了。

---

## §0 關於這場 talk

這場 talk 的主角是 `devops-ai-skill` — 一個把 Terraform + Helm + Kustomize 維運最佳實踐包成 AI Skill 的開源工具包。兩個 agent：Horus 負責 IaC（Terraform + Helm），Zeus 負責 GitOps（Kustomize + ArgoCD）。台上我演示的是「同一個有問題的 Terraform repo，先用人手改一個檔案花了快 8 分鐘，再交給 Horus 跑完整個 pipeline 只要 5 分鐘」的對比。

你現在看到的這份手冊就是讓你自己動手重現那個過程。我把練習設計成三層：A 是 Horus 基礎驗證（10 分鐘），B 是 Zeus 基礎驗證（10 分鐘），C 是串完整 Horus pipeline（選做，20 分鐘）。三個練習都是 copy-paste 可跑的指令，不需要額外的 GCP 帳號或真實部署。

- Slides PDF：**[TBD — talk 後上傳至 devops-ai-skill/docs/talks/]**
- Recording：**[TBD — iThome 官方發布後補連結]**

---

## §1 課前準備

### 必裝 CLI（選一即可）

`devops-ai-skill` 支援四個平台，選其中一個安裝即可：

- **Claude Code**：`curl -fsSL https://claude.ai/install.sh | bash`，驗證 `claude --version`
- **OpenAI Codex CLI**：`npm install -g @openai/codex`，驗證 `codex --version`
- **Google Gemini CLI**：`npm install -g @google/gemini-cli`，驗證 `gemini --version`
- **Google Antigravity**：參考官方文件

練習說明以 Claude Code 為主。如果你用其他 CLI，把 `claude` 換成 `codex` / `gemini` / `antigravity` 即可。

### IaC 工具

```bash
# macOS
brew install terraform helm kubectl kustomize

# 驗證（看到版本號就 OK）
terraform version && helm version --short && kubectl version --client --short && kustomize version
```

Windows：`winget install Hashicorp.Terraform Helm.Helm Kubernetes.kubectl`，kustomize 用 `scoop install kustomize`。

---

## §2 安裝 `devops-ai-skill`

全域安裝一次，所有專案都能用：

```bash
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
bash scripts/install-global.sh
```

這個腳本會自動偵測你裝了哪些 AI CLI，並複製 Horus / Zeus agents + 10 個 skills 到對應的全域設定目錄。

### 驗證安裝

```bash
bash scripts/install-global.sh --status
```

預期輸出（以 Claude Code 為例）：

```
Claude Code   ✓  ~/.claude/agents/horus.md
Claude Code   ✓  ~/.claude/agents/zeus.md
Claude Code   ✓  ~/.claude/skills/terraform-validate/
Claude Code   ✓  ~/.claude/skills/kustomize-resource-validation/
...（共 10 個 skills）
```

看到全部打勾就代表安裝完成。如果某個 CLI 沒裝，那一行會顯示 `✗ not installed`，正常，跳過就好。

---

## §3 Fork 兩個 Template Repo

你需要自己的 fork，這樣才能對著自己的 repo 跑練習（也可以直接 clone 來跑 read-only 驗證，不影響結果）。

**強調：請從 `main` 分支 fork，不要 fork `demo-conditioned/2026-ithome-devopsday` 分支。** 那個分支是台上演示專用的「刻意破壞版」，結構和 main 不同。

### Fork 步驟

1. 開瀏覽器到 `https://github.com/qwedsazxc78/iac-template-ai-skill`，點右上角「Fork」，確認分支是 `main`
2. 開瀏覽器到 `https://github.com/qwedsazxc78/gitops-template-ai-skill`，同樣 fork `main`
3. Clone 你的 fork 到本機：

```bash
# 換成你自己的 GitHub username
git clone https://github.com/<your-username>/iac-template-ai-skill.git
git clone https://github.com/<your-username>/gitops-template-ai-skill.git
```

---

## §4 練習 A — Horus IaC 驗證

**目標：** 對 `iac-template-ai-skill` 跑 Horus 的 `terraform-validate` pipeline，看到 AI 自動找出格式問題和潛在的安全建議。

### 步驟

```bash
# 1. 進入你 clone 下來的 iac-template-ai-skill 目錄
cd iac-template-ai-skill

# 2. 啟動 Claude Code（Horus agent 全域安裝後會自動可用）
claude

# 3. 在 Claude Code 互動介面中，輸入以下指令觸發 Horus
> *validate
```

### Horus 會做什麼

`*validate` pipeline 包含三個階段：

1. **Step 0 — 探索**：自動掃描 `application/` 目錄，識別 `.tf` 檔案和 Helm modules
2. **Step 1 — fmt 檢查**：對比 `terraform fmt -diff` 輸出，列出格式不一致的行號
3. **Step 2 — 靜態分析**：分析 `0-provider.tf`、`1-variables.tf`、`3-gke.tf`，報告 naming convention 問題、missing required fields、security baseline 差距

### 預期輸出

Horus 跑完後你會看到：Discovery 掃描出 `application/` 下 6 個 `.tf` 檔案 + 2 個 Helm modules → fmt diff（main branch 若已格式化通常 no differences）→ 靜態分析報告（N findings，依 info / warning / error 分類）。

### 3 個看點

- **看 Discovery 階段**：Horus 沒有 hardcoded 路徑，它是動態掃描出 `application/` 下有哪些 `.tf` 和 module。這就是 spec 說的「No hardcoded paths」設計原則
- **看格式建議**：即使 main branch 的格式相對乾淨，Horus 還是會分析 variable descriptions 是否完整、outputs 是否有型別標注
- **看 security 建議**：重點看 GKE cluster 相關的設定（`3-gke.tf`）——Horus 會針對 GKE hardening checklist 給出具體建議，例如 Workload Identity、Private nodes、Binary Authorization 等

---

## §5 練習 B — Zeus GitOps 驗證

**目標：** 對 `gitops-template-ai-skill` 跑 Zeus 的 `kustomize-resource-validation` pipeline，看到 AI 驗證三個環境的 Kustomize build 是否正確，並找出跨環境的設定差異。

### 步驟

```bash
# 1. 進入你 clone 下來的 gitops-template-ai-skill 目錄
cd gitops-template-ai-skill

# 2. 啟動 Claude Code
claude

# 3. 在 Claude Code 互動介面中，觸發 Zeus
> *health
```

### Zeus 會做什麼

Zeus 的 `*health` pipeline 掃描：

1. **Kustomize build** — 對 `overlays/dev`、`overlays/stg`、`overlays/prd` 各跑一次 `kustomize build`，確認三個環境都能成功 render
2. **孤兒資源掃描** — 找出宣告在 `base/` 但沒有被任何 overlay 引用的資源（`app.ingress.yaml`、`app.hpa.yaml`、`app.pdb.yaml` 等）
3. **跨環境 drift 偵測** — 比較 dev / stg / prd 的 `replicas`、resource limits、image tag 設定是否一致，有差異時標出

### 預期輸出

Zeus 跑完後：Discovery（`base/` 6 資源 + `overlays/dev|stg|prd`）→ kustomize build 三個環境各 PASS → 跨環境 drift 摘要（例如 `replicas: dev=1, stg=2, prd=3`）→ 整體 health 評分。

---

## §6 練習 C — 串 Horus Pipeline（選做）

這是 stretch goal。如果你想看台上那個「8 分鐘手動 vs 5 分鐘 Horus」對比的完整流程，可以在 `iac-template-ai-skill` 上跑完整的 Horus pipeline。

**前提：** 先完成練習 A，確認 Horus 安裝正常可用。

### 步驟

```bash
# 進入 iac-template-ai-skill 目錄後啟動 Claude Code
cd iac-template-ai-skill
claude
```

在 Claude Code 互動介面中依序執行，等每一步完成後再繼續：

```
> *validate    # 第 1 步：fmt + 靜態分析
> *security    # 第 2 步：安全稽核
> *upgrade     # 第 3 步：Helm 版本升級建議
```

或者直接跑 `*full` 一次完成全部（fmt → 靜態分析 → security → Helm 版本 → 完整報告）：

```
> *full
```

### 流程說明

| 指令 | Horus 做什麼 |
|---|---|
| `*validate` | terraform fmt diff + naming + missing fields |
| `*security` | GKE hardening + IAM + Helm security review |
| `*upgrade` | 檢查 `ingress-nginx`（v4.12.1）和 `cert-manager`（v1.17.2）是否有更新版本 |

`*full` 跑完後 Horus 會輸出一份 markdown 完整報告：格式問題 + Security findings（HIGH / MEDIUM / INFO）+ Helm 版本建議 + 建議下一步。把報告存起來，對著自己的真實 Terraform repo 跑一次，就是把今天帶回工作的第一步。

---

## §7 疑難排解

> **這是 placeholder。T-7 天排練後我會把真實遇到的錯誤訊息和解法填進來。以下是我預想的五個常見問題。**

**Q: Horus / Zeus agent 不出現，打 `*validate` 沒反應**
A: 全域安裝沒成功。跑 `bash scripts/install-global.sh --status` 確認，看到 `✗` 就重跑 `bash scripts/install-global.sh --claude`。

**Q: `claude` 要求 auth，但 key 已設定**
A: `claude auth login` 重新登入，或確認 `ANTHROPIC_API_KEY` 環境變數有效。公司 proxy 環境先確認 `https://api.anthropic.com` 沒被擋。

**Q: `*validate` 跑到一半 hang 住**
A: 確認 `terraform version` 能正常輸出。工具缺少時 Horus 會 graceful degrade（跳過那步並顯示安裝指令）。

**Q: Claude 回傳亂碼或格式不像 Horus**
A: agent 檔案沒正確安裝。`ls -la ~/.claude/agents/` 確認 `horus.md` 存在且非空。

**Q: `kustomize build overlays/dev` 找不到 base resource**
A: 確認你在 `gitops-template-ai-skill` 的根目錄，不是在 `overlays/dev/` 子目錄裡。

---

## §8 接下來去哪

你已經把 Horus + Zeus 跑起來了。以下是繼續深入的方向：

- **GitHub Discussions**（問問題 / 分享 findings）：`https://github.com/qwedsazxc78/devops-ai-skill/discussions`
- **GitHub Issues**（回報 bug 或提 feature request）：`https://github.com/qwedsazxc78/devops-ai-skill/issues`
- **Contribution Guide**（Skills 遵循 Open Agent Skills 標準，SKILL.md + YAML frontmatter）：`https://github.com/qwedsazxc78/devops-ai-skill/blob/main/CONTRIBUTING.md`

### 今天 talk 沒有涵蓋的 4 個 skills

今天台上我只演示了 `terraform-validate`、`terraform-security`、`helm-version-upgrade`、`kustomize-resource-validation` 和 `gateway-api-migration`。以下這四個 skill 也在包裡，有興趣可以自己試：

| Skill | 誰用 | 做什麼 |
|---|---|---|
| `release-validate` | Horus + Zeus 共用 | 發 release 前的就緒檢查（changelog、version tag、CI 狀態） |
| `helm-scaffold` | Horus | 互動式生成新 Helm module 架構（省去手動建目錄和 boilerplate） |
| `cicd-enhancer` | Horus | 分析現有 CI/CD pipeline，給出最佳化建議（GitHub Actions / GitLab CI） |
| `repo-detect` | Horus + Zeus 共用 | 自動偵測 repo 類型（Terraform / Kustomize / 混合），決定要用哪個 agent |

---

## §9 Talk 素材

- **Slides PDF**：`https://github.com/qwedsazxc78/devops-ai-skill/blob/main/docs/talks/2026-ithome-devopsday/slides.pdf`（talk 後上傳）
- **Recording**：iThome 官方頻道發布後補連結（TBD）
- **Slides 原始稿**：`https://github.com/qwedsazxc78/content-asset-system/assets/course-2026-ithome-devopsday/`（課程備課 repo，含 speaker notes）
- **devops-ai-skill repo**：`https://github.com/qwedsazxc78/devops-ai-skill`（fork 這個，開始用）

---

> 文件版本：draft
> 最後更新：2026-04-27
> 維護者：Alex Hsieh
> 發布目標：PR 至 `devops-ai-skill/docs/talks/2026-ithome-devopsday.md`（T-3 天）
