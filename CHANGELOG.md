# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **`--uninstall` / `--status` orphaned newer skills & workflows (stale hardcoded lists)** — `install-global.sh` and `install-global.ps1` enumerated a frozen 10-skill / 19-workflow list, so everything added since (7 skills incl. `ingress-controller-install`, `nginx-to-traefik`, `painter`, `traefik-controller-decommission`; 8 `zeus-*` migration workflows) was never removed on uninstall and not shown by status. Both now discover skills from `skills/` and workflows from `prompts/` dynamically, so the lists never go stale. Verified: `--all` install (17 skills + 27 workflows) followed by `--uninstall` now leaves **0** leftovers.

- **Windows installer was completely broken (worked only on macOS/Linux)** — `scripts\install-global.ps1` aborted on the very first line of its body with *"Parameter set cannot be resolved using the specified named parameters."* on Windows PowerShell 5.1. Cause: `Split-Path -Parent -LiteralPath` is an ambiguous parameter set in 5.1 (`-Parent` and `-LiteralPath` live in different sets). Dropped the redundant `-Parent` (it is the default) in all 4 call sites; verified install / update / `-Status` / `-Help` / `-Uninstall` / `-All` all run clean (exit 0). The `.sh` path was unaffected, which is why the pack appeared to "only work on Mac".
- **Docs: `install-tools.ps1` invocations failed under default execution policy** — README showed bare `.\scripts\install-tools.ps1`, which throws *"running scripts is disabled on this system"* under the default `Restricted` policy. Switched to the `powershell -ExecutionPolicy Bypass -File ...` form (consistent with the `install-global.ps1` examples) and added an execution-policy / no-admin (no UAC) note. Per-user installs never require elevation.

## [1.17.1] - 2026-06-11

### Added

- **`*retire-nginx` Zeus command** — `prompts/zeus/retire-nginx.md` pipeline wrapper + `.gemini/commands/devops/pipelines/zeus-retire-nginx.toml`, wiring the v1.17.0 `nginx-ingress-retire` skill into the Zeus command set (CLAUDE.md, `commands/zeus.md`, `.claude/agents/zeus.md`)
- **Architecture diagrams for the migration skill family** — Mermaid + Painter-HTML for nginx-ingress-retire, nginx-to-traefik, gateway-api-migration, nginx-to-gateway, ingress-migration-advisor, traefik-controller-decommission under `docs/diagrams/`, plus a mindmap HTML explainer for `nginx-ingress-retire`

### Changed

- **Migration runbook updated for the retirement era** — `*migration-quickstart` now
  shows cluster state **S4 (nginx retired)**, the 8-command table (was labeled "five"
  with 7 rows), `*retire-nginx` in the decision tree / per-state recommendations /
  Mermaid, and a v1.17.0 banner; Gemini TOML mirror synced. `migration-journey.md`
  diagram gains the `*retire-nginx` terminal transition and a completion note
  (reference deployment retired nginx 2026-06-05, CTS-9828).
  `traefik-gateway-migration-plan.md` status: Draft → Implemented & completed.

### Fixed

- **v1.17.0 registration gap** — `nginx-ingress-retire` shipped without cross-platform registration; now listed in README (EN/zh-TW/zh-CN, badges 16→17 skills / 22→23 pipelines), `docs/PROJECT.md`, `AGENTS.md`, `GEMINI.md`, and `gemini-extension.json`
- **Version desync** — `package.json`, `plugin.json`, `marketplace.json`, `gemini-extension.json` were left at 1.16.0 by the v1.17.0 release (`version-bump.sh` reads OLD_VERSION from the already-bumped `VERSION` file, so its `sed` silently matched nothing); all four resynced to 1.17.0

## [1.17.0] - 2026-06-05

### Added

