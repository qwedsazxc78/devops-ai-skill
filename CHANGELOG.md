# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.12.0] - 2026-05-19

### Added

- **Skill — `ingress-migration-advisor` (new Zeus skill)**
  - Read-only planner for the NGINX Ingress Controller 2025 EOL migration. Inventories every Ingress in the repo, scores each service on five dimensions, and recommends a path per service (`direct-gateway`, `two-step`, `swap-only`, `defer`).
  - Critical-tier veto (from `docs/ingress-tier-map.yaml`) — critical services are forced to `defer` regardless of score; no `--force-critical` bypass. The tier map is required (HALT if missing).
  - `sourceClass: traefik` shortcut — services already on Traefik Ingress route directly to `direct-gateway`, skipping a redundant swap phase.
  - Score range 4–14 (traffic-tier dimension caps at 2 because score-3 is reserved for the veto). Bands: 4–7 → direct-gateway · 8–10 → two-step · 11–13 → swap-only · 14 → defer.
  - 3 Python scripts: `inventory_all_ingresses.py` (reuses gateway-api-migration's classify_ingress.py via subprocess), `score_services.py` (veto + 5-dim rubric + decision matrix), `render_plan.py` (plan-template substitution with banner for unresolved placeholders).
  - 3 reference docs: `scoring-model.md` (the rubric, edit via PR), `decision-matrix.md` (bands + sourceClass shortcut), `plan-template.md` (Mermaid Gantt + per-service decision table + per-batch command block).
  - Output: `docs/reports/ingress-migration-advisor/<slug>/{state.yaml,plan.md}`. Batch commands are deduplicated at overlay-level (overlay-wide skills like `*gateway-migrate <overlay>` process all services in one run).
  - Test fixtures: `tests/ingress-migration-advisor/` with 4 cases (critical-tier-veto, source-class-traefik-shortcut, score-band-direct-gateway, foreign-class-defer) — all passing.
  - Gemini TOML command: `zeus-ingress-migration-advisor`.
  - Design spec: `docs/superpowers/specs/2026-05-19-ingress-migration-advisor-design.md`.
- **Skill — `traefik-controller-decommission` (new Horus skill)**
  - SAFE plan-only uninstall of the `ingress-nginx` controller after every Ingress migration completes and DNS bake elapses. Never executes `helm`/`kubectl`; emits `commands.sh` for the operator to run manually.
  - `verify_no_nginx_class.sh` — dual cluster + repo scan. Mirrors Kubernetes' precedence: an Ingress is nginx-class if `spec.ingressClassName == "nginx"` OR (`spec.ingressClassName == null` AND legacy annotation `kubernetes.io/ingress.class == "nginx"`).
  - `generate_uninstall_plan.sh` — renders three sections (Helm uninstall + GKE LB IP release + IAM cleanup) to `plan.md` and a copy-paste-ready `commands.sh`.
  - Verdict: `READY` (all gates pass), `BLOCKED` (any active nginx Ingress or operator declines DNS bake confirmation), `NEEDS_REVIEW` (kubectl/helm unreachable or ambiguous release).
  - Horus pipeline: `*decommission-nginx`.
- **Skill — `ingress-controller-install` (new Horus skill)**
  - Idempotent install or upgrade of Traefik Helm chart, configured for coexistence with `ingress-nginx` (distinct IngressClass, distinct LoadBalancer IP, no port 80/443 conflict).
  - `detect_existing_install.sh` — helm + kubectl probes; branches into install vs upgrade flow.
  - `validate_coexistence.sh` — three collision checks (`classCollision`, `ipCollision`, `portCollision`). HALT on any collision; plan files not written.
  - `references/values-template.yaml` — parameterized Traefik Helm values (`${ENV}`, `${NAMESPACE}`, `${INGRESS_CLASS_NAME}`, `${LB_IP}`, `${GATEWAY_API_ENABLED}`). Keeps `ingressClass.isDefaultClass: false` so Traefik never steals the default class from ingress-nginx.
  - Output: `docs/reports/ingress-controller-install/<date>/{state.yaml,values.yaml,install.sh}`. Operator runs `install.sh` manually.
  - Horus pipeline: `*install-traefik`.
- **Zeus command — `*ingress-to-gateway` (new pipeline, no new skill)**
  - Slash-command sugar for `*gateway-migrate`. Auto-detects the target module's source class (nginx | traefik | mixed | foreign) via the gateway-api-migration classifier, then delegates with the right `--source-class` flag.
  - Mixed-class modules WARN with count breakdown and prompt the operator to pick one class; foreign-only modules HALT (out of scope).
  - Gemini TOML command: `zeus-ingress-to-gateway`.
- **Test fixtures for advisor** — `tests/ingress-migration-advisor/` with 4 cases + runner. Covers veto, sourceClass shortcut, score band, and foreign-class defer paths. `bash tests/ingress-migration-advisor/run-fixtures.sh` exits 0 with all green.

### Fixed

- `verify_no_nginx_class.sh` precedence rule discovered during smoke-testing against `eye-of-horus-gitops`: original logic checked only `spec.ingressClassName`, missing the (very common) state where an Ingress has `spec.ingressClassName: null` and relies on the legacy `kubernetes.io/ingress.class: nginx` annotation. The script now follows Kubernetes' actual precedence (spec wins, annotation is fallback) so the decommission gate cannot falsely return PASS while controller consumers still exist.

### Known issues

- `gateway-api-migration/scripts/classify_ingress.py` uses annotation-first precedence (annotation wins over `spec.ingressClassName`), the opposite of Kubernetes' actual rule. The `ingress-migration-advisor` inherits this and may classify a migrated `spec=traefik, ann=nginx` Ingress as nginx-source. Aligning the classifier is deferred to a follow-up because it also affects the `gateway-api-migration` and `nginx-to-gateway` skills — needs coordinated review across all three.

## [1.11.0] - 2026-05-18

### Added

- **Skill A — `nginx-to-traefik` (new skill)**
  - Class-swap pipeline: replaces `kubernetes.io/ingress.class: nginx` with `traefik` across an entire Kustomize overlay in one operator session.
  - 11-step flow (0, 0b, 1–10): tool check → env-config → inventory → batch plan → generate Traefik Ingress → archive nginx file → kustomization edit → managed-cert update → kustomize build → cross-consistency check → DNS/verify script update.
  - 3 new Python scripts: `inventory_nginx_ingresses.py`, `generate_traefik_ingress.py` (10 annotation-translation rules), `update_kustomization.py` (idempotent resource/patch/host edits).
  - 1 new shell script: `validate_cross_consistency.sh` — 4-way cross-check of DNS script, verify script, Traefik Ingress YAMLs, and `app.ingress.yaml`. Uses `awk` static parsing (no `source`/`eval`) for bash 3.2 compatibility.
  - Reference docs: `annotation-translation.md` (10-row rule table), `dns-cutover-runbook.md` (pre-cutover invariants, cutover sequence, rollback procedure), `nginx-to-traefik-env-config.md` (env-config schema).
  - State YAML schema: `outputs.traefikIngresses[]` — hand-off contract consumed by Skill C.
  - Gemini TOML command: `zeus-nginx-to-traefik`.
- **Skill B enhancement — `gateway-api-migration` extended for Traefik source**
  - New CLI flags: `--source-class nginx|traefik` (default `nginx`), `--source-state <path>` (state.yaml from Skill A), `--no-redirect` (suppress TLS-redirect HTTPRoute when source already serves HTTPS via Traefik).
  - `classify_ingress.py` Rule 5 updated: `traefik` ingressClass is now classified as `"ready"` with `"sourceClass": "traefik"` (was `"skip"`).
  - `validate_generated.py` check 12 `middleware-coverage` extended: traefik-source branch validates `router.middlewares` annotations map to HTTPRoute `extensionRef` filters.
  - `validate_generated.py` check 13 `no-redundant-tls-redirect` (new): WARN when `--source-class traefik` and a `tls-redirect` HTTPRoute is emitted.
  - `docs/gateway/annotation-map.md` appended with Traefik source annotation table (4 rows: router.middlewares, router.tls.options, router.entrypoints).
- **Skill C — `nginx-to-gateway` (new thin orchestrator skill)**
  - Chains Skill A + Skill B in one session: NGINX Ingress → Traefik Ingress → Gateway API resources.
  - 6-step flow (C.0–C.5): merged tool check → chain run-dir → invoke Skill A → hand-off (reads `outputs.traefikIngresses[]`) → invoke Skill B with `--source-class traefik --no-redirect --source-state <A's state.yaml>` → render combined report.
  - Failure semantics: A halt → chain halt; B halt after A done → resume with `--skip-a`; C.5 halt → re-run only render step.
  - Flags: `--gateway-class traefik|gke-l7-global-external-managed`, `--skip-a`, `--skip-b`, `--resume`.
  - Reference: `chain-report-template.md` — `{{ ... }}` template for the combined chain report.
  - Gemini TOML command: `zeus-nginx-to-gateway`.
- **Test fixtures** for both new skills: `tests/nginx-to-traefik/` (4 fixture tests, all passing), `tests/nginx-to-gateway/` (2 fixture tests, all passing).
- **Structure test Section 19** — validates SKILL.md presence and step count, pipeline files, TOML commands, references, and fixture runners for both new skills. Total TOML count updated to 21.

## [1.10.0] - 2026-05-07

### Added

- **Native Windows install — no Git Bash, no WSL.** Two new PowerShell scripts plus a one-click `install.bat` launcher at the repo root.
  - `install.bat` — interactive menu (skills / tools / both / status / uninstall). Resolves PowerShell host (`pwsh.exe` preferred, falls back to `powershell.exe`), passes `-ExecutionPolicy Bypass -NoProfile`. Double-clickable from File Explorer.
  - `scripts/install-global.ps1` — 1:1 port of `install-global.sh`. Same flags (`-All`, `-Claude`, `-Codex`, `-Gemini`, `-Antigravity`, `-Status`, `-Uninstall`), same auto-detect, same plugin cache layout (`%USERPROFILE%\.claude\plugins\cache\devops-ai-skill\...`), same legacy-purge logic. Patches `settings.json` and `installed_plugins.json` natively via `ConvertFrom-Json` / `ConvertTo-Json` (no python3 dependency) and writes BOM-less UTF-8.
  - `scripts/install-tools.ps1` — 1:1 port of `install-tools.sh`. Same TOOLS registry, same `check` / `install [zeus|horus]` subcommands, same 3-attempt retry. Detects `winget` / `choco` / `scoop` / `uv` / `pip3` / `pip` and fails fast (with install URLs) if none are present.
  - Both `.ps1` scripts target PowerShell 5.1 — built into every Windows 10 / 11 / Server 2016+ box, no extra install required.
- **`pnpm setup:win` and `pnpm setup:win:tools`** — npm scripts that invoke the new `.ps1` files non-interactively.
- **22 new structure tests** under "Windows Native Install" section in `tests/test-structure.sh` — verify file presence, drift-control headers, CLI flag parity with bash, package manager references, and `package.json` whitelist coverage.
- **Drift-control headers** on both `.ps1` files identify them as 1:1 ports of the corresponding `.sh` and instruct future contributors to update bash first, then port the diff.

### Changed

- **README.md, docs/quick-start.md (+ zh-TW / zh-CN), docs/setup.md, docs/README.zh-TW.md, docs/README.zh-CN.md** — Windows is now a first-class install target alongside macOS / Linux instead of a "use Git Bash / WSL" footnote. Each install snippet shows both the bash and PowerShell forms.
- **`package.json` `files` whitelist** — added `install.bat` so it ships in the npm tarball.

### Out of scope

- Per-repo `setup.sh` flow on Windows — it relies on Unix symlinks (require Administrator or Developer Mode); Windows users use Global Install (`install.bat` / `install-global.ps1`) instead.
- Auto-installing Git for Windows / `winget` / PowerShell 7 — documented as prerequisites; not bootstrapped (matches bash behavior on macOS without Homebrew).

## [1.9.0] - 2026-04-15

### Added

- **gateway-api-migration v1.2.0 — dual-target Traefik (default) + GKE Gateway (opt-in)**
  - New `--gateway-class <name>` flag (default `traefik`). Skill emits provider-specific CRDs based on prefix: Traefik `Middleware` / `ServersTransport` for `traefik*`; GKE `GCPBackendPolicy` / `HealthCheckPolicy` for `gke-l7-*`; vanilla Gateway API only for any other class.
  - New `--include-orphan-hosts` flag — by default, hostnames advertised on the master with no minion routing them are skipped (smaller Gateway, cleaner output).
  - New `references/traefik-gateway-notes.md` — Traefik-specific reference (CRDs, helm install, Middleware patterns for CORS and path denylist, cert-manager integration, debugging tips).
  - `references/annotation-map.md` upgraded to a per-target matrix. Critical differences:
    - Row 9c path denylists are auto-converted to `Middleware kind: redirectRegex` under Traefik (no longer a manual-review stub). Plugin-based alternative emitted as commented-out option.
    - CORS rows (5–8) become a single shared `Middleware kind: headers` per namespace under Traefik (vs N per-backend GCPBackendPolicy under GKE).
    - Row 10 (proxy-*-timeout) becomes a `ServersTransport` under Traefik with all 3 timeout fields preserved (vs collapsed to a single `timeoutSec` under GKE).
  - SKILL.md Step 0b cluster preflight + Step 4d semantic diff are both target-aware.
- **gateway-api-migration v1.1.0 — Step 1.1 built-overlay default, full enrichment, Step 4d validator**
  - Step 1.1 now uses `kustomize build` to render each overlay before classifying Ingress documents. Closes a long-standing blind spot where base templates with placeholder hostnames caused false-positive "orphan minion" halts. Dead files on disk that no `kustomization.yaml` references are also automatically excluded.
  - 5 new bundled scripts: `check_cluster_preflight.sh`, `classify_ingress.py`, `pair_minions.py`, `inventory_annotations.py`, `build_report.py`. Pure deterministic logic moved out of the model's natural-language re-derivation.
  - New `scripts/validate_generated.py` — Step 4d semantic validator. 12 checks: kustomize-build (gateway/service), listener-coverage, httproute-parentref-name, source-hostname-coverage (active hostnames only — orphans intentionally excluded), source-backend-coverage, path-coverage (with `ImplementationSpecific /` → `PathPrefix /` normalization), namespace-consistency, tls-secret-coverage (active secrets), dead-file-safety, ingress2gateway-second-opinion (cross-authority cross-check), middleware-coverage (Traefik target only).
  - New `references/preflight-checks.md` documents the 6 cluster-side checks. Now target-aware.
  - New `references/report-template.md` — 18-section operator report template.
  - Runbook template expanded with phase-by-phase SLI-based soak criteria, ManagedCertificate provisioning waits, target-aware Phase 0.3 install steps (helm install Traefik vs gcloud `--gateway-api=standard`).
  - State YAML schema bumped to v2: adds `skillVersion`, `targetGatewayClass`, `targetFamily`, `gitSha`, `runId`, `backups[]` (full file contents — fixes a v1.0 rollback bug), `cutover[]`, `validatorOutput`, per-step started/finished timestamps.
- **release-validate is now actively used as a release gate.** This release was validated by it and it caught two real bugs (see Fixed below).

### Fixed

- **gateway-api-migration: rollback-from-SHA256 was unrecoverable.** Phase 3B claimed to back up `kustomization.yaml` via SHA256 hash and restore on build failure — but a hash is one-way; the script could not actually reconstruct content. Now backs up full file content under `docs/reports/gateway-migration/<slug>/backups/`. The hash is kept for tamper detection only.
- **gateway-api-migration: Step 3A declared an HTTP listener on port 80 but never generated the redirect HTTPRoute.** Result: generated Gateways would silently drop port-80 traffic. Now generates a `tls-redirect` HTTPRoute attached to every `http-*` listener with a `RequestRedirect` filter.
- **gateway-api-migration: row 9c path-denylist regex `_LOCATION_DENY_RE` missed `location ~ ... { deny all; return 404; }` blocks** because it required `{` to be followed immediately by whitespace and then `return 404`, which excluded the common case of `deny all;` between them. Six manual-review items were silently dropped per run. Regex updated to `[^}]*?return\s+404` and `search()` replaced with `findall()` so each location block becomes its own report entry.
- **gateway-api-migration: validator's `source-hostname-coverage` and `tls-secret-coverage` falsely flagged orphan hostnames as missing.** Validator now computes the *active* hostname set (master ∩ minions) and only requires coverage for those.
- **gateway-api-migration: validator's `path-coverage` failed on `pathType: ImplementationSpecific` with path `/`.** This is a common nginx-ingress pattern that's semantically equivalent to `PathPrefix /` in Gateway API. Validator now applies the documented normalization rule and only fails on non-trivial `ImplementationSpecific` paths that genuinely require manual review.
- **gateway-api-migration: `check_cluster_preflight.sh` confused "Cloud IAM 403 Forbidden" with "resource missing"**, so a user without `roles/container.viewer` would be told to "install Traefik" or "create namespaces" when the real fix is an IAM grant. New `kubectl_probe()` wrapper classifies kubectl results into `ok` / `forbidden` / `missing` / `error`. Forbidden cases now produce `CANNOT VERIFY — Cloud IAM denies ...` messages with explicit IAM remediation. Discovered by running the preflight against a real production-adjacent cluster.
- **gateway-api-migration: runbook Phase 0.4 forgot to include the master's own namespace in the `kubectl label namespace` command.** The `tls-redirect` HTTPRoute lives in `ingress-nginx` (the Gateway's namespace), so without that label the redirect HTTPRoute would silently fail to attach and port-80 traffic would be dropped. Master namespace is now the first entry in the label list, plus a verification `for` loop.
- **release: npm pack tarball leaked Python `__pycache__/*.cpython-<ver>.pyc` files.** Adding Python scripts to a skill triggers ad-hoc bytecode generation; `.gitignore` correctly excluded them but `pnpm pack` doesn't read `.gitignore`. New `.npmignore` excludes `__pycache__/`, `*.pyc`, `*.pyo`, `*.tgz`, OS clutter. Tarball file count dropped from 150 to 148, and the 2 `.pyc` files (cpython-3.14 specific, useless for users on any other Python version) no longer ship.
- **release: 9 platform-facing files described `*gateway-migrate` as "GKE Gateway API"-only.** The v1.2.0 Traefik retrofit was applied to `SKILL.md` / scripts / references but never propagated to the platform descriptions. Updated 16 stale references across `AGENTS.md`, `GEMINI.md`, `README.md`, `docs/PROJECT.md`, `.claude/agents/zeus.md`, `.gemini/agents/zeus.md`, `commands/gateway-api-migration.md`, `commands/zeus.md`, and `.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml`. All 9 files now mention Traefik default + GKE opt-in. Caught by `release-validate` Phase 2.

