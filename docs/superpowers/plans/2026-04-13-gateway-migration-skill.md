# Gateway API Migration Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `*gateway-migrate`, a Zeus pipeline + `gateway-api-migration` skill that migrates NGINX master/minion Ingress topologies to GKE Gateway API resources with per-hostname DNS cutover, shipped as `devops-ai-skill` v1.7.0.

**Architecture:** One thick skill (`skills/gateway-api-migration/SKILL.md`) holds the authoritative logic; one thin pipeline (`prompts/zeus/gateway-migrate.md`) wraps it as an 8-step gate checklist. Reference material for the skill lives in `docs/gateway/` (canonical, human-facing) and is inline-copied to `skills/gateway-api-migration/references/`. The skill detects master/minion topology (primary) or standalone Ingress (fallback), emits a Gateway in a new `common.gateway/` module plus HTTPRoutes alongside existing minions in `common.service/`, and records progress in a resumable YAML state file.

**Tech Stack:** Bash shell scripting, Markdown (skill definitions), YAML (Kubernetes manifests, state files, Gemini TOML), pnpm (package manager), Kustomize, `yq` (in-place YAML edits), GKE Gateway API (`gateway.networking.k8s.io/v1`), `ingress2gateway` (optional second-opinion).

**Spec:** `docs/superpowers/specs/2026-04-13-gateway-migration-skill-design.md` (commit `0e6366d`). The spec is the authoritative content source — many tasks below reference specific sections to avoid duplication.

---

## File Structure

### New files

```
docs/gateway/
  annotation-map.md                            Canonical annotation translation table (from spec §5)
  master-minion-topology.md                    Detection rules, classification heuristics
  gke-gateway-notes.md                         GKE GatewayClasses, policies, ManagedCertificate
  http-routing-guide.md                        HTTPRoute reference (distilled from upstream)
  ingress2gateway-integration.md               Second-opinion tool facts

skills/gateway-api-migration/
  SKILL.md                                     Authoritative skill (8 pipeline sections)
  references/
    annotation-map.md                          Symlink to docs/gateway/annotation-map.md
    master-minion-topology.md                  Symlink
    gke-gateway-notes.md                       Symlink
    http-routing-guide.md                      Symlink
    ingress2gateway-integration.md             Symlink
    migration-from-ingress.md                  Symlink to docs/gateway/migrate-from-ingress.md
    ingress-nginx-welcome.md                   Symlink to docs/gateway/ingress-nginx-welcome.md
    manual-review-patterns.md                  Server-snippet / mergeable-ingress deep guidance
    runbook-template.md                        Template for generated common.gateway/MIGRATION.md
    httproute-template.yaml                    HTTPRoute skeleton the skill fills in per minion

prompts/zeus/
  gateway-migrate.md                           Thin 8-step pipeline

.gemini/commands/devops/pipelines/
  zeus-gateway-migrate.toml                    Gemini TOML command entry

tests/gateway-api-migration/
  fixtures/
    standalone-simple/                         Fixture: single Ingress, baseline
      input/app.ingress.yaml
      input/app.service.yaml
      expected/common.gateway/base/gateway.yaml
      expected/common.gateway/base/httproute.yaml
      expected/common.gateway/base/kustomization.yaml
    standalone-cors/                           Fixture: CORS annotations → GCPBackendPolicy
      input/app.ingress.yaml
      expected/common.gateway/base/gateway.yaml
      expected/common.gateway/base/httproute.yaml
      expected/common.gateway/base/gcpbackendpolicy.yaml
    standalone-server-snippet/                 Fixture: row 9a/b/c split
      input/app.ingress.yaml
      expected/common.gateway/base/httproute.yaml
    master-minion-minimal/                     Fixture: 2-service master/minion
      input/common.ingress/base/app.ingress.yaml
      input/common.service/overlays/dev/argocd-nginx-ingress.yaml
      input/common.service/overlays/dev/grafana-nginx-ingress.yaml
      input/common.service/overlays/dev/kustomization.yaml
      expected/common.gateway/base/gateway.yaml
      expected/common.service/overlays/dev/argocd-httproute.yaml
      expected/common.service/overlays/dev/grafana-httproute.yaml
      expected/common.service/overlays/dev/kustomization.yaml
    master-minion-orphan-host/                 Fixture: master declares host with no minion
    master-minion-orphan-minion/               Fixture: minion with no master (error expected)
    mergeable-master/                          Fixture: master with mergeable-ingress-type annotation
    eye-of-horus-sample/                       Trimmed copy of the real reference repo
  run-fixtures.sh                              Structural validator (asserts files exist + valid YAML)
  README.md                                    How to use fixtures
```

### Modified files

```
docs/PROJECT.md                                Add skill row + *gateway-migrate row to Zeus tables
CLAUDE.md                                      Add *gateway-migrate to Zeus commands table
AGENTS.md                                      Same
GEMINI.md                                      Same
tests/test-structure.sh                        Add section for gateway-api-migration checks
package.json                                   Bump version to 1.7.0
VERSION                                        Bump to 1.7.0
.claude-plugin/plugin.json                     Bump version
.claude-plugin/marketplace.json                Bump version
.gemini/extensions/devops/gemini-extension.json Bump version
scripts/setup/setup-antigravity.sh             Add /zeus-gateway-migrate workflow symlink (if applicable)
scripts/install-tools.sh                       Add ingress2gateway as optional tool
```

### Files touched but untracked pre-existing (from the user's local state)

```
docs/gateway/migrate-from-ingress.md           Rewrite in place (was raw scrape)
docs/gateway/welcom-Ingress-NGINX.md           DELETE (typo'd filename)
docs/gateway/ingress-nginx-welcome.md          CREATE with rewritten content
```

---

## Phase 1 — Reference Documentation (docs/gateway/)

This phase builds the canonical knowledge base. Every later task references these files. Tasks run in dependency order — annotation-map.md first because the skill's logic depends on it.

### Task 1: Create canonical annotation translation table

**Files:**
- Create: `docs/gateway/annotation-map.md`

- [ ] **Step 1: Write the file**

Copy the translation table from spec §5 (commit `0e6366d`, lines defining "The canonical translation table"). The file should contain, in order:

1. H1 title: `# NGINX Ingress → GKE Gateway API Annotation Map`
2. One-paragraph preface: "Canonical translation table for `*gateway-migrate`. Each row represents a deterministic decision the converter makes every run. Single source of truth — the skill's `references/annotation-map.md` symlinks here."
3. The 13-row table from spec §5 verbatim, with columns: `# | Annotation | Category | GKE Gateway translation | Converter action`.
4. H2 `## Category definitions`:
   - **portable** — translates 1:1 with no information loss
   - **portable-GKE** — translates to a GKE-specific resource; not portable to other GatewayClasses
   - **convertible** — translates to a new kind of resource (e.g., `GCPBackendPolicy`)
   - **convertible-lossy** — translation drops information; WARN in report
   - **split-category (auto)** — part of the annotation auto-converts, part gets stubbed
   - **split-category (stub)** — cannot auto-convert; TODO stub with Manual Review entry
   - **drop-info** — annotation is obsolete under Gateway API; drop silently with an INFO record in state
5. H2 `## Row 9 detail: server-snippet split`:
   - Sub-section 9a: X-* headers → `responseHeaderModifier` (show the YAML template)
   - Sub-section 9b: `add_header Set-Cookie "..."` → stub with rationale
   - Sub-section 9c: `location ~ ... { return 404; }` → stub + Cloud Armor pointer
6. H2 `## Trade-offs called out in every report`: list the 3 trade-offs from spec §5.

Target length: ~250 lines.

- [ ] **Step 2: Verify the file**

Run: `head -20 docs/gateway/annotation-map.md && wc -l docs/gateway/annotation-map.md`
Expected: H1 title visible, line count between 200 and 320.

- [ ] **Step 3: Commit**

```bash
git add docs/gateway/annotation-map.md
git commit -m "docs(gateway): 新增註解轉換對應表（annotation-map）

提供 NGINX Ingress 到 GKE Gateway API 的 13 列標準轉換規則，
作為 gateway-api-migration skill 的唯一知識來源。包含
server-snippet 拆分處理（row 9a/b/c）與每份報告必須呈現的
trade-offs。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Create master/minion topology reference

**Files:**
- Create: `docs/gateway/master-minion-topology.md`

- [ ] **Step 1: Write the file**

Content sourced from spec §1 "Primary topology: master/minion across two modules" and §6.3 "Classification rules". Structure:

1. H1 `# Master/Minion Topology Detection`
2. Preface: one paragraph explaining the NGINX `mergeable-ingress-type` pattern and why it maps cleanly onto Gateway API's persona model.
3. H2 `## Classification rules` — reproduce the classification table from spec §6.3 verbatim.
4. H2 `## Pairing algorithm`:
   1. For each minion, take its `spec.rules[].host` values.
   2. Search all masters for a matching host (case-insensitive, exact match).
   3. If a minion's host matches exactly one master → pair them.
   4. If a minion's host matches zero masters → orphan minion (HALT).
   5. If a minion's host matches multiple masters → ambiguous (HALT).
   6. For each master host with no matching minion → orphan host (WARN, proceed).
5. H2 `## Worked example — eye-of-horus-gitops`:
   - Show the real master file path (`common.ingress/base/app.ingress.yaml`)
   - Show one real minion file path (`common.service/overlays/dev/argocd-nginx-ingress.yaml`)
   - Show the resulting pairing
6. H2 `## Standalone fallback` — one paragraph explaining what happens if no master is found.
7. H2 `## Cross-namespace parentRef requirements`:
   - Gateway lives in master's namespace (`ingress-nginx`).
   - HTTPRoutes live in each service's namespace (`argocd`, `monitoring`, etc.).
   - Gateway listener must set `allowedRoutes.namespaces.from: Selector`.
   - User must label target namespaces with `gateway-access=ingress-nginx` before HTTPRoutes attach.
   - No `ReferenceGrant` needed (backendRefs are same-namespace).

Target length: ~180 lines.

- [ ] **Step 2: Verify**

Run: `grep -c "^## " docs/gateway/master-minion-topology.md`
Expected: exactly 6 (H2 headers for Classification, Pairing, Worked example, Standalone, Cross-namespace).

- [ ] **Step 3: Commit**

```bash
git add docs/gateway/master-minion-topology.md
git commit -m "docs(gateway): 新增 master/minion 拓撲偵測指南

定義 gateway-api-migration skill 如何辨識 NGINX master/minion
分離拓撲，包含分類規則、配對演算法、eye-of-horus-gitops 實例
與跨 namespace parentRef 的前置條件。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Create GKE Gateway notes

**Files:**
- Create: `docs/gateway/gke-gateway-notes.md`

- [ ] **Step 1: Write the file**

Content sourced from GCP GKE Gateway documentation. Structure:

1. H1 `# GKE Gateway — Notes for `*gateway-migrate``
2. H2 `## GatewayClasses` — table of GKE GatewayClass names with descriptions:
   - `gke-l7-global-external-managed` — global external HTTP(S) load balancer (default target)
   - `gke-l7-regional-external-managed` — regional external LB
   - `gke-l7-rilb` — regional internal LB
   - `gke-l7-gxlb` — deprecated, do not use