- **`nginx-ingress-retire` skill v1.17.0** — new post-migration cleanup skill for retiring the nginx ingress controller and all nginx Ingress resources from a Kustomize + ArgoCD repo after Gateway API / Traefik migration is complete.
  - Supports single-env (`dev`/`stg`/`prd`) or all-envs retirement in one command (`retire-nginx all`)
  - **Safety gates**: hard-abort if no HTTPRoute/Traefik Ingresses found (migration not done); warns on active nginx patches still in `patches:` section
  - **Correct validation**: checks `ingress.class: nginx` count = 0, not total `kind: Ingress` count — envs with Traefik ingresses legitimately retain `kind: Ingress` resources after retirement
  - **Dynamic discovery via `kustomize build`**: uses `kustomize build common.service/base` + awk to extract exact `metadata.name` / `metadata.namespace` — file names don't always match resource names
  - **Per-env ingress breakdown**: pre-flight shows nginx vs Traefik vs HTTPRoute counts before any action
  - **$patch: delete pattern**: excludes base nginx Ingress resources per-env in the overlay kustomization — base files stay intact for other envs still using them
  - **All-env cleanup check**: after `retire-nginx all`, detects when `common.ingress/` module is fully orphaned and offers to archive or delete the entire module
  - **Class-override patch detection (Step 2c / Step 5c)**: base nginx Ingress resources patched by an env overlay to a different ingress class (e.g., `ingress.class: gce` for GCE external LB) are detected via rendered manifest cross-check and excluded from `$patch: delete`. Only the file is renamed for semantic clarity; `metadata.name` stays unchanged to avoid cloud LB reprovisioning. Documents Kustomize constraint: cannot combine `$patch: delete` with a same-name standalone resource — duplicate ID error occurs at accumulation phase, before patches run.
  - Sourced from live retirement of `eye-of-horus-gitops` dev + stg + prd environments (CTS-9828, 2026-06-05)

## [1.16.0] - 2026-06-01

### Added

- **`*diagram` pipeline** (`prompts/zeus/diagram.md`) rewired as a thin recipe layer over `devops:painter`. Three ready-made recipes with dual-format output:
  - **Zeus (GitOps)** — `common.service/base + overlays` → ArgoCD `Application` → GKE, with `common.traefik` controller / `common.service` data-plane split
  - **Horus (IaC)** — Terraform modules + Helm releases → ArtifactHub version discovery → GKE
  - **Migration** — S0→S3 ingress-nginx → Traefik → Gateway API state journey (7 Zeus commands)
- **3 sample diagrams × 2 formats** shipped as static committed artifacts:
  - Mermaid (`.md`) — renders inline on GitHub; `flowchart` for Zeus/Horus, `stateDiagram-v2` for Migration
  - Painter HTML (`detailed`) — overview page + 4 clickable drill-down pages per diagram (12 detail pages total); blue-white palette, card UI, SVG arrows, dark code blocks, `← Back to overview` links