### Changed

- `gateway-api-migration` skill internal version bumped 1.0.0 → 1.1.0 → **1.2.0**.
- `check_cluster_preflight.sh` script version 1.1.0 → **1.2.1**, added `--gateway-class` and `--context` flags. The `--context` flag scopes kubectl probes to a named context for one run only — never modifies the user's global current-context setting.
- `references/master-minion-topology.md` adds a new section "Classify rendered output, not raw files".
- The skill's "never surprise the user" principle expanded from 4 to 5 invariants. New invariant 5: "Dual-target without magic — switching targets is a one-argument change, no separate pipelines."

## [1.8.0] - 2026-04-14

### Added

- 新增 `/devops:gateway-api-migration` 斜線指令 — 直接進入 Gateway API
  migration pipeline 的捷徑，無需先呼叫 `/devops:zeus` 再下 `*gateway-migrate`。
  Silently 套用 Zeus 的 Critical Rules 與 Error Recovery，跳過問候與
  `*help` 選單，直接執行 `prompts/zeus/gateway-migrate.md`。
- `commands/zeus.md` 在 Skills 表格與新增的「Direct skill entry points」
  區段交叉連結至新指令，明確兩條入口共用同一 pipeline 與 skill。

### Fixed

- **Claude Code 重複註冊**：`scripts/install-global.sh` 過去同時做
  「直接複製到 `~/.claude/{skills,agents,prompts}/`」與「plugin 快取
  註冊」兩條路徑，造成每個 devops skill/agent 同時以裸名與 `devops:`
  命名空間出現兩次（10 個 skill + 2 個 agent + 3 個 prompts 目錄受影響）。
  改為 plugin-only 模式，並新增 `_claude_purge_legacy_direct_install()`
  在每次安裝時清除舊有副本，讓既有使用者升級時自動修復。

