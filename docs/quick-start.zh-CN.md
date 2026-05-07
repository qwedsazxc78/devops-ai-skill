# 5 分钟快速上手 — DevOps AI Skill Pack

> 零基础也能在 5 分钟内让 AI Agent 帮你做 DevOps！

[English](quick-start.md) | [繁體中文](quick-start.zh-TW.md) | 简体中文

---

## 前置条件

你只需要：

- **Git** — 版本控制（你应该已经有了）
- **一个 AI CLI 工具**（任选一个）：
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) — `npm install -g @anthropic-ai/claude-code`
  - [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) — `npm install -g @anthropic-ai/gemini-cli`
  - [OpenAI Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`
  - [Google Antigravity](https://developers.google.com/antigravity) — IDE 内建

> 不需要先安装 Terraform、Helm 等 DevOps 工具！Agent 会在需要时提示你安装。

## Step 1：安装 Skill Pack（1 分钟）

**macOS / Linux：**

```bash
# 下载
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill

# 全局安装（自动检测你的 AI CLI）
bash scripts/install-global.sh
```

**Windows（一键安装）：**

```powershell
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
.\install.bat                      # 交互式菜单，选 [1] Skills
```

看到 `Global install complete!` 就完成了。

![全局安装运行中](guide/01-install-global-run.png)
![全局安装完成](guide/03-install-global-complete.png)

## Step 2：启动 Agent（30 秒）

切换到你的 DevOps 项目目录，启动 AI CLI：

```bash
cd ~/your-project        # 你的 Terraform/Kustomize 项目
claude                   # Claude Code
# gemini                 # Google Gemini CLI
# codex                  # OpenAI Codex CLI
# antigravity            # Google Antigravity（IDE 内启动）
```

Agent 会自动检测你的项目类型：
- 有 `*.tf` 文件 → **Horus**（IaC 专家）自动启动
- 有 `kustomization.yaml` → **Zeus**（GitOps 专家）自动启动

**Gemini CLI 示例** — skills 和 commands 会自动发现：

![Gemini Skills 列表](guide/06-gemini-skills-list.png)
![Gemini Commands 与 Pipelines](guide/07-gemini-commands-pipelines.png)

**Zeus Agent 启动** — Agent 自我介绍并列出可用 pipelines：

![Zeus Agent 启动](guide/08-zeus-agent-activation.png)

## Step 3：跑你的第一个指令（1 分钟）

### 情境 A：Terraform + Helm 项目（Horus）

```
> *health
```

Horus 会扫描你的项目并生成健康报告，告诉你：
- 哪些工具已安装、哪些缺少
- 项目结构是否正确
- 有没有常见的配置问题

### 情境 B：Kustomize + ArgoCD 项目（Zeus）

```
> *health
```

Zeus 会检查你的 GitOps 仓库：
- Kustomize overlay 是否正确
- YAML 格式是否合规
- 有没有孤立的资源文件

![Zeus Full Pipeline 运行](guide/09-zeus-full-pipeline-run.png)

## Step 4：试试更多功能（2 分钟）

### 常用指令速查

| 你想做的事 | Horus 指令 | Zeus 指令 |
|-----------|-----------|-----------|
| 完整健检 | `*full` | `*full` |
| 安全扫描 | `*security` | `*full`（含安全） |
| 验证格式 | `*validate` | `*pre-merge` |
| 升级版本 | `*upgrade` | — |
| 构建新模块 | `*scaffold` | `*scaffold` |
| 生成架构图 | — | `*diagram` |
| 检查工具 | `*health` | `*status` |

### 实战范例

```
> *validate
# → Horus 自动跑 terraform fmt + validate + tflint，生成报告

> *security
# → Horus 分析你的 .tf 文件，找出安全风险

> *upgrade
# → Horus 查询 ArtifactHub，列出可升级的 Helm Charts
```

## Step 5：安装 DevOps 工具（选做）

Agent 在执行过程中会告诉你缺少哪些工具，你也可以一次安装：

![工具状态检查](guide/04-install-tools-status.png)
![Horus 工具安装](guide/05-install-tools-horus.png)

**macOS / Linux：**

```bash
# 交互模式：逐一确认安装
./scripts/install-tools.sh

# 一键安装你的 Agent 所需工具
./scripts/install-tools.sh install horus   # Terraform + Helm 工具
./scripts/install-tools.sh install zeus    # Kustomize + GitOps 工具
```

**Windows：**

```powershell
.\scripts\install-tools.ps1
.\scripts\install-tools.ps1 install horus
.\scripts\install-tools.ps1 install zeus
```

## 常见问题

### Q: 我没有 Terraform 项目，可以先试玩吗？

可以！建一个最小项目来体验：

```bash
mkdir demo-iac && cd demo-iac
cat > main.tf << 'EOF'
terraform {
  required_version = ">= 1.0"
}

resource "null_resource" "demo" {}
EOF
claude    # 启动 Agent（或 gemini/codex），输入 *health
```

### Q: 我用 Windows，怎么办？

原生 PowerShell 安装，不需要 Git Bash 或 WSL：

```powershell
# 一键安装（交互式菜单）
.\install.bat

# 或非交互执行
powershell -ExecutionPolicy Bypass -File scripts\install-global.ps1
powershell -ExecutionPolicy Bypass -File scripts\install-tools.ps1 install
```

针对 PowerShell 5.1（Windows 10 / 11 / Server 2016+ 内置），开箱即用。如果你还是偏好用 bash，Git Bash 与 WSL 仍可搭配 `.sh` 脚本：

```bash
# Git Bash
bash scripts/install-global.sh

# WSL
wsl bash scripts/install-global.sh
```

### Q: 安装后什么都没反应？

确认你有用 `--status` 检查安装状态：

```bash
bash scripts/install-global.sh --status
```

![安装状态](guide/02-install-global-status.png)

### Q: 可以同时用多个平台吗？

可以！全局安装会自动检测所有已安装的 AI CLI 并全部设置。

## 下一步

- 📖 [完整安装指南](setup.md) — 进阶安装选项
- 🌐 [GitHub Repo](https://github.com/qwedsazxc78/devops-ai-skill) — Star 支持我们！
- 📂 [docs/guide/](guide/) — 教学截图