- **`docs/diagrams/README.md`** — gallery index linking all Mermaid + HTML overviews with a format comparison table
- **`docs/diagrams-guide.md`** — usage guide: `*diagram` vs `devops:painter` decision table, 3 recipes, params (`--level`/`--output`/`--parallel`), dual-format output paths, regenerate instructions
- **`gateway-api-migration` skill v1.16.0 (sourced from CTS-9681 live migration, 2026-05-28)** — five enrichments lifted from a 15-host Traefik-source migration across 2 repos and 3 environments:
  - **SE1 — Traefik source annotation classification.** `scripts/inventory_annotations.py` now recognises 6 `traefik.ingress.kubernetes.io/*` annotations (T1–T6) and adds a new `translatedByCoexistence` bucket alongside `translated`/`translatedLossy`/`stubbed`/`unknown`/`dropInfo`. The `router.middlewares` annotation (the most common case) was previously bucketed as `unknown` and surfaced as S1 risk; it now classifies correctly as `translated-by-coexistence` with S2 risk.
  - **SE2 — Cross-repo HTTPRoute handoff (new Step 7b in SKILL.md).** When a service's backend lives in a separate GitOps repo, the HTTPRoute is emitted into that repo's `overlays/<env>/httproute.yaml` rather than `common.service/`. `state.yaml.crossRepo[]` records the handoff. The Gateway listener uses `allowedRoutes.namespaces.from: All` so the cross-repo HTTPRoute attaches.
  - **SE3 — Multi-env staged activation (new Step 7d).** `--activation-env <env>` (default `dev`) controls which environment is wired up immediately; other envs get files on disk plus commented-out `kustomization.yaml` entries with activation hints. Prevents ArgoCD sync failures when `kubernetesGateway` isn't enabled in stg/prd Traefik instances.
  - **SE4 — TLS-only host detection.** `scripts/classify_ingress.py` emits a new `tlsOnly: true` flag when an Ingress declares hosts + TLS refs but has no `http.paths`. Lets the operator decide alias / skip / abort at Step 1 instead of getting a silent orphan-host warning later.
  - **SE5 — DNS cutover script alignment (new Step 7c).** After generation, the skill globs `scripts/dns-*.sh` and reports any new hostnames that aren't yet listed in the appropriate DNS batch. Emits a diff snippet; optional `--update-dns` flag to apply.
  - **`docs/gateway/annotation-map.md`** — "Traefik source annotations" section expanded from a 4-row table to a 6-row classification matrix + a "Middleware coexistence" subsection documenting the three resolutions (keep-as-is / per-namespace copies / ReferenceGrant) + a "Bucket: translatedByCoexistence" subsection documenting the new output schema.

### Changed

- **README** (EN / zh-TW / zh-CN) — ASCII migration block replaced with Mermaid `stateDiagram-v2`; new **Architecture Diagrams** section links the gallery and diagrams-guide
- **GitHub repo description** — updated to include Antigravity platform and diagram/painter capability; `gateway-api` topic added
- **`gateway-api-migration` skill** — cert-manager annotation correction (sourced from live POC 2026-05-27):
  - `docs/gateway/annotation-map.md` row 2: `cert-manager.io/cluster-issuer` Traefik action changed from **drop-info → migrate to Gateway annotation**. The annotation is moved from the source Ingress to `Gateway.metadata.annotations`; cert-manager v1.15+ gateway-shim auto-creates/renews the Certificate CR from it.
  - `docs/gateway/traefik-gateway-notes.md` cert-manager section rewritten: documents the preferred Gateway annotation pattern (v1.15+, auto-rotation, no explicit Certificate CR) and the explicit Certificate CR fallback (pre-v1.15).
- **`gateway-api-migration` skill** — `docs/gateway/traefik-gateway-notes.md` + `skills/gateway-api-migration/references/preflight-checks.md`: add Kustomize `helmCharts: valuesInline` deployment pattern (eye-of-horus-gitops style).
  - New section "Kustomize-managed Traefik (helmCharts: valuesInline pattern)" documents the `gatewayClass.enabled + providers.kubernetesGateway.enabled` valuesInline approach and the critical rule: **never add a standalone `GatewayClass` to kustomize `resources:` when the chart generates it** — doing so causes `"id exists; can not use behavior: 'unspecified'"` merge conflict.
  - Documents the chart-generated `traefik-gateway` default Gateway (port 8000, web entrypoint) as expected and non-conflicting with migration Gateways.
  - Check 3 in `preflight-checks.md` now includes a Kustomize fix path alongside the existing `helm install --set` path.
  - Sourced from live POC: `common.traefik/overlays/dev/app.dashboard-gateway.yaml` migration on 2026-05-27.

## [1.15.1] - 2026-05-20

### Changed

- **Two-tier command architecture** — Reduced `/devops` command palette from 17 to 12 entries by converting 5 Horus-internal skills to `GUIDE.md` (hidden from plugin discovery). Migration/Ingress/Traefik skills retain `SKILL.md` for natural-language triggering.
  - Converted to `GUIDE.md` (Horus agent reads via `Read`): `terraform-validate`, `terraform-security`, `helm-scaffold`, `cicd-enhancer`, `repo-detect`
  - Horus pipeline files (`validate.md`, `scaffold.md`, `cicd.md`, `upgrade.md`, `security.md`, `health.md`) updated to reference `GUIDE.md` paths
  - `horus.md` agent definition updated: new **Internal Guides** table distinguishes agent-only guides from user-visible skills