## [1.7.0] - 2026-04-13

### Added
- **Zeus:** `*gateway-migrate` pipeline and `gateway-api-migration` skill
  for migrating NGINX Ingress (master/minion or standalone) to GKE Gateway API
- **docs/gateway/**: 7 canonical reference files (annotation-map,
  master-minion-topology, gke-gateway-notes, http-routing-guide,
  ingress2gateway-integration, migrate-from-ingress, ingress-nginx-welcome)
- **tests/gateway-api-migration/**: 8 structural fixtures covering
  standalone and master/minion topologies
- Optional `ingress2gateway` tool integration for second-opinion diffs
- `scripts/install-tools.sh` now installs `ingress2gateway` as an optional
  tool on macOS (brew) and Linux (go install)

### Changed
- `docs/gateway/welcom-Ingress-NGINX.md` renamed to `ingress-nginx-welcome.md`
  (typo fix); content rewritten for project-facing use
- `docs/gateway/migrate-from-ingress.md` rewritten to remove marketing
  sections and focus on the concepts `*gateway-migrate` depends on

### Technical
- First Zeus skill to perform idempotent in-place edits
  (`common.service/overlays/<env>/kustomization.yaml`)
- Introduces resumable YAML state files for long-running migrations

## [1.6.0] - 2026-04-07

### Added

- 新增 `release-validate` 共用技能 — 發佈就緒驗證（版本一致性、跨平台連結完整性、setup 腳本煙霧測試）
- 新增「Shared Skills」分類於 PROJECT.md 與 AGENTS.md

### Changed

- 作者由 Awoo Platform Team 更新為 alexhsieh（plugin.json、marketplace.json、package.json）
- 技能總數由 8 更新為 9（全部 README、setup.md、setup.sh、測試）
- 測試斷言更新至 9 skills（test-structure.sh、test-setup-scripts.sh）

## [1.5.0] - 2026-04-03

### Added

- `commands/` 目錄：新增 `horus.md` 與 `zeus.md` 斜線指令定義，支援 `/devops:horus` (plugin) 與 `/devops-horus` (setup.sh) 兩種呼叫方式
- `setup.sh` 新增 `.claude/commands/` symlink 安裝與卸載邏輯
- `setup.sh` CLAUDE.md 模板補上 `/devops-horus` 與 `/devops-zeus` slash command 提示
- 四平台 agent 啟動指令、指令表與 `*help` 定義
- Section 16 跨平台指令名稱一致性結構測試

### Fixed

- `commands/{horus,zeus}.md` agent 路徑統一為 `.claude/agents/`，相容 plugin 與 symlink 兩種安裝模式
- `install-global.sh` 補齊 prompts 複製，四平台新增 shared-help workflow

## [1.4.1] - 2026-04-01

### Fixed

- `setup.sh` git clone 安裝方式的 CLAUDE.md 區段缺少 Zeus 指令表（僅列出 Horus 7 條指令）
  - 新增 Zeus Commands 表格（`*full`, `*pre-merge`, `*health`, `*review`, `*scaffold`, `*diagram`, `*status`）
  - 將原 Commands 標題改為 Horus Commands / Zeus Commands 雙表格格式
- `*full` pipeline 所需的 `docs/reports/` 目錄不存在，新增 `.gitkeep` 確保 git clone 後目錄可用
- Zeus `*diagram` pipeline 所需的 `docs/diagrams/` 目錄不存在，新增 `.gitkeep`

## [1.4.0] - 2026-03-23

### Added

- 5-minute quick start guide (`docs/quick-start.md`) — beginner-friendly 5-step onboarding
- Multi-language quick start: `quick-start.zh-TW.md`, `quick-start.zh-CN.md`
- `docs/guide/` directory for tutorial screenshots (placeholder)
- `npx skills` comparison table showing Skills-only vs Global Install feature gap
- CHANGELOG entry for v1.4.0

### Fixed

- Codex 全域安裝缺少 agents 與 prompts，導致 `*full-pipeline` 找不到 pipeline 定義
  - `install_codex()` 新增 agents、prompts 複製，並擴充 `instructions.md` 內容
  - 同步更新 uninstall 與 status 函式
- 全域安裝選項文件僅列出 `--claude`、`--gemini`，補齊 `--codex`、`--antigravity`
- Quick start Step 2 僅顯示 `claude`，補齊四平台 AI CLI 啟動指令

### Changed

- **BREAKING: Pipeline command alignment** — unified command names across Horus and Zeus:
  - Horus `*new-module` → `*scaffold` (file: `prompts/horus/scaffold.md`)
  - Zeus `*health-check` → `*health` (file: `prompts/zeus/health.md`)
  - Zeus `*onboard` → `*scaffold` (file: `prompts/zeus/scaffold.md`)
  - Gemini TOML commands renamed accordingly (`horus-scaffold`, `zeus-health`, `zeus-scaffold`)
- README.md default language switched from 繁體中文 to English
- README split into 3 separate language files: `README.md` (EN), `docs/README.zh-TW.md`, `docs/README.zh-CN.md`
- Quick start split into 3 separate language files matching README structure
- Updated all cross-references across 27+ files (agents, skills, scripts, tests, docs)
- All 284 structure tests pass with renamed pipelines

## [1.3.0] - 2026-03-17

### Added

- Zeus full-pipeline 新增 Step 0（Discover Kustomize Root），與 Horus Step 0 對齊
- Zeus full-pipeline 新增完整 Per-Step YAML Schema（discovery/exec/read 三種類型模板）
- Zeus discovery schema 包含 `kustomize_roots[]`、`argocd_apps_found`、`total_roots` 欄位
- `report-format.md` 新增 Zeus-Specific Fields 區塊（validation/security/read）

### Fixed

- Gemini TOML `zeus-full.toml` 同步為 Step 0-8（原為舊版 10 步驟，與 pipeline 不符）
- Gemini TOML `horus-full.toml` 同步為 Step 0-9（原為舊版 10 步驟，與 pipeline 不符）

### Changed

- Zeus full-pipeline 步驟編號從 1-based 改為 0-based（Step 0-8），與 Horus 一致
- Zeus full-pipeline 標題改為 "Full Pipeline Check (with Report)"，與 Horus 命名一致
- Zeus/Horus Report Rules 去重，改為指向 `prompts/shared/report-format.md`
- `report-format.md` 重構 Type-Specific Fields，明確區分 Horus/Zeus 專屬欄位

## [1.2.0] - 2026-03-16

### Added

- 全域安裝腳本 `install-global.sh`：一次安裝至 `~/.claude/`、`~/.codex/`、`~/.gemini/`、`~/.agents/`
- 統一安裝腳本 `setup.sh`：支援一鍵安裝至目標專案（per-repo symlinks）
- Gemini CLI 命令面板支援：18 個 TOML 檔（`.gemini/commands/devops/`）
- Antigravity 工作流全域安裝：17 個 pipeline 檔案複製至 `~/.agents/workflows/`
- Gemini extensions 全域安裝（`~/.gemini/extensions/devops/`）
- 新增 22 項 Gemini commands TOML 結構測試

### Fixed

- 修正 Gemini 全域安裝 skills 缺失（移除不存在的 `gemini skills link` 指令）
- 修正 `|| true` 導致 fallback 永遠不觸發的 bash bug
- 修正 `$DO_VAR && func || true` 隱藏錯誤，改用 `if/then`
- 修正 Gemini/Antigravity skills 衝突：Antigravity 自動清除與 `~/.gemini/skills/` 重複的 skill
- 修正 docs 中所有 `devops-go` 錯字為 `devops-ai-skill`
- 移除所有文件中不存在的 `gemini skills link` 引用

### Changed

- README 三語平台支援表重構：新增命令面板、工作流、全域路徑欄位
- README 安裝方式改為全域安裝優先（per-repo 改為 legacy）
- 專案結構樹新增 `.gemini/commands/devops/` 目錄

## [1.1.0] - 2026-03-10

### Added

- npm 套件包含完整 agent 定義檔（`.claude/agents/`、`.gemini/agents/`）
- npm 套件包含平台設定檔（`.claude-plugin/`、`.codex/`、`.gemini/extensions/`）
- npm 套件包含 `docs/`、`CHANGELOG.md`
- postinstall 自動複製 agents、prompts、entry files 至專案根目錄
- README 新增 npm version 與 GitHub Release 動態徽章
- CHANGELOG 底部加入 Keep a Changelog 標準比較連結
- `version-bump.sh` 自動建立 CHANGELOG 條目與版本比較連結
- `release.sh` 發版前驗證 CHANGELOG 條目存在
- `release.yml` 自動附加 npm/tag/changelog 交叉連結至 GitHub Release

## [1.0.0] - 2026-03-09

### Added

- Cross-platform DevOps AI Skill Pack
- **Horus** IaC Operations Engineer agent (Terraform + Helm + GKE)
- **Zeus** GitOps Engineer agent (Kustomize + ArgoCD)
- 8 shared skills following Open Agent Skills standard (SKILL.md)
  - terraform-validate, terraform-security, helm-version-upgrade, helm-scaffold
  - cicd-enhancer, kustomize-resource-validation, yaml-fix-suggestions, repo-detect
- 14 pipeline definitions in `prompts/` (7 Horus + 7 Zeus)
- Platform support: Claude Code, OpenAI Codex CLI, Google Gemini CLI
- Platform entry points: CLAUDE.md, AGENTS.md, GEMINI.md
- Setup scripts for each platform (`scripts/setup/`)
- Claude Code marketplace compatibility (`.claude-plugin/`)
- Cross-platform version check (`scripts/version-check.sh`)
- Tool installer (`scripts/install-tools.sh`)
- Bilingual documentation (EN + 繁體中文)

<!-- Links -->
[1.12.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.10.0...v1.11.0
[1.10.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/qwedsazxc78/devops-ai-skill/releases/tag/v1.0.0