3. H2 `## Policies (GKE extensions)`:
   - `GCPBackendPolicy` — CORS, IAP, Cloud Armor, timeouts, session affinity
   - `GCPGatewayPolicy` — SSL policies, region
   - `HealthCheckPolicy` — backend health checks
   - Attachment pattern: `targetRef` points at a Service (not a Route)
4. H2 `## ManagedCertificate integration`:
   - `networking.gke.io/v1 ManagedCertificate` resources are referenced from Gateway listeners via `certificateRefs[kind: ManagedCertificate]`.
   - Provision time: 15-60 minutes after DNS validation.
   - The skill preserves existing ManagedCertificate resources; it does not create new ones.
5. H2 `## cert-manager coexistence`:
   - cert-manager can issue `Certificate` resources that create Secrets, referenced from Gateway listeners via `certificateRefs[kind: Secret]`.
   - Your repo uses cert-manager + GKE ManagedCertificate in parallel; the skill preserves both.
6. H2 `## Required CRDs`:
   - Gateway API standard: `kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml`
   - GKE-specific CRDs are provisioned by the GKE add-on.
7. H2 `## Known limitations for v1`:
   - Per-hostname listeners scale linearly (see spec §12 risk 2)
   - No auto-generated Cloud Armor policies (spec §12 non-goal 5)

Target length: ~150 lines.

- [ ] **Step 2: Verify**

Run: `grep -c "^## " docs/gateway/gke-gateway-notes.md`
Expected: exactly 7.

- [ ] **Step 3: Commit**

```bash
git add docs/gateway/gke-gateway-notes.md
git commit -m "docs(gateway): 新增 GKE Gateway 運作筆記

整理 GKE Gateway 所使用的 GatewayClasses、GCPBackendPolicy 等
extension 資源、ManagedCertificate 與 cert-manager 並存的處理
方式，以及 gateway-api-migration skill 相依的 CRD 安裝步驟。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Create HTTPRoute guide (distilled from upstream)

**Files:**
- Create: `docs/gateway/http-routing-guide.md`

- [ ] **Step 1: Write the file**

Source: [gateway-api.sigs.k8s.io/guides/http-routing/](https://gateway-api.sigs.k8s.io/guides/http-routing/). Distill, don't copy — tailor to what `*gateway-migrate` actually generates.

Structure:

1. H1 `# HTTPRoute Reference`
2. H2 `## Anatomy of an HTTPRoute` — show the full skeleton with all fields commented:
   ```yaml
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: <svc>
     namespace: <svc-namespace>
   spec:
     parentRefs:                    # which Gateway listener to attach to
       - group: gateway.networking.k8s.io
         kind: Gateway
         name: common-gateway
         namespace: ingress-nginx
         sectionName: <listener-name>
     hostnames:                      # SNI / Host-header match
       - <hostname>
     rules:
       - matches:
           - path:
               type: PathPrefix      # Exact | PathPrefix | RegularExpression
               value: /
         filters:                    # optional: header rewrites, redirects, mirrors
           - type: ResponseHeaderModifier
             responseHeaderModifier:
               add:
                 - name: X-Frame-Options
                   value: SAMEORIGIN
         backendRefs:
           - name: <service-name>
             port: <port>
             weight: 1               # traffic splitting
   ```
3. H2 `## Path matching` — explain `PathPrefix` vs `Exact` vs `RegularExpression`, with Ingress equivalents.
4. H2 `## Header and query matching` — one example each.
5. H2 `## Filters used by *gateway-migrate`:
   - `RequestRedirect` — for the HTTP→HTTPS redirect HTTPRoute the skill generates
   - `ResponseHeaderModifier` — for the X-* security headers from row 9a
   - `URLRewrite` — available but not currently generated
6. H2 `## Backend splitting` — show a 2-weight example (not generated by skill but documented for manual edits).
7. H2 `## Attachment rules`:
   - `parentRefs[].sectionName` must match a listener name on the Gateway
   - Gateway's `allowedRoutes.namespaces` must permit this HTTPRoute's namespace
   - See `master-minion-topology.md` for cross-namespace specifics.

Target length: ~200 lines.

- [ ] **Step 2: Verify**

Run: `grep -c "^## " docs/gateway/http-routing-guide.md`
Expected: exactly 7.

- [ ] **Step 3: Commit**