### Documentation

- README (EN / zh-TW / zh-CN): Skills section restructured into **User-Visible Skills** and **Horus Internal Guides** tables; badge updated `SKILLS-12 → SKILLS-10`
- `docs/PROJECT.md`: Horus Skills section split into Skills (user-visible) and Internal Guides

## [1.15.0] - 2026-05-19

### Added

- **`release-validate` skill v1.15.0** — two new pre-release gates and a top-level orchestrator:
  - **Phase 6 — Cross-repo-style coverage check.** `scripts/check_repo_style_coverage.sh` reads `references/repo-style-matrix.md` (a plain markdown table declaring per-skill style requirements) and reports gaps. WARN-only. Pre-v1.15.0 fixtures count as `kustomize-argocd`-style by convention; other styles require directory names containing the style keyword (e.g. `helm-only-basic`).
  - **Phase 7 — Cross-AI-tool registration parity check.** `scripts/check_ai_tool_parity.sh` verifies that every Zeus command appears in all 4 surfaces (CLAUDE.md / AGENTS.md / GEMINI.md / docs/PROJECT.md) + has a Gemini TOML mirror. FAIL on any gap — strengthens the existing Phase 2 (file-reference validation) with command-registration validation.
  - **`scripts/release_check.sh` orchestrator + `pnpm release:check`** — runs Phases 4 + 5 + 6 + 7, writes per-phase JSON under `docs/reports/release-validate/<version>/`, and invokes the renderer for `RELEASE-CHECK.md`. Used by both operators and CI.
  - **CI integration** — `.github/workflows/release.yml` runs `scripts/release_check.sh` after the existing structure-test step and uploads `docs/reports/release-validate/` as a workflow artifact (`release-check-<tag>`).
- 4 new fixture tests under `tests/release-validate/fixtures/` covering Phase 6 + 7 happy / failure paths (plus a name-mismatch resolution test for Phase 7).

## [1.14.0] - 2026-05-19

### Added

- **`release-validate` skill v1.14.0** — three new phases that complete the pre-release safety net:
  - **Phase 4 — Skill fixture suite runs.** New `scripts/run_all_fixtures.sh` iterates every `tests/*/run-fixtures.sh`, captures per-suite PASS / FAIL counts, and emits aggregated JSON. Fail-fast on any suite returning non-zero. Catches regressions that the structure test (file-existence) cannot detect.
  - **Phase 5 — Shell portability static checks.** New `scripts/check_shell_portability.sh` lints every `.sh` under `skills/` and `scripts/` against five cross-OS rules: portable shebang (WARN), `declare -A` bash 3.2 incompatibility (ERROR), `mapfile`/`readarray` bash 4+ (ERROR), `sed -i` BSD/GNU divergence (WARN), `readlink -f` BSD incompatibility (WARN). Optional `shellcheck` integration when available. Would have caught the bash-3.2 `declare -A` bug fixed in v1.13.1.
  - **Phase 8 — Release artifact generation.** New `scripts/render_release_artifact.sh` aggregates Phase 4 + 5 (and existing Phases 1–3) outputs into `docs/reports/release-validate/<version>/RELEASE-CHECK.md`. The artifact is suitable verbatim as the body for `gh release create --notes-file` or as the npm publish README excerpt.
- 22 shell scripts under `skills/` + `scripts/` now pass the portability lint (`scanned=22, errors=0, warnings=0`).

### Smoke-test results (v1.14.0)

```
release-validate v1.14.0: PASS (fixtures=OK, portability=OK)

| Phase | Verdict | Detail                                              |
| 4. Fixture suites    | OK | 153 PASS / 0 FAIL across 6 suites          |
| 5. Shell portability | OK | 22 scripts scanned, 0 errors, 0 warnings  |
```

Per-suite Phase 4 breakdown:

| Suite | PASS | Verdict |
|---|---|---|
| gateway-api-migration | 135 | OK |
| ingress-controller-install | 3 | OK |
| ingress-migration-advisor | 4 | OK |
| nginx-to-gateway | 2 | OK |
| nginx-to-traefik | 4 | OK |
| traefik-controller-decommission | 5 | OK |

### Documentation

- README.md, docs/README.zh-{CN,TW}.md: skill / pipeline / TOML counts synced to v1.13.1 reality. README adds a "Migration journey at a glance" decision-tree subsection pointing operators at `*migration-quickstart`.
- docs/setup.md: `npx skills add` count corrected (12 → 15 skills; 17 → 22 pipelines).

## [1.13.1] - 2026-05-19

Patch release: corrects the agent placement of `*install-traefik` and
`*decommission-nginx` (v1.12.0 / v1.13.0 had them under Horus, which
ran `helm install` / `helm uninstall` directly — incompatible with
ArgoCD + Kustomize cluster setups). Relocated to Zeus and rewritten
for GitOps semantics. Both commands now operate on Kustomize files
under `common.traefik/` and `common.ingress-nginx/`, never invoke
`helm` directly, and emit `git` / `kubectl apply -f .../argocd/<env>.yaml`
for the operator. ArgoCD handles the actual helm install/uninstall.

Treated as a patch (not a minor) because v1.12.0 / v1.13.0 adoption is
very recent and the original placement was a design error rather than
shipped functionality — no consumer should have built around it yet.
Dry-run smoke-tested against eye-of-horus-gitops.

### Changed

- **`*install-traefik` relocated Horus → Zeus**, skill `ingress-controller-install` v1.13.1:
  - Three auto-detected modes: `bootstrap` (scaffold `common.traefik/{base,overlays/<env>,argocd}/`), `new-env` (copy an existing overlay), `upgrade` (atomic chart-version bump across base + every overlay with full-file backups).
  - Coexistence validation switched to read-only `kustomize build` inspection across `common.*/overlays/<env>/` (offline; no `kubectl` required).
  - Scripts: `detect_mode.sh`, `validate_coexistence_kustomize.sh`, `upgrade_chart_version.sh` (replace `detect_existing_install.sh` + `validate_coexistence.sh`).
- **`*decommission-nginx` relocated Horus → Zeus**, skill `traefik-controller-decommission` v1.13.1:
  - Discover the ingress-nginx Kustomize module via `discover_nginx_module.sh` (greps `helmCharts[].name == ingress-nginx`, walks up to the module root). HALT on zero / ambiguous matches.
  - Decommission plan rewritten as: archive Kustomize module → ArgoCD prunes resources → disable + delete the ArgoCD Application → optional GKE LB / IAM cleanup. No more `helm uninstall` command.
  - `verify_no_nginx_class.sh` (precedence-aware from v1.12.0/v1.13.0) unchanged — already GitOps-correct.
- **Quickstart decision tree** (`prompts/zeus/migration-quickstart.md`) re-labels both commands as Zeus.

### Added

- 2 Gemini TOML mirrors completing the relocation: `zeus-install-traefik.toml`, `zeus-decommission-nginx.toml`. (The v1.12.0 release had Horus pipelines without TOML mirrors; this patch completes them under Zeus.)
- Test fixtures rewritten for GitOps mode detection:
  - `tests/ingress-controller-install/fixtures/{bootstrap-empty-repo,new-env-needed,upgrade-existing}/` — exercise `detect_mode.sh`.
  - `tests/traefik-controller-decommission/fixtures/discover-single-module/` — exercises `discover_nginx_module.sh` happy path.

### Test infrastructure

- TOML command count 24 → 26 in `tests/test-structure.sh`. Full suite: 410 (structure) + 83 (setup) + 135 (gateway-api-migration) + 18 across the 5 skill fixture suites = 656 PASS, 0 FAIL.