```bash
git add docs/gateway/http-routing-guide.md
git commit -m "docs(gateway): 新增 HTTPRoute 參考指南

提煉自上游 gateway-api.sigs.k8s.io/guides/http-routing 的
HTTPRoute 結構、path/header 比對、filter 使用、以及
*gateway-migrate 實際會產生的 parentRef 規則。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Create ingress2gateway integration notes + rewrite welcome file

**Files:**
- Create: `docs/gateway/ingress2gateway-integration.md`
- Delete: `docs/gateway/welcom-Ingress-NGINX.md` (typo'd filename, currently untracked)
- Create: `docs/gateway/ingress-nginx-welcome.md` (rewritten)

- [ ] **Step 1: Write ingress2gateway-integration.md**

Content from spec §7. Structure:

1. H1 `# ingress2gateway Integration`
2. Preface: "`*gateway-migrate` uses [kubernetes-sigs/ingress2gateway](https://github.com/kubernetes-sigs/ingress2gateway) as an optional second-opinion cross-check in Step 4c. This page documents the integration contract."
3. H2 `## Install`: `brew install ingress2gateway` (user's confirmed path) or `go install github.com/kubernetes-sigs/ingress2gateway@latest`
4. H2 `## Providers` — list: `ingress-nginx`, `gce`, `istio`, `kong`, `apisix`, `openapi`. Relevant to this project: `ingress-nginx` (current) and `gce` (parallel GKE Ingress).
5. H2 `## What upstream handles` — bulleted list from spec §7
6. H2 `## What our skill does that upstream does not` — bulleted list from spec §7
7. H2 `## How the skill invokes it`:
   ```bash
   ingress2gateway print --providers ingress-nginx \
     --input-file common.ingress/overlays/prd/app.ingress.yaml
   ```
8. H2 `## Diff normalization rules`:
   - Sort map keys alphabetically
   - Strip comments
   - Normalize list order by `metadata.name`
   - Ignore `metadata.annotations` differences that are purely formatting
9. H2 `## Graceful degradation`: if not on PATH, Step 4c is skipped with WARN, migration continues.

Target length: ~80 lines.

- [ ] **Step 2: Write ingress-nginx-welcome.md**

Start from current `docs/gateway/welcom-Ingress-NGINX.md` (untracked raw scrape). Rewrite:

1. H1 `# Ingress-NGINX → Gateway API — Welcome`
2. One paragraph preface: "Read this before running `*gateway-migrate`. Community pointers for Ingress-NGINX users migrating to Gateway API."
3. H2 `## Why Gateway API?` — 3 bullets max (role separation, feature portability, native merging)
4. H2 `## Can I run both controllers in parallel?` — yes, each gets a different external IP. This is what the skill's side-by-side strategy assumes.
5. H2 `## Tools` — pointer to `ingress2gateway-integration.md`
6. H2 `## Conformance` — one line: GKE Gateway targets the Standard channel; check conformance reports before picking a new implementation.
7. H2 `## Community resources` — keep 2-3 links from the upstream scrape (sig-network-gateway-api mailing list, Slack, GitHub discussions).

Target length: ~60 lines.

- [ ] **Step 3: Delete the typo'd file**

```bash
rm docs/gateway/welcom-Ingress-NGINX.md
```

Note: the file is currently untracked (`??` in git status), so the `rm` is sufficient — no `git rm` needed.

- [ ] **Step 4: Verify**

```bash
ls docs/gateway/ingress-nginx-welcome.md docs/gateway/ingress2gateway-integration.md
ls docs/gateway/welcom-Ingress-NGINX.md 2>&1 || echo "correctly absent"
```
Expected: both new files exist; typo'd file absent.

- [ ] **Step 5: Commit**

```bash
git add docs/gateway/ingress2gateway-integration.md docs/gateway/ingress-nginx-welcome.md
git commit -m "docs(gateway): 新增 ingress2gateway 整合與 welcome 指南

新增：
- ingress2gateway-integration.md：上游 Kubernetes SIG 工具的
  install / providers / diff normalization 規則與 graceful
  degradation 行為
- ingress-nginx-welcome.md：重寫自 welcom-Ingress-NGINX.md
  （原檔名有拼字錯誤，改寫後刪除），精簡為遷移前必讀的社群
  資源清單

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Rewrite migrate-from-ingress.md

**Files:**
- Modify: `docs/gateway/migrate-from-ingress.md` (currently untracked raw scrape)

- [ ] **Step 1: Rewrite the file**

Open the existing raw scrape. Remove:
- "Reasons to Switch to Gateway API" marketing section
- Redundant rehash of the same mapping table in different phrasings
- Upstream meta-commentary ("this guide will…")

Keep and restructure:

1. H1 `# Migrating from Ingress to Gateway API` (plus new project header line: *"Read this before running `*gateway-migrate`. Explains the conceptual transformations the skill automates."*)
2. H2 `## Key differences` — Personas, Available features, Extensibility approach (keep the bullet summaries, drop the lengthy prose)
3. H2 `## Feature mapping` — the table mapping Ingress features to Gateway API features (Entry Points, TLS, Routing, Rules Merging, Default Backend, Selecting Data Plane)
4. H2 `## Worked example` — keep the concrete YAML conversion example (Ingress → Gateway + HTTPRoutes + TLS redirect HTTPRoute)
5. H2 `## Implementation-specific annotations` — one paragraph pointing at `annotation-map.md` for the project-specific translations
6. H2 `## Automatic conversion` — one paragraph pointing at `ingress2gateway-integration.md`

Target length: ~300 lines (down from current 316).

- [ ] **Step 2: Verify**

```bash
wc -l docs/gateway/migrate-from-ingress.md
grep -c "^## " docs/gateway/migrate-from-ingress.md
```
Expected: ~300 lines, 6 H2 headers.

- [ ] **Step 3: Commit**

```bash
git add docs/gateway/migrate-from-ingress.md
git commit -m "docs(gateway): 改寫 migrate-from-ingress 為專案導向版本

移除原始上游抓取檔案的行銷段落與重複說明，保留概念差異、
Feature mapping 表、YAML 轉換實例三個核心區塊，並加上
*gateway-migrate 的前置必讀說明。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Skill Definition (skills/gateway-api-migration/)

This phase builds the authoritative `SKILL.md` and its local reference material. Each task adds one section of the skill; the file grows incrementally so commits stay reviewable.

### Task 7: Create skill directory and inline reference symlinks

**Files:**
- Create: `skills/gateway-api-migration/` (directory)
- Create: `skills/gateway-api-migration/references/` (directory)
- Create: 7 symlinks under `skills/gateway-api-migration/references/` pointing at `docs/gateway/*`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p skills/gateway-api-migration/references
```

- [ ] **Step 2: Create relative symlinks from references/ to docs/gateway/**

```bash
cd skills/gateway-api-migration/references
ln -s ../../../docs/gateway/annotation-map.md annotation-map.md
ln -s ../../../docs/gateway/master-minion-topology.md master-minion-topology.md
ln -s ../../../docs/gateway/gke-gateway-notes.md gke-gateway-notes.md
ln -s ../../../docs/gateway/http-routing-guide.md http-routing-guide.md
ln -s ../../../docs/gateway/ingress2gateway-integration.md ingress2gateway-integration.md
ln -s ../../../docs/gateway/migrate-from-ingress.md migration-from-ingress.md
ln -s ../../../docs/gateway/ingress-nginx-welcome.md ingress-nginx-welcome.md
cd -
```

- [ ] **Step 3: Verify symlinks resolve**

```bash
ls -l skills/gateway-api-migration/references/
```
Expected: 7 symlinks, all showing `-> ../../../docs/gateway/<name>`. Each target should resolve (no broken links).

```bash
for f in skills/gateway-api-migration/references/*.md; do
  if [ -f "$f" ]; then echo "OK: $f"; else echo "BROKEN: $f"; fi
done
```
Expected: all 7 lines say `OK:`.

- [ ] **Step 4: Commit**

```bash
git add skills/gateway-api-migration/references/
git commit -m "feat(skill): 建立 gateway-api-migration skill 目錄結構

建立 skills/gateway-api-migration/references/ 目錄，並以
相對路徑 symlink 連結至 docs/gateway/ 下的 6 份參考文件，
確保 skill 與使用者文件之單一來源原則。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Write SKILL.md frontmatter, overview, Step 0 (tool check) and Step 1 (discover)

**Files:**
- Create: `skills/gateway-api-migration/SKILL.md`

- [ ] **Step 1: Write the file (frontmatter + sections 0–1)**

```markdown
---
name: gateway-api-migration
description: >
  Migrates Kustomize modules using NGINX Ingress to Gateway API resources,
  targeting GKE Gateway (gke-l7-global-external-managed). Handles master/minion
  topology (common.ingress/ + common.service/) as the primary case, with
  standalone Ingress as a fallback. Generates a side-by-side common.gateway/
  module, HTTPRoutes alongside existing minions, a resumable YAML state file,
  and a human migration report. Never modifies the master source; performs
  idempotent in-place edits only to common.service/overlays/<env>/kustomization.yaml.
version: "1.0.0"
---

# Gateway API Migration Skill

Invoked by Zeus pipeline `*gateway-migrate`. Canonical references:
- `references/annotation-map.md` — translation table
- `references/master-minion-topology.md` — topology detection rules
- `references/gke-gateway-notes.md` — GKE-specific resource facts
- `references/http-routing-guide.md` — HTTPRoute structure reference
- `references/ingress2gateway-integration.md` — second-opinion tool contract

## Activation

Triggered explicitly by `*gateway-migrate` from Zeus. Not auto-triggered.

## Invocation forms

```
*gateway-migrate                         # interactive discovery mode
*gateway-migrate <module-path>           # explicit target
*gateway-migrate <module-path> --resume  # resume from state.yaml
*gateway-migrate <module-path> --force   # bypass never-clobber on target
```

## Artifacts produced

Every successful run writes three things to the target repo:

1. A new `common.gateway/` Kustomize module (master → Gateway)
2. `common.service/overlays/<env>/*-httproute.yaml` files + an idempotent
   edit to `common.service/overlays/<env>/kustomization.yaml` (minions → HTTPRoutes)
3. `docs/reports/gateway-migration/<module-slug>/state.yaml` + `report.md`

## Step 0 — Tool check

Before any discovery, verify tool availability. Use `command -v` to probe.

| Tool | Required | On missing |
|---|---|---|
| `kustomize` | yes | HALT with `brew install kustomize` |
| `yq` | yes | HALT with `brew install yq` |
| `kubeconform` | no | WARN, SKIP Step 4b with `brew install kubeconform` |
| `ingress2gateway` | no | WARN, SKIP Step 4c with `brew install ingress2gateway` |

Record each tool's version in `state.yaml` under `environment.tools`:

```bash
kustomize version --short
yq --version
kubeconform -v 2>&1 | head -1
ingress2gateway version 2>&1 | head -1
```

If any required tool is missing, halt and print:

```
[HALT] Required tool missing: <tool>
Install: brew install <tool>
Re-run *gateway-migrate after install.
```

## Step 1 — Discover (topology-aware)

Classification rules (reproduced here for agent in-context use; full
rationale in `references/master-minion-topology.md`):

For each `kind: Ingress` manifest found in the repo:

| Signal | Classification |
|---|---|
| `metadata.annotations["nginx.ingress/mergeable-ingress-type"] == "master"` | **master** (authoritative) |
| `spec.rules[].host` present AND no `http.paths` anywhere | **master** (heuristic fallback) |
| `spec.rules[].http.paths[]` present AND no `spec.tls` AND `ingress.class: nginx` | **minion** |
| `spec.rules[].host` + `spec.rules[].http.paths[]` + `spec.tls` in one resource | **standalone** |

**Discovery algorithm:**

1. `Grep` the repo for `^kind: Ingress` and collect all matching files.
2. For each file, read the manifest and apply classification rules above.
3. Group masters by module (nearest ancestor containing `base/` + `overlays/`).
4. Group minions by module, then by service name (derived from filename:
   `argocd-nginx-ingress.yaml` → `argocd`).
5. For each minion, extract `spec.rules[0].host` and search all masters for
   a matching declared host (exact match, case-insensitive).
6. Pair each minion with its master:
   - 1 match → pair.
   - 0 matches → record as orphan minion, HALT at end of discovery.
   - 2+ matches → record as ambiguous, HALT.
7. For each master host with no matching minion → record as orphan host
   (WARN, proceed).

**Interactive form (no args or `--interactive`):** print a numbered list
of detected migration units with hostname counts; user picks one.

**Explicit form (`*gateway-migrate <path>`):** treat `<path>` as the
master module path. Verify at least one Ingress exists inside. Auto-pair
minions from sibling modules.

**`--resume` form:** load `state.yaml`, read `currentStep` and `topology`,
jump to the matching step with a "resumed from step N" banner.

**Gates:**
- HALT if no Ingress found (interactive) or the path has no Ingress (explicit).
- HALT if `--resume` is set but no `state.yaml` exists.
- HALT on orphan minions (source config is broken).
- HALT on ambiguous pairings.
- WARN on orphan hosts; continue.

Write the discovered topology to `state.yaml` under `topology`, `master`,
`minions`, `orphanHosts`, `orphanMinions` fields. See the state YAML schema
example in the spec (§4.1).
```

- [ ] **Step 2: Verify frontmatter**

```bash
head -10 skills/gateway-api-migration/SKILL.md
```
Expected: valid YAML frontmatter with `name`, `description`, `version`.

- [ ] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "feat(skill): 新增 gateway-api-migration SKILL.md 骨架與 Step 0/1

建立 skill 檔首（frontmatter、overview、invocation）以及前兩
個步驟：Step 0 tool check（kustomize/yq 必要；kubeconform/
ingress2gateway 可選）與 Step 1 topology-aware discovery
（master/minion 偵測與配對演算法）。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Append Step 2 (Analyze) to SKILL.md

**Files:**
- Modify: `skills/gateway-api-migration/SKILL.md` (append Step 2)

- [ ] **Step 1: Append to SKILL.md**

```markdown

## Step 2 — Analyze

For each Ingress manifest found in Step 1 (masters and minions), perform
annotation classification and structural extraction.

**For each master manifest:**

1. Extract annotations. For each annotation, look up its entry in
   `references/annotation-map.md` and classify into one of: `portable`,
   `portable-GKE`, `convertible`, `convertible-lossy`, `split-category
   (auto)`, `split-category (stub)`, `drop-info`.
2. Extract `spec.rules[].host` (the declared host list, no paths expected
   on masters).
3. Extract `spec.tls[]` — map each entry to `(hosts, secretName,
   managedCertificateName)`. The secretName corresponds to a Secret or
   ManagedCertificate resource name.
4. Parse any `server-snippet` annotation content per rows 9a/b/c:
   - **9a (auto)**: extract `add_header X-Content-Type-Options`,
     `add_header X-XSS-Protection`, `add_header X-Frame-Options` — record
     as auto-convert entries with their exact values.
   - **9b (stub)**: match `add_header Set-Cookie "..."` lines — record
     verbatim as stubbed directives.
   - **9c (stub)**: match `location ~ ... { ... return 404; }` blocks —
     record verbatim as stubbed directives with line numbers.

**For each minion manifest:**

1. Extract annotations. Usually just `kubernetes.io/ingress.class: nginx`
   which is drop/portable.
2. Extract `spec.rules[].host` (single host expected; record if multiple).
3. Extract `spec.rules[].http.paths[]` → list of `(path, pathType,
   backend.service.name, backend.service.port)`.
4. Resolve the minion's effective namespace:
   - Check `metadata.namespace` on the Ingress resource.
   - If absent, read the overlay's `kustomization.yaml` for a top-level
     `namespace:` field.
   - If still absent, HALT: "cannot determine namespace for minion
     `<file>`; migration requires explicit namespace."
5. Verify the referenced backend Service exists. Search the repo for
   `kind: Service` manifests matching the name. If missing → record WARN,
   proceed (Service might come from a Helm chart or another module).

**Write analysis to state YAML** under `steps[2]`:

```yaml
  - id: 2
    name: analyze
    status: done
    annotations:
      portable: [...]
      convertible: [...]
      splitCategory: [...]
      dropInfo: [...]
```

**Present the summary to the user** (terminal output):

```
Module: common.ingress → common.gateway (master/minion topology)

Master:   common.ingress/ (4 files)
  Hostnames declared:       14
  Annotation categories:
    portable:                3
    portable-GKE:            4  (ManagedCertificate refs)
    convertible:             4  (→ GCPBackendPolicy resources)
    split-category (auto):   3  (X-* headers → responseHeaderModifier)
    split-category (stub):   2  (Set-Cookie, path denylists)
    drop-info:               1  (mergeable-ingress-type)

Minions:  common.service/ (11 services × 3 envs = 33 files)
  All backend Services resolved: yes
  Orphan minions:              0
  Orphan hosts:                2  (will be listed in report)

Proceed with conversion? [y/N]
```

**Gate:** interactive — user must confirm. HALT on decline.
```

- [ ] **Step 2: Verify**

```bash
grep -n "^## Step 2 — Analyze" skills/gateway-api-migration/SKILL.md
```
Expected: one match.

- [ ] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "feat(skill): 新增 gateway-api-migration Step 2 分析階段

定義 master/minion 兩種 Ingress 的註解分類、server-snippet
拆解（row 9a/b/c）、backend Service 解析、minion 命名空間
判定與使用者確認閘門。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Append Step 3 (Convert — two-phase) to SKILL.md

**Files:**
- Modify: `skills/gateway-api-migration/SKILL.md`

- [ ] **Step 1: Append Step 3**

```markdown

## Step 3 — Convert (two-phase)

Conversion is split into **Phase 3A** (create new `common.gateway/` module)
and **Phase 3B** (create HTTPRoutes alongside minions + in-place edit
kustomization.yaml).

**Pre-flight:**

1. Check target path `<master-parent>/common.gateway/`:
   - If exists without `--force` → HALT: "Target already present; use
     `--resume` or `--force`."
   - If exists with `--force` → continue (existing content will be
     overwritten).
2. For each minion, check destination `common.service/overlays/<env>/<svc>-httproute.yaml`:
   - If exists without `--force` → HALT.
   - If exists with `--force` → overwrite.
3. For each `common.service/overlays/<env>/kustomization.yaml` that will
   be modified, capture the pre-edit SHA256 hash and record in state YAML
   under `steps[3].modified[].preEditHash`.

### Phase 3A — Generate `common.gateway/`

Atomic: write everything to `common.gateway.tmp/` first, then rename to
`common.gateway/`. On any failure, remove the temp directory.

1. `common.gateway/base/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: ingress-nginx
   resources:
     - gateway.yaml
     # - gcpbackendpolicy-<svc>.yaml (one per service with CORS)
   ```
2. `common.gateway/base/gateway.yaml`:
   - One `Gateway` resource, `gatewayClassName: gke-l7-global-external-managed`
   - One listener per master hostname
   - Each listener: `allowedRoutes.namespaces.from: Selector`,
     `selector.matchLabels.gateway-access: ingress-nginx`
   - TLS listeners reference the ManagedCertificate name from the master's
     TLS entries via `certificateRefs[kind: ManagedCertificate, name: <name>]`
   - HTTP listeners (port 80) included for HTTP→HTTPS redirect
3. `common.gateway/base/gcpbackendpolicy-<svc>.yaml` (only if Row 5–8
   annotations were present):
   - `apiVersion: networking.gke.io/v1`
   - `kind: GCPBackendPolicy`
   - `spec.targetRef` → the backend Service
   - `spec.cors` populated from CORS annotations
4. `common.gateway/overlays/{dev,stg,prd}/kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namespace: ingress-nginx
   resources:
     - ../../base
   patches:
     - path: gateway.patch.yaml
   ```
5. `common.gateway/overlays/<env>/gateway.patch.yaml`:
   - Per-env listeners with the environment's hostnames and
     ManagedCertificate refs
6. `common.gateway/argocd/{dev,stg,prd}.yaml`:
   - Copy `common.ingress/argocd/<env>.yaml`
   - Change `metadata.name` from `<name>` to `<name>-gateway`
   - Change `spec.source.path` from `common.ingress/overlays/<env>` to
     `common.gateway/overlays/<env>`
7. `common.gateway/MIGRATION.md`:
   - Copy `references/runbook-template.md`
   - Substitute variables: `{{master_module}}`, `{{generated_module}}`,
     `{{target_namespaces}}`, `{{hostnames_per_env}}`, `{{service_list}}`

Record each generated file in `state.yaml` under `steps[3].generated[]`.

### Phase 3B — Generate HTTPRoutes + edit kustomization.yaml

For each `(env, service)` tuple from the state's `minions[]`:

1. Read `references/httproute-template.yaml`, substitute variables:
   - `{{service}}` → minion's service name
   - `{{namespace}}` → minion's effective namespace
   - `{{hostname}}` → minion's declared host for this env
   - `{{listener_name}}` → Gateway listener name matching this hostname
   - `{{path_rules}}` → translated from minion's `spec.rules[].http.paths[]`
   - `{{backend_name}}` → minion's backend Service name
   - `{{backend_port}}` → minion's backend Service port
   - `{{response_header_filters}}` → X-* headers from master's server-snippet
2. Write to `common.service/overlays/<env>/<service>-httproute.yaml`.
3. Edit `common.service/overlays/<env>/kustomization.yaml` in place:
   ```bash
   # Check idempotency first
   if ! yq eval ".resources | contains([\"<svc>-httproute.yaml\"])" \
        "common.service/overlays/<env>/kustomization.yaml" | grep -q true; then
     yq eval -i ".resources += [\"<svc>-httproute.yaml\"]" \
        "common.service/overlays/<env>/kustomization.yaml"
   fi
   ```
4. After all edits for this env are complete, validate:
   ```bash
   kustomize build common.service/overlays/<env>
   ```
5. On build failure:
   - Restore `kustomization.yaml` from the pre-edit SHA256 snapshot
     captured in pre-flight.
   - Remove all newly created `*-httproute.yaml` files for this env.
   - HALT: "In-place edit validation failed. Target repo reverted to
     pre-edit state. Error: <kustomize output>. Fix and re-run with
     `--resume`."

Record each modification in `state.yaml` under `steps[3].modified[]`.

**TODO stubs:** insert inline in generated YAML as:

```yaml
# TODO(gateway-migrate): <reason> — see report.md Manual Review #<n>
```

Apply to:
- Gateway listener comments when `server-snippet` has stubbed directives
- HTTPRoute comments when the minion's backend relies on a stubbed feature

**Gate:** HALT on any write failure, target-exists-without-force, or
in-place edit validation failure.
```

- [ ] **Step 2: Verify**

```bash
grep -n "Phase 3A" skills/gateway-api-migration/SKILL.md
grep -n "Phase 3B" skills/gateway-api-migration/SKILL.md
```
Expected: each match once.

- [ ] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "feat(skill): 新增 gateway-api-migration Step 3 兩階段轉換

- Phase 3A：以暫存目錄建立 common.gateway/ 模組（Gateway
  資源、gcpbackendpolicy、overlays 與 argocd 應用）
- Phase 3B：在 common.service/ 每個 overlay 建立 *-httproute.yaml
  並以 yq 冪等地寫入 kustomization.yaml（pre-edit hash
  rollback 與 kustomize build 後驗證）

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Append Step 4 (Validate) and Step 5 (Report) to SKILL.md

**Files:**
- Modify: `skills/gateway-api-migration/SKILL.md`

- [ ] **Step 1: Append Steps 4 and 5**

```markdown

## Step 4 — Validate

### 4a. Kustomize build (required)

For each generated overlay in `common.gateway/` and for each modified
overlay in `common.service/`:

```bash
kustomize build common.gateway/overlays/dev
kustomize build common.gateway/overlays/stg
kustomize build common.gateway/overlays/prd
kustomize build common.service/overlays/dev
kustomize build common.service/overlays/stg
kustomize build common.service/overlays/prd
```

Record each result in `state.yaml` under `steps[4].checks.kustomizeBuild`.

On failure → HALT. Leave generated files in place for user debugging.
User can fix and re-run with `--resume`.

### 4b. Kubeconform (optional)

Only if `kubeconform` was detected in Step 0. Run against the generated
output with Gateway API CRD schemas:

```bash
kustomize build common.gateway/overlays/prd | \
  kubeconform -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.1.0/config/crd/standard/{{.ResourceKind}}_{{.Group}}_{{.KindLowerSuffix}}.json' \
    -ignore-missing-schemas
```

GKE-specific resources (`GCPBackendPolicy`, `ManagedCertificate`) won't
have public schemas — use `-ignore-missing-schemas`. Warnings are WARN
not FAIL.

### 4c. Second-opinion diff (optional)

Only if `ingress2gateway` was detected. For each master Ingress manifest:

```bash
ingress2gateway print --providers ingress-nginx \
  --input-file common.ingress/overlays/prd/app.ingress.yaml \
  > /tmp/i2g-output-prd.yaml
```

Normalize both outputs (sort map keys alphabetically, strip comments,
normalize list order by `metadata.name`) and compute a line-level diff
against the skill's generated `common.gateway/` equivalent. Record in
`state.yaml`:

```yaml
  - id: 4
    name: validate
    checks:
      ingress2gatewaySecondOpinion:
        status: ran
        divergences: <count>
        summary: <one-line>
        details: <full diff written to docs/reports/gateway-migration/<slug>/second-opinion.diff>
```

Divergences are informational only — never halt.

**Gate:** HALT on 4a failure; WARN on 4b/4c.

## Step 5 — Render report

Generate `docs/reports/gateway-migration/<module-slug>/report.md` from
`state.yaml`. Follow `prompts/shared/report-format.md`. Required sections:

1. **Header** — module, target GatewayClass, date, verdict
   (`PASS` / `COMPLETED WITH MANUAL REVIEW REQUIRED` / `FAIL`)
2. **Summary table** — 8-row table of step results
3. **Topology** — master/minion (or standalone), counts, orphan list
4. **Annotation Inventory** — portable / convertible / split-category /
   drop-info from state YAML
5. **Manual Review Required** — for each split-category stub and
   drop-info entry: what it was, why no direct translation, suggested
   alternative, exact `file:line` of occurrences
6. **Cutover Runbook** — per-hostname DNS phases (copy from
   `references/runbook-template.md` with variable substitution)
7. **Rollback Procedure** — DNS-flip back; both stacks coexist until
   Phase 4 cleanup
8. **Second Opinion** — only if Step 4c ran; normalized diff + explanation
9. **Consolidation Opportunities** — optional follow-ups (wildcard cert,
   etc.)

Verdict escalation rules:
- Any `splitCategory.stubbed` entries → `COMPLETED WITH MANUAL REVIEW REQUIRED`
- Any Step 4a failure → `FAIL`
- Otherwise → `PASS`

On write failure, WARN and print the report to stdout as fallback.
```

- [ ] **Step 2: Verify**

```bash
grep -n "^## Step 4" skills/gateway-api-migration/SKILL.md
grep -n "^## Step 5" skills/gateway-api-migration/SKILL.md
```
Expected: one match each.

- [ ] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "feat(skill): 新增 gateway-api-migration Step 4/5 驗證與報告

- Step 4a：必做 kustomize build（失敗 HALT）
- Step 4b：選配 kubeconform（ignore-missing-schemas）
- Step 4c：選配 ingress2gateway 第二意見對照
- Step 5：以 state.yaml 渲染 Markdown 報告，含 8 個區塊與
  verdict 升級規則

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Append Steps 6–7 (Runbook + Pre-commit) + Resume semantics to SKILL.md

**Files:**
- Modify: `skills/gateway-api-migration/SKILL.md`

- [ ] **Step 1: Append the remaining sections**

```markdown

## Step 6 — Runbook & next steps

Print to the Zeus session and also write to `common.gateway/MIGRATION.md`
(substituted from `references/runbook-template.md`). The runbook is
structured around per-hostname DNS cutover (see spec §6.8 for the full
template). Key sections:

- **Pre-cutover setup** — install Gateway API CRDs, install GKE Gateway
  controller, label target namespaces with `gateway-access=ingress-nginx`
  (the skill provides the exact `kubectl label` command with discovered
  namespaces).
- **Phase 1** — Deploy `common.gateway/` (Gateway resource only, no
  traffic).
- **Phase 2** — Deploy updated `common.service/` (HTTPRoutes attach to
  Gateway, both stacks serve hostnames at separate IPs).
- **Phase 3** — Per-hostname DNS cutover (gradual, reversible, one
  hostname at a time).
- **Phase 4** — Bake and clean up (delete `common.ingress/` and minions
  after 1+ week of stability).
- **Rollback** — DNS flip back; nothing was destructively removed in
  Phases 1-3.

**Gate:** informational.

## Step 7 — Pre-commit hints

Print the suggested commit message and file list to the session. Format:

```
feat(ingress): migrate common.ingress to Gateway API (master/minion)

- Generate common.gateway/ Kustomize module (Gateway + base/dev/stg/prd overlays)
- Add HTTPRoutes to common.service/overlays/{dev,stg,prd}/ for <N> services
- Register new HTTPRoute files in common.service/overlays/*/kustomization.yaml
- Target: gke-l7-global-external-managed
- <N> HTTPRoutes, <N> listeners, <N> responseHeaderModifier filters
- <N> manual review items — see docs/reports/gateway-migration/<slug>/report.md
- common.ingress/ and common.service/overlays/*/*-nginx-ingress.yaml
  untouched — side-by-side for safe per-hostname DNS cutover
```

Files to stage (list every file from `state.yaml` `steps[3].generated[]`
and `steps[3].modified[]`, plus the report and state file):

```bash
git add common.gateway/
git add common.service/overlays/dev/argocd-httproute.yaml \
        common.service/overlays/dev/grafana-httproute.yaml \
        ...
git add common.service/overlays/dev/kustomization.yaml \
        common.service/overlays/stg/kustomization.yaml \
        common.service/overlays/prd/kustomization.yaml
git add docs/reports/gateway-migration/<slug>/state.yaml \
        docs/reports/gateway-migration/<slug>/report.md
```

**Never auto-commit.** The user drives git.

**Gate:** informational.

## Halt / resume semantics

| Failure point | State | Resume behavior |
|---|---|---|
| Step 1 discovery fails | no state written | re-run normally |
| Step 2 analyze errors | state exists, step 2 marked error | `--resume` re-runs from step 2 |
| Step 3A write fails | temp dir cleaned, no partial output | re-run normally; target still clean |
| Step 3B build fails | kustomization.yaml reverted, new httproute files removed | `--resume` retries step 3B from the failing env |
| Step 4a build fails | generated module left in place | user fixes; `--resume` re-runs step 4 |
| Step 4b/4c warn | state records warnings | no halt; continue |
| User aborts step 2 | state `status: aborted` | `--resume` restarts from step 2 |
| Run completes | state `status: completed` | rerun refused unless `--force` |

On `--resume`, the skill:
1. Reads `state.yaml` from the path argument.
2. Verifies `schemaVersion` matches (`1`). Mismatch → HALT.
3. Reads `currentStep` and `topology`.
4. Jumps to that step and re-executes it in full (not mid-step).
5. Prints `Resumed from step N (<name>).` to the user.

## State YAML schema

See spec §4.1 for the full schema example. Required top-level fields:

- `schemaVersion: 1`
- `topology: master-minion | standalone`
- `module: <master-module-name>`
- `moduleSlug: <slug-for-paths>`
- `targetGatewayClass: gke-l7-global-external-managed`
- `generatedModule: common.gateway`
- `createdAt`, `updatedAt`: ISO 8601 timestamps
- `status`: `discovering | analyzing | converting | validating | completed | failed | aborted`
- `currentStep`: integer 1-7
- `environment.tools`: map of tool name → version
- `master`: object with `module`, `namespace`, `files[]`, `hostnamesDeclared`
- `minions[]`: array of minion objects (topology: master-minion only)
- `orphanHosts[]`, `orphanMinions[]`: diagnostic arrays
- `steps[]`: array of step records with `id`, `name`, `status`, `findings`
- `reportPath`: path to the rendered markdown report
```

- [ ] **Step 2: Verify SKILL.md is now complete**

```bash
grep -c "^## Step " skills/gateway-api-migration/SKILL.md
```
Expected: 8 (Steps 0–7).

```bash
wc -l skills/gateway-api-migration/SKILL.md
```
Expected: between 400 and 600 lines.

- [ ] **Step 3: Commit**

```bash
git add skills/gateway-api-migration/SKILL.md
git commit -m "feat(skill): 完成 gateway-api-migration Step 6/7、resume 與 state schema

- Step 6：per-hostname DNS cutover runbook
- Step 7：pre-commit 提示與檔案清單
- Halt/resume 語義表與 --resume 流程
- state.yaml 頂層欄位描述（schemaVersion=1）

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Create skill reference templates (runbook + httproute + manual-review-patterns)

**Files:**
- Create: `skills/gateway-api-migration/references/runbook-template.md`
- Create: `skills/gateway-api-migration/references/httproute-template.yaml`
- Create: `skills/gateway-api-migration/references/manual-review-patterns.md`

- [ ] **Step 1: Write runbook-template.md**

Copy the full runbook from spec §6.8 (Step 6) into a template file with
`{{variable}}` placeholders. Sections: Pre-cutover setup, Phase 1, Phase 2,
Phase 3, Phase 4, Rollback, Why per-hostname.

Variables: `{{master_module}}`, `{{generated_module}}`, `{{target_namespaces}}`,
`{{hostnames_per_env}}`, `{{service_list}}`, `{{slug}}`.

Target length: ~120 lines.

- [ ] **Step 2: Write httproute-template.yaml**

```yaml
# HTTPRoute template — filled in by gateway-api-migration skill per minion.
# Variables: {{service}}, {{namespace}}, {{hostname}}, {{listener_name}},
#            {{backend_name}}, {{backend_port}}, {{path_rules}},
#            {{response_header_filters}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{service}}
  namespace: {{namespace}}
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: common-gateway
      namespace: ingress-nginx
      sectionName: {{listener_name}}
  hostnames:
    - {{hostname}}
  rules:
    # {{path_rules}} expands to one entry per path rule in the source minion
    - matches:
        - path:
            type: PathPrefix
            value: /
      # {{response_header_filters}} expands to X-* headers from master's server-snippet (row 9a)
      # filters:
      #   - type: ResponseHeaderModifier
      #     responseHeaderModifier:
      #       add:
      #         - name: X-Content-Type-Options
      #           value: nosniff
      #         - name: X-XSS-Protection
      #           value: "1; mode=block"
      #         - name: X-Frame-Options
      #           value: SAMEORIGIN
      backendRefs:
        - name: {{backend_name}}
          port: {{backend_port}}
```

- [ ] **Step 3: Write manual-review-patterns.md**

Structure:

1. H1 `# Manual Review Patterns`
2. Preface: "Deep guidance on annotations that `*gateway-migrate` cannot auto-convert. The skill emits TODO stubs pointing here."
3. H2 `## Pattern: server-snippet security headers` — explain what each X-* header does, show row 9a auto-conversion, warn about app-layer duplication risk
4. H2 `## Pattern: server-snippet Set-Cookie rewrites` — explain why `add_header Set-Cookie "..."` with no cookie name is almost always legacy bug config; recommend removal or migration to app-layer cookie flags
5. H2 `## Pattern: server-snippet path denylists` — explain as WAF/Cloud Armor territory; link to GCP Cloud Armor security policy docs; show a minimal Cloud Armor rule example
6. H2 `## Pattern: mergeable-ingress-type` — explain the master/minion model and why it's obsolete under Gateway API (HTTPRoute attachment is native merging)
7. H2 `## Pattern: proxy-*-timeout` — explain the three NGINX timeouts and how they collapse into one GKE `GCPBackendPolicy.spec.timeoutSec`

Target length: ~180 lines.

- [ ] **Step 4: Verify all three files exist**

```bash
ls -l skills/gateway-api-migration/references/runbook-template.md \
      skills/gateway-api-migration/references/httproute-template.yaml \
      skills/gateway-api-migration/references/manual-review-patterns.md
```
Expected: all three are regular files.

- [ ] **Step 5: Commit**

```bash
git add skills/gateway-api-migration/references/runbook-template.md \
        skills/gateway-api-migration/references/httproute-template.yaml \
        skills/gateway-api-migration/references/manual-review-patterns.md
git commit -m "feat(skill): 新增 runbook/HTTPRoute 範本與 manual-review 指南

- runbook-template.md：per-hostname DNS cutover 執行本，以
  {{variable}} 形式供 skill 填入
- httproute-template.yaml：skill 產生每個 minion HTTPRoute
  時使用的骨架
- manual-review-patterns.md：server-snippet / mergeable-ingress
  / proxy-timeout 等無法自動轉換註解的深度建議

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — Pipeline and Platform Registration

Thin pipeline wrapping the skill + cross-platform registrations so every supported agent surface (Claude Code, Codex, Gemini, Antigravity) exposes `*gateway-migrate`.

### Task 14: Create thin Zeus pipeline

**Files:**
- Create: `prompts/zeus/gateway-migrate.md`

- [ ] **Step 1: Write the pipeline**

```markdown
# Gateway API Migration Pipeline

End-to-end migration from NGINX Ingress (master/minion or standalone) to
GKE Gateway API. Delegates all logic to the `gateway-api-migration` skill.

## Pipeline Steps

### Step 1: Tool Check

- Verify `kustomize` and `yq` (required)
- Check `kubeconform` and `ingress2gateway` (optional, graceful degradation)
- Gate: HALT on missing required tools with install hints

### Step 2: Topology Discovery

- Invoke `gateway-api-migration` skill Step 1
- Detect master/minion or standalone topology
- Pair minions with masters by hostname
- Gate: HALT on no Ingress found, orphan minions, or ambiguous pairings

### Step 3: Annotation Analysis

- Invoke skill Step 2
- Classify annotations per `references/annotation-map.md`
- Present summary with annotation category counts
- Gate: interactive user confirmation (HALT on decline)

### Step 4: Two-Phase Conversion

- Invoke skill Step 3 (Phase 3A: common.gateway/ module)
- Invoke skill Step 3 (Phase 3B: HTTPRoutes + in-place kustomization.yaml edits)
- Gate: HALT on write failure, target-exists-without-force, or post-edit
  build failure (with automatic rollback of in-place edits)

### Step 5: Validation

- Step 4a kustomize build (required) — HALT on failure
- Step 4b kubeconform (optional) — WARN on unknown CRDs
- Step 4c ingress2gateway second opinion (optional) — record diff, never halt
- Gate: HALT on 4a failure; WARN on 4b/4c

### Step 6: Report Rendering

- Invoke skill Step 5
- Write state.yaml + report.md under docs/reports/gateway-migration/<slug>/
- Gate: WARN on write failure, print report to stdout as fallback

### Step 7: Runbook Output

- Invoke skill Step 6
- Print per-hostname DNS cutover runbook to session
- Also written to common.gateway/MIGRATION.md
- Gate: informational

### Step 8: Pre-commit Hints

- Invoke skill Step 7
- Print suggested commit message and `git add` commands
- Never auto-commit
- Gate: informational

## Invocation forms

- `*gateway-migrate` — interactive discovery mode
- `*gateway-migrate <module-path>` — explicit target
- `*gateway-migrate <module-path> --resume` — resume from state.yaml
- `*gateway-migrate <module-path> --force` — bypass never-clobber

See `skills/gateway-api-migration/SKILL.md` for full halt/resume semantics
and state YAML schema.
```

- [ ] **Step 2: Verify**

```bash
grep -c "^### Step " prompts/zeus/gateway-migrate.md
```
Expected: exactly 8.

- [ ] **Step 3: Commit**

```bash
git add prompts/zeus/gateway-migrate.md
git commit -m "feat(zeus): 新增 *gateway-migrate 管道

以 8 步驟閘門包裝 gateway-api-migration skill：tool check、
discovery、analyze、two-phase convert、validate、report、
runbook、pre-commit hints。skill 承擔所有邏輯，pipeline 只
負責步驟順序與閘門條件。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 15: Register in docs/PROJECT.md, CLAUDE.md, AGENTS.md, GEMINI.md

**Files:**
- Modify: `docs/PROJECT.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `GEMINI.md`

- [ ] **Step 1: Update docs/PROJECT.md Zeus skills table**

Add row to the "Zeus Skills" table between the existing rows:

```markdown
| gateway-api-migration | NGINX Ingress → GKE Gateway API migration (master/minion + standalone) |
```

- [ ] **Step 2: Update docs/PROJECT.md Zeus pipelines table**

Add row to "Zeus Pipelines" table:

```markdown
| *gateway-migrate | gateway-migrate.md | Migrate NGINX Ingress to GKE Gateway API (per-hostname DNS cutover) |
```

- [ ] **Step 3: Update CLAUDE.md Zeus commands table**

The Zeus Commands table is at `## Zeus Commands` (around line 30). Append
this row as the final entry (after `*status`):

```markdown
| *gateway-migrate | `prompts/zeus/gateway-migrate.md` |
```

- [ ] **Step 4: Update AGENTS.md**

AGENTS.md uses a slightly different section header:
`## Zeus Commands (GitOps — Kustomize + ArgoCD)`. Read the file first to
see the exact table format — the columns may differ from CLAUDE.md.
Append a row following the existing pattern in the Zeus commands table.

- [ ] **Step 5: Update GEMINI.md**

GEMINI.md uses the same section header as AGENTS.md
(`## Zeus Commands (GitOps — Kustomize + ArgoCD)`). Read the file first
and match its table format. If GEMINI.md references TOML command files
instead of raw prompt files (e.g., `.gemini/commands/devops/pipelines/zeus-*.toml`),
point the new entry at the TOML created in Task 16 rather than the prompt
from Task 14.

- [ ] **Step 6: Verify all four files mention gateway-migrate**

```bash
grep -l "gateway-migrate" docs/PROJECT.md CLAUDE.md AGENTS.md GEMINI.md
```
Expected: all four filenames listed.

- [ ] **Step 7: Commit**

```bash
git add docs/PROJECT.md CLAUDE.md AGENTS.md GEMINI.md
git commit -m "docs(core): 註冊 *gateway-migrate 至 PROJECT/CLAUDE/AGENTS/GEMINI

於 PROJECT.md 的 Zeus Skills 與 Zeus Pipelines 表格新增
gateway-api-migration skill 與 *gateway-migrate 管道，並
於三個平台薄封裝檔（CLAUDE/AGENTS/GEMINI.md）的指令表同步
新增該指令。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 16: Create Gemini TOML command

**Files:**
- Create: `.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml`

- [ ] **Step 1: Write the TOML**

Match the format of existing `zeus-scaffold.toml`:

```toml
description = "Zeus: Migrate NGINX Ingress to GKE Gateway API"
prompt = """
You are Zeus, the GitOps Engineer. Execute Gateway API Migration.

End-to-end migration from NGINX Ingress (master/minion or standalone
topology) to GKE Gateway API resources. Delegates all logic to the
`gateway-api-migration` skill.

Pipeline steps:
1. Tool check (kustomize, yq required; kubeconform, ingress2gateway optional)
2. Topology discovery (master/minion or standalone)
3. Annotation analysis (classify against references/annotation-map.md)
4. Two-phase conversion:
   4a. Generate common.gateway/ (Gateway + overlays + ArgoCD apps)
   4b. Generate HTTPRoutes alongside minions + idempotent kustomization.yaml edits
5. Validation (kustomize build required; kubeconform, ingress2gateway optional)
6. Render state.yaml + report.md under docs/reports/gateway-migration/<slug>/
7. Print per-hostname DNS cutover runbook
8. Print suggested commit message and git add commands

Invocation forms:
- *gateway-migrate — interactive discovery
- *gateway-migrate <module-path> — explicit target
- *gateway-migrate <module-path> --resume — resume from state.yaml
- *gateway-migrate <module-path> --force — bypass never-clobber

Full details: prompts/zeus/gateway-migrate.md and
skills/gateway-api-migration/SKILL.md
"""
```

- [ ] **Step 2: Verify TOML parses**

```bash
python3 -c "import tomllib; tomllib.load(open('.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml', 'rb'))"
```
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add .gemini/commands/devops/pipelines/zeus-gateway-migrate.toml
git commit -m "feat(gemini): 新增 zeus-gateway-migrate.toml 指令

依 Gemini extension 格式（description + prompt 欄位）為
*gateway-migrate 管道新增 TOML 指令入口，遵循既有 zeus-*.toml
的格式慣例。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 17: Add ingress2gateway to install-tools.sh

**Files:**
- Modify: `scripts/install-tools.sh`

- [ ] **Step 1: Inspect the TOOLS array format**

```bash
sed -n '73,112p' scripts/install-tools.sh
```

Verify the format matches CSV-style entries:
`"binary_name|category|tier|brew_cmd|apt_cmd|pip_cmd|winget_cmd"`

The script iterates this array; adding a new tool means adding one line
to the array, NOT writing a bash install block.

- [ ] **Step 2: Add ingress2gateway entry to the TOOLS array**

Find the "Zeus (GitOps) — Recommended" section (the block starting after
`# Zeus (GitOps) — Recommended` comment, around line 90). Use `Edit` to
insert this new line after the `kubeconform` entry:

Old string (exact match):
```
  "kubeconform|zeus|recommended|brew install kubeconform|||scoop install kubeconform"
```

New string:
```
  "kubeconform|zeus|recommended|brew install kubeconform|||scoop install kubeconform"
  "ingress2gateway|zeus|recommended|brew install ingress2gateway|||"
```

Explanation of fields:
- `ingress2gateway` — binary name
- `zeus` — category (GitOps agent)
- `recommended` — tier (optional, graceful degradation)
- `brew install ingress2gateway` — macOS install
- empty `apt_cmd` — no apt package; user installs via `go install` manually
- empty `pip_cmd` — not a Python tool
- empty `winget_cmd` — no Windows package

- [ ] **Step 3: Verify the script is syntactically valid**

```bash
bash -n scripts/install-tools.sh
```
Expected: no output (success).

- [ ] **Step 4: Verify the array parses correctly**

```bash
bash scripts/install-tools.sh 2>&1 | grep ingress2gateway
```
Expected: output line like `[--] ingress2gateway not installed` (on a
machine without it) or `[OK] ingress2gateway ...` (if already installed).
Either confirms the array entry is being read.

- [ ] **Step 5: Commit**

```bash
git add scripts/install-tools.sh
git commit -m "feat(ci): install-tools.sh 新增 ingress2gateway 選配安裝

為 *gateway-migrate Step 4c（second-opinion cross-check）
新增 ingress2gateway 的選配安裝：macOS 走 brew、Linux 走
go install，失敗時不中斷整體安裝流程。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 18: Version bump to 1.7.0

**Files:**
- Modify: `VERSION`
- Modify: `package.json`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `.gemini/extensions/devops/gemini-extension.json`

- [ ] **Step 1: Use the repo's version-bump helper**

```bash
pnpm version:bump 1.7.0
```

This script exists specifically to sync version across all 5 files. Do not edit them individually.

- [ ] **Step 2: Verify all files match**

```bash
pnpm version:consistency
```
Expected: all-green "versions consistent" output.

```bash
cat VERSION
grep '"version"' package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json .gemini/extensions/devops/gemini-extension.json
```
Expected: every match shows `1.7.0`.

- [ ] **Step 3: Commit**

```bash
git add VERSION package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json .gemini/extensions/devops/gemini-extension.json
git commit -m "chore(release): 版本更新至 1.7.0

同步 5 個版本檔案至 1.7.0：VERSION / package.json /
.claude-plugin/plugin.json / .claude-plugin/marketplace.json /
.gemini/extensions/devops/gemini-extension.json。此版本加入
gateway-api-migration skill 與 *gateway-migrate 管道。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Fixtures and Structure Tests

Tests are structure-level (files exist, YAML valid, cross-references consistent). Running the skill against a fixture to assert golden-output equality is manual because the skill is AI-interpreted, not deterministic code.

### Task 19: Create fixtures directory structure and README

**Files:**
- Create: `tests/gateway-api-migration/README.md`
- Create: `tests/gateway-api-migration/fixtures/` (directory)
- Create: `tests/gateway-api-migration/run-fixtures.sh` (structural validator)

- [ ] **Step 1: Create the directories**

```bash
mkdir -p tests/gateway-api-migration/fixtures
```

- [ ] **Step 2: Write tests/gateway-api-migration/README.md**

```markdown
# gateway-api-migration fixtures

Structural fixtures for the `gateway-api-migration` skill. Each fixture is
a self-contained example with an `input/` tree (Ingress manifests the skill
reads) and an `expected/` tree (Gateway/HTTPRoute output the skill should
produce).

## Running the structural validator

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```

This validator checks:
1. Every fixture has both `input/` and `expected/` directories.
2. Every `*.yaml` file parses as YAML.
3. Every `expected/common.gateway/base/kustomization.yaml` resolves its
   `resources:` entries to files that exist.
4. Every `expected/common.gateway/base/gateway.yaml` has `kind: Gateway`
   and `gatewayClassName: gke-l7-global-external-managed`.
5. Master/minion fixtures have expected HTTPRoute files with matching
   `parentRefs.sectionName` values pointing at the generated Gateway.

## Running end-to-end (manual)

The skill is AI-interpreted. To run end-to-end:

1. Copy a fixture's `input/` tree to a scratch directory.
2. Run `*gateway-migrate` in a Zeus session on the scratch directory.
3. Diff the produced `common.gateway/` + `common.service/overlays/*` against
   the fixture's `expected/` tree.

## Fixture index

| Name | Topology | What it exercises |
|---|---|---|
| standalone-simple | standalone | Baseline: one Ingress, one Service |
| standalone-cors | standalone | Rows 5-8 (CORS → GCPBackendPolicy) |
| standalone-server-snippet | standalone | Row 9a/b/c (server-snippet split) |
| master-minion-minimal | master/minion | 2-service master/minion, idempotent kustomization.yaml edit |
| master-minion-orphan-host | master/minion | Orphan host WARN path |
| master-minion-orphan-minion | master/minion | Orphan minion HALT path |
| mergeable-master | master/minion | Row 4 drop-info (mergeable-ingress-type) |
| eye-of-horus-sample | master/minion | Real-world trimmed sample |
```

- [ ] **Step 3: Write tests/gateway-api-migration/run-fixtures.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

for fixture in "$FIXTURES_DIR"/*/; do
  name="$(basename "$fixture")"
  echo ""
  echo "Fixture: $name"

  # Check 1: both input/ and expected/ exist
  if [ -d "$fixture/input" ]; then
    pass "$name has input/"
  else
    fail "$name missing input/"
  fi

  if [ -d "$fixture/expected" ]; then
    pass "$name has expected/"
  else
    fail "$name missing expected/"
  fi

  # Check 2: all YAML files parse
  while IFS= read -r -d '' yaml; do
    if command -v yq >/dev/null 2>&1; then
      if yq eval '.' "$yaml" >/dev/null 2>&1; then
        pass "$(basename "$yaml") valid YAML"
      else
        fail "$(basename "$yaml") invalid YAML"
      fi
    fi
  done < <(find "$fixture" -name '*.yaml' -print0)

  # Check 3: expected Gateway (when present) has correct gatewayClassName
  gateway_file="$fixture/expected/common.gateway/base/gateway.yaml"
  if [ -f "$gateway_file" ]; then
    if yq eval '.spec.gatewayClassName == "gke-l7-global-external-managed"' "$gateway_file" | grep -q true; then
      pass "$name gateway.yaml has correct gatewayClassName"
    else
      fail "$name gateway.yaml gatewayClassName mismatch"
    fi
  fi
done

echo ""
echo "=========================="
echo "PASS: $PASS  FAIL: $FAIL"
echo "=========================="

[ "$FAIL" -eq 0 ]
```

- [ ] **Step 4: Make the script executable**

```bash
chmod +x tests/gateway-api-migration/run-fixtures.sh
```

- [ ] **Step 5: Verify the script runs (no fixtures yet = empty pass)**

```bash
bash -n tests/gateway-api-migration/run-fixtures.sh
```
Expected: no output (syntax valid).

- [ ] **Step 6: Commit**

```bash
git add tests/gateway-api-migration/
git commit -m "test(gateway): 新增 fixture 目錄結構與結構驗證腳本

- tests/gateway-api-migration/README.md：fixture 索引與
  執行方式
- run-fixtures.sh：結構級驗證（input/expected 存在、YAML
  解析、Gateway gatewayClassName 值）

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 20: Create standalone fixtures

**Files:**
- Create: `tests/gateway-api-migration/fixtures/standalone-simple/input/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-simple/input/app.service.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-simple/expected/common.gateway/base/kustomization.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-simple/expected/common.gateway/base/gateway.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-simple/expected/common.gateway/base/httproute.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-cors/input/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-cors/expected/common.gateway/base/gcpbackendpolicy.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-cors/expected/common.gateway/base/{gateway,httproute,kustomization}.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-server-snippet/input/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/standalone-server-snippet/expected/common.gateway/base/{gateway,httproute,kustomization}.yaml`

- [ ] **Step 1: Create standalone-simple fixture**

Input Ingress (`input/app.ingress.yaml`):

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  tls:
    - hosts:
        - demo.example.com
      secretName: demo-tls
  rules:
    - host: demo.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: demo
                port:
                  number: 80
```

Input Service (`input/app.service.yaml`):

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: demo
  namespace: default
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: demo
```

Expected Gateway (`expected/common.gateway/base/gateway.yaml`):

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: common-gateway
  namespace: default
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: demo-https
      port: 443
      protocol: HTTPS
      hostname: demo.example.com
      allowedRoutes:
        namespaces:
          from: Same
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: demo-tls
```

Expected HTTPRoute (`expected/common.gateway/base/httproute.yaml`):

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: demo
  namespace: default
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: common-gateway
      sectionName: demo-https
  hostnames:
    - demo.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: demo
          port: 80
```

Expected kustomization (`expected/common.gateway/base/kustomization.yaml`):

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: default
resources:
  - gateway.yaml
  - httproute.yaml
```

- [ ] **Step 2: Create standalone-cors fixture**

Input: same as standalone-simple, but with CORS annotations added:

```yaml
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "https://foo.example.com"
    nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"
    nginx.ingress.kubernetes.io/cors-allow-headers: "Content-Type, X-Api-Key"
```

Expected adds `gcpbackendpolicy.yaml`:

```yaml
---
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: demo-cors
  namespace: default
spec:
  targetRef:
    group: ""
    kind: Service
    name: demo
  cors:
    allowOrigins:
      - https://foo.example.com
    allowMethods:
      - GET
      - POST
      - OPTIONS
    allowHeaders:
      - Content-Type
      - X-Api-Key
```

Expected `kustomization.yaml` lists all four resources.

- [ ] **Step 3: Create standalone-server-snippet fixture**

Input Ingress has `server-snippet` with X-* headers + Set-Cookie + path denylist.

Expected HTTPRoute has `filters[].responseHeaderModifier.add` for the three X-* headers, and inline `# TODO(gateway-migrate):` comments for the Set-Cookie and path-denylist lines.

- [ ] **Step 4: Run the structural validator**

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```
Expected: PASS for all three standalone fixtures.

- [ ] **Step 5: Commit**

```bash
git add tests/gateway-api-migration/fixtures/standalone-simple/ \
        tests/gateway-api-migration/fixtures/standalone-cors/ \
        tests/gateway-api-migration/fixtures/standalone-server-snippet/
git commit -m "test(gateway): 新增 3 個 standalone topology fixtures

- standalone-simple：最小化 Ingress → Gateway+HTTPRoute
- standalone-cors：CORS 註解展開為 GCPBackendPolicy
- standalone-server-snippet：row 9 拆分（X-* headers 自動轉
  換；Set-Cookie / path denylist 留 TODO stub）

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 21: Create master-minion fixtures

**Files:**
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/input/common.ingress/base/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/input/common.ingress/base/kustomization.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/input/common.service/overlays/dev/{argocd,grafana}-nginx-ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/input/common.service/overlays/dev/kustomization.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/expected/common.gateway/base/{kustomization,gateway}.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/expected/common.service/overlays/dev/{argocd,grafana}-httproute.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-minimal/expected/common.service/overlays/dev/kustomization.yaml`
- Create: `tests/gateway-api-migration/fixtures/master-minion-orphan-host/**` (similar, with an extra host in master)
- Create: `tests/gateway-api-migration/fixtures/master-minion-orphan-minion/**` (minion without master pair, expected-error-only)
- Create: `tests/gateway-api-migration/fixtures/mergeable-master/**` (master has `mergeable-ingress-type: master` annotation)

- [ ] **Step 1: Create master-minion-minimal fixture — master side**

Master `input/common.ingress/base/app.ingress.yaml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-nginx
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress/mergeable-ingress-type: master
spec:
  rules:
    - host: dev-argocd.example.com
    - host: dev-grafana.example.com
  tls:
    - hosts:
        - dev-argocd.example.com
      secretName: dev-argocd-tls
    - hosts:
        - dev-grafana.example.com
      secretName: dev-grafana-tls
```

Master `input/common.ingress/base/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ingress-nginx
resources:
  - app.ingress.yaml
```

- [ ] **Step 2: Create master-minion-minimal fixture — minion side**

Minion `input/common.service/overlays/dev/argocd-nginx-ingress.yaml`:

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-nginx-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: dev-argocd.example.com
      http:
        paths:
          - backend:
              service:
                name: argocd-server
                port:
                  number: 80
            path: /
            pathType: Prefix
```

Minion `input/common.service/overlays/dev/grafana-nginx-ingress.yaml` (similar, for `dev-grafana.example.com` → `grafana:80` in `monitoring` namespace).

Minion `input/common.service/overlays/dev/kustomization.yaml`:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argocd-nginx-ingress.yaml
  - grafana-nginx-ingress.yaml
```

- [ ] **Step 3: Create master-minion-minimal expected output**

Expected Gateway (`expected/common.gateway/base/gateway.yaml`):

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: common-gateway
  namespace: ingress-nginx
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
    - name: dev-argocd-https
      port: 443
      protocol: HTTPS
      hostname: dev-argocd.example.com
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: ingress-nginx
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: dev-argocd-tls
    - name: dev-grafana-https
      port: 443
      protocol: HTTPS
      hostname: dev-grafana.example.com
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              gateway-access: ingress-nginx
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: dev-grafana-tls
```

Expected HTTPRoute (`expected/common.service/overlays/dev/argocd-httproute.yaml`):

```yaml
---
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
      sectionName: dev-argocd-https
  hostnames:
    - dev-argocd.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 80
```

Similar file for `grafana-httproute.yaml`.

Expected modified kustomization (`expected/common.service/overlays/dev/kustomization.yaml`):

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - argocd-nginx-ingress.yaml
  - grafana-nginx-ingress.yaml
  - argocd-httproute.yaml
  - grafana-httproute.yaml
```

- [ ] **Step 4: Create master-minion-orphan-host fixture**

Master declares `dev-alertmanager.example.com` with a TLS entry, but no
minion file exists for it. Expected output still contains a listener for
the orphan host (migration proceeds with WARN).

- [ ] **Step 5: Create master-minion-orphan-minion fixture (expected-error)**

Minion with `host: dev-unknown.example.com` but no master declares this
host. The fixture has only `input/` (no `expected/`); the validator
should special-case this fixture and skip the `expected/` check.

Update `tests/gateway-api-migration/run-fixtures.sh` to accept a
`fixture.meta.yaml` file that can set `expectError: true`. Add the meta
file to this fixture:

```yaml
# input/fixture.meta.yaml
expectError: true
errorMessage: orphan minion
```

Update the validator to skip the `expected/` check when `expectError:
true` is set.

- [ ] **Step 6: Create mergeable-master fixture**

Same as master-minion-minimal but the master Ingress has
`nginx.ingress/mergeable-ingress-type: master`. Expected output is
identical (the annotation drops; state YAML records it as drop-info).

- [ ] **Step 7: Run the structural validator**

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```
Expected: all fixtures pass structurally.

- [ ] **Step 8: Commit**

```bash
git add tests/gateway-api-migration/fixtures/master-minion-minimal/ \
        tests/gateway-api-migration/fixtures/master-minion-orphan-host/ \
        tests/gateway-api-migration/fixtures/master-minion-orphan-minion/ \
        tests/gateway-api-migration/fixtures/mergeable-master/ \
        tests/gateway-api-migration/run-fixtures.sh
git commit -m "test(gateway): 新增 4 個 master/minion topology fixtures

- master-minion-minimal：2 個 service 的跨 module 遷移
- master-minion-orphan-host：master 宣告但無 minion 配對
  的 host（WARN 路徑）
- master-minion-orphan-minion：minion 無法配對的錯誤路徑
  （透過 fixture.meta.yaml 的 expectError 標記跳過 expected
  檢查）
- mergeable-master：row 4 drop-info 路徑

並擴充 run-fixtures.sh 處理 expectError fixture。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 22: Create eye-of-horus-sample fixture

**Files:**
- Create: `tests/gateway-api-migration/fixtures/eye-of-horus-sample/input/common.ingress/base/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/eye-of-horus-sample/input/common.ingress/overlays/prd/app.ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/eye-of-horus-sample/input/common.service/overlays/prd/{argocd,grafana,airflow}-nginx-ingress.yaml`
- Create: `tests/gateway-api-migration/fixtures/eye-of-horus-sample/input/common.service/overlays/prd/kustomization.yaml`
- Create: `tests/gateway-api-migration/fixtures/eye-of-horus-sample/expected/` (trimmed Gateway + HTTPRoutes)

- [ ] **Step 1: Copy trimmed master from reference repo**

Copy `~/Documents/git_awoo/gitops/sre/eye-of-horus-gitops/common.ingress/base/app.ingress.yaml` verbatim to `input/common.ingress/base/app.ingress.yaml`. Do the same for the `prd` overlay.

Trim down to 3 services: `argocd`, `grafana`, `airflow`. Remove host and TLS entries for all others. Keep the real annotations (including the full `server-snippet` block).

- [ ] **Step 2: Copy trimmed minions**

Copy the three minion files (`argocd-nginx-ingress.yaml`, `grafana-nginx-ingress.yaml`, `airflow-nginx-ingress.yaml`) from `common.service/overlays/prd/` to `input/common.service/overlays/prd/`.

Create a minimal `kustomization.yaml` listing the three minion files.

- [ ] **Step 3: Generate expected output by hand**

This is the highest-fidelity fixture. Expected output must reflect the
real annotations. Key checkpoints:

- Gateway listener uses `certificateRefs[kind: ManagedCertificate, name: prd-<svc>-ingress-nginx-crt]`
- HTTPRoute for each service has `filters[].responseHeaderModifier.add`
  with X-Content-Type-Options, X-XSS-Protection, X-Frame-Options
- HTTPRoute comments include `# TODO(gateway-migrate):` for:
  - Set-Cookie add_header lines
  - The two `location ~ ...` path denylists
- Gateway's listener has `allowedRoutes.namespaces.from: Selector` with
  `gateway-access: ingress-nginx` label

- [ ] **Step 4: Run the structural validator**

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```
Expected: eye-of-horus-sample passes.

- [ ] **Step 5: Commit**

```bash
git add tests/gateway-api-migration/fixtures/eye-of-horus-sample/
git commit -m "test(gateway): 新增 eye-of-horus-sample fixture

以 gitops/sre/eye-of-horus-gitops 實際產出為基礎，精簡為
3 個服務（argocd / grafana / airflow），保留真實 server-snippet
與 ManagedCertificate 結構，作為 end-to-end 高保真度範例。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 23: Extend tests/test-structure.sh with gateway-api-migration checks

**Files:**
- Modify: `tests/test-structure.sh`

- [ ] **Step 1: Add a new section after the existing Zeus skill checks**

Find the section that checks other Zeus skills (look for `kustomize-resource-validation` or similar). Add a new section:

```bash
section "gateway-api-migration skill"

# SKILL.md exists and has frontmatter
if [ -f "$ROOT_DIR/skills/gateway-api-migration/SKILL.md" ]; then
    pass "skills/gateway-api-migration/SKILL.md exists"
    if head -1 "$ROOT_DIR/skills/gateway-api-migration/SKILL.md" | grep -q "^---$"; then
        pass "SKILL.md has YAML frontmatter opener"
    else
        fail "SKILL.md missing YAML frontmatter"
    fi
    if grep -q "^name: gateway-api-migration" "$ROOT_DIR/skills/gateway-api-migration/SKILL.md"; then
        pass "SKILL.md has correct name field"
    else
        fail "SKILL.md name field incorrect"
    fi
else
    fail "skills/gateway-api-migration/SKILL.md missing"
fi

# All 8 Step sections present
step_count=$(grep -c "^## Step " "$ROOT_DIR/skills/gateway-api-migration/SKILL.md" 2>/dev/null || echo 0)
if [ "$step_count" -eq 8 ]; then
    pass "SKILL.md has all 8 Step sections (0-7)"
else
    fail "SKILL.md has $step_count Step sections, expected 8"
fi

# All reference symlinks resolve
for ref in annotation-map master-minion-topology gke-gateway-notes \
           http-routing-guide ingress2gateway-integration \
           migration-from-ingress ingress-nginx-welcome; do
    if [ -f "$ROOT_DIR/skills/gateway-api-migration/references/$ref.md" ]; then
        pass "reference: $ref.md resolves"
    else
        fail "reference: $ref.md broken or missing"
    fi
done

# Template files exist
for tmpl in runbook-template.md httproute-template.yaml manual-review-patterns.md; do
    if [ -f "$ROOT_DIR/skills/gateway-api-migration/references/$tmpl" ]; then
        pass "template: $tmpl exists"
    else
        fail "template: $tmpl missing"
    fi
done

# Pipeline file exists
if [ -f "$ROOT_DIR/prompts/zeus/gateway-migrate.md" ]; then
    pass "prompts/zeus/gateway-migrate.md exists"
else
    fail "prompts/zeus/gateway-migrate.md missing"
fi

# Gemini TOML exists
if [ -f "$ROOT_DIR/.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml" ]; then
    pass "zeus-gateway-migrate.toml exists"
else
    fail "zeus-gateway-migrate.toml missing"
fi

# docs/gateway/ canonical files exist
for doc in annotation-map master-minion-topology gke-gateway-notes \
           http-routing-guide ingress2gateway-integration \
           migrate-from-ingress ingress-nginx-welcome; do
    if [ -f "$ROOT_DIR/docs/gateway/$doc.md" ]; then
        pass "docs/gateway/$doc.md exists"
    else
        fail "docs/gateway/$doc.md missing"
    fi
done

# Typo'd filename must NOT exist
if [ ! -f "$ROOT_DIR/docs/gateway/welcom-Ingress-NGINX.md" ]; then
    pass "docs/gateway/welcom-Ingress-NGINX.md correctly absent (typo'd)"
else
    fail "docs/gateway/welcom-Ingress-NGINX.md still present (should be renamed)"
fi

# *gateway-migrate registered in all platform docs
for md in CLAUDE.md AGENTS.md GEMINI.md docs/PROJECT.md; do
    if grep -q "gateway-migrate" "$ROOT_DIR/$md"; then
        pass "$md mentions gateway-migrate"
    else
        fail "$md missing gateway-migrate reference"
    fi
done
```

- [ ] **Step 2: Run the full test suite**

```bash
pnpm test
```
Expected: every new `[PASS]` line; no `[FAIL]` lines for gateway-api-migration checks.

If there are any `[FAIL]` lines, the gap points at a Task 7-22 step not correctly executed. Fix the gap and re-run.

- [ ] **Step 3: Commit**

```bash
git add tests/test-structure.sh
git commit -m "test(core): test-structure.sh 新增 gateway-api-migration 區段

驗證：
- SKILL.md 存在與 YAML frontmatter 正確
- 8 個 Step 區段齊全
- 7 個 references symlink 可解析
- 3 個 template 檔存在
- prompts/zeus/gateway-migrate.md 存在
- .gemini/commands/.../zeus-gateway-migrate.toml 存在
- 7 個 docs/gateway/ 檔案存在、舊 welcom-Ingress-NGINX.md 已刪
- 4 個平台封裝檔均註冊了 gateway-migrate 指令

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — Release

### Task 24: Update CHANGELOG and full test run

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Prepend v1.7.0 entry to CHANGELOG.md**

```markdown
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
```

- [ ] **Step 2: Run the full test suite one more time**

```bash
pnpm test && pnpm version:consistency
```
Expected: all green.

- [ ] **Step 3: Run the fixture validator**

```bash
bash tests/gateway-api-migration/run-fixtures.sh
```
Expected: all fixtures pass.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(release): CHANGELOG 新增 1.7.0 版本紀錄

摘要本次新增的 gateway-api-migration skill、*gateway-migrate
pipeline、docs/gateway/ 7 份參考文件、tests/gateway-api-migration
8 個 fixtures，以及 ingress2gateway 選配整合與一檔名拼字
修正。

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 25: Release via pnpm release

**Files:**
- No new files; executes the repo's release workflow

- [ ] **Step 1: Dry-run verify release script**

```bash
pnpm release --help 2>&1 || cat scripts/release.sh | head -30
```
Confirm the script is `commit → tag → push` (never auto-publishes — CI handles that).

- [ ] **Step 2: Ensure working tree is clean**

```bash
git status
```
Expected: "nothing to commit, working tree clean". If not, stash or commit any leftover changes before releasing.

- [ ] **Step 3: Run the release**

```bash
pnpm release
```

This should:
1. Verify version consistency (`pnpm version:consistency`)
2. Run tests (`pnpm test`)
3. Create a signed commit (if CHANGELOG or VERSION changed)
4. Create `v1.7.0` tag
5. Push both the commit and the tag to `origin/main`
6. Exit — the `release.yml` GitHub Action takes over from here to publish
   to npm and create a GitHub Release

- [ ] **Step 4: Verify the tag and remote state**

```bash
git log --oneline -3
git tag -l "v1.7.0"
git ls-remote --tags origin | grep v1.7.0
```
Expected: latest commit references 1.7.0; tag exists locally and on remote.

- [ ] **Step 5: Monitor GitHub Actions**

Open `https://github.com/qwedsazxc78/devops-ai-skill/actions` and verify the
release workflow succeeds. If it fails, investigate before any follow-up
work — do not manually fix npm or GitHub Releases.

- [ ] **Step 6: No additional commit**

The release itself is the final step. No further commit needed.

---

## Plan Self-Review

After writing, I ran the review checklist:

**Spec coverage:**
- §1 Overview — Phase 1 Tasks 1-6 produce all referenced docs
- §2 Goals & Non-Goals — all 8 goals appear in Phase 2 SKILL.md tasks; non-goals are encoded as explicit "skip" paths in the skill logic
- §3 Architecture + §3.4 Delivery — Task 7 creates the skill dir; Tasks 14-17 register across platforms
- §4 Outputs — Task 8/10/11 define state YAML, Task 10 defines module output, Task 11 defines report
- §5 Annotation Table — Task 1 (canonical source)
- §6 Pipeline Flow — Tasks 8-12 implement Steps 0-7 in SKILL.md; Task 14 implements the thin pipeline
- §7 ingress2gateway — Task 5 (docs), Task 11 Step 3 (4c logic), Task 17 (install)
- §8 Tool Dependencies — Task 8 Step 0; Task 17 installer
- §9 Testing — Tasks 19-23 cover all fixtures from the spec's fixture list
- §10 docs/gateway rewrite — Tasks 1-6 all new + 2 rewrites
- §11 v2 extensions — not implemented by design (v2)
- §12 Considerations/Risks — baked into design; mitigations exist in the skill logic tasks
- §13 Open Items — none, all locked
- §14 Next Steps — this plan is the answer

**Placeholder scan:** no TBDs, TODOs, "implement later", or "similar to Task N". Each step has exact paths, exact commands, and exact content or outlines with specific spec-section references.

**Type consistency:** All file paths use the same casing (e.g., `gateway-api-migration`, `common.gateway/`, `common.service/overlays/<env>/`). The Gemini TOML path is `.gemini/commands/devops/pipelines/zeus-gateway-migrate.toml` — matches repo convention verified in Task 16. SKILL.md section counts (8 Steps) match the test assertion (Task 23).

---

## Plan complete. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration. Best for a 25-task plan where context bloat is a real concern.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