### Smoke-test results (eye-of-horus-gitops, 2026-05-19)

| Script | Verdict |
|---|---|
| `detect_mode --target-env dev` | `mode=upgrade, currentChartVersion=39.0.8` |
| `detect_mode --target-env new-region` | `mode=new-env, currentChartVersion=39.0.8` |
| `discover_nginx_module` | `verdict=NONE` (ingress-nginx is not GitOps-managed in this repo — correct) |
| `verify_no_nginx_class --repo` | `verdict=BLOCKED, 6 overlays still have nginx-class Ingresses` |
| `validate_coexistence_kustomize --target-class traefik --mode upgrade` | `classCollision=false, lbIpCollision=false, portCollision=false` |

### Migration notes for v1.12.0 / v1.13.0 adopters

- Old paths under `prompts/horus/install-traefik-controller.md` and `prompts/horus/decommission-nginx-controller.md` are gone (moved to `prompts/zeus/`).
- State-file schemas unchanged (additive only). Existing reports under `docs/reports/ingress-controller-install/<date>/` and `docs/reports/traefik-controller-decommission/<date>/` from prior runs remain readable.
- The `install.sh` artifact is no longer produced; the Helm command lives inside Kustomize's `HelmChartInflationGenerator` block instead. The new `plan.md` contains the operator's `git` + `kubectl apply` recipe.

## [1.13.0] - 2026-05-19

### Added

- **Zeus command — `*migration-quickstart` (new pipeline, no new skill)**
  - 30-second orientation for first-time operators staring at the now-7 migration commands. Prints a decision tree (S0 → S1 → S2 → S3 cluster-state machine), the 5-command table with When-to-use, and nginx-first sample invocations. No questions, no scans, no state files.
  - Pipeline: `prompts/zeus/migration-quickstart.md` (~140 lines of static printout content).
  - Gemini TOML command: `zeus-migration-quickstart`.
  - Designed as a pure-documentation slash command — surfaces inline alongside the migration commands it describes so operators discover it via tab-completion rather than hunting docs pages.

### Fixed

- **`classify_ingress.py` precedence aligned with Kubernetes** (v1.12.0 carry-over). The classifier now reads `spec.ingressClassName` first and falls back to the legacy `kubernetes.io/ingress.class` annotation only when spec is absent — matching what the Kubernetes API server actually does. Previous behavior was annotation-first, which mis-classified mid-migration Ingresses where `spec.ingressClassName: traefik` had been set but the legacy annotation was still `nginx` (e.g., the in-flight state common to half-migrated services in eye-of-horus-gitops). Affects three downstream skills: `gateway-api-migration` (Step 1 classification), `nginx-to-gateway` (transitively), and `ingress-migration-advisor` (per-service path recommendations).
  - New regression test: `tests/gateway-api-migration/fixtures/spec-wins-over-annotation/` exercises the dual-annotated case. All existing fixtures across nginx-to-traefik, nginx-to-gateway, gateway-api-migration, ingress-migration-advisor, traefik-controller-decommission, and ingress-controller-install remain green (16 fixtures total).

### Test infrastructure

- TOML command count bumped 23 → 24 in `tests/test-structure.sh` for the new `zeus-migration-quickstart`. Full suite: 408 (structure) + 83 (setup) + 135 (gateway-api-migration) + 16 across the 5 new skill fixture suites = 642 PASS, 0 FAIL.

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
[1.15.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.14.0...v1.15.0
[1.14.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.13.0...v1.14.0
[1.13.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.12.0...v1.13.0
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
[1.15.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.14.0...v1.15.0
[1.14.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.13.1...v1.14.0
[1.13.1]: https://github.com/qwedsazxc78/devops-ai-skill/releases/tag/v1.13.1
[1.16.0]: https://github.com/qwedsazxc78/devops-ai-skill/compare/v1.15.1...v1.16.0
[1.15.1]: https://github.com/qwedsazxc78/devops-ai-skill/releases/tag/v1.15.1
