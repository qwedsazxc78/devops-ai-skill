# Diagram Capability Enhancement — Design

**Date:** 2026-06-01
**Status:** Approved — reviewed; implementation plan written at `docs/superpowers/plans/2026-06-01-diagram-enhancement.md`
**Author:** Zeus pipeline maintainers

## Problem

The `*diagram` pipeline (`prompts/zeus/diagram.md`, 29 lines) hand-rolls Mermaid and
covers only Zeus / Kustomize topologies. Meanwhile the richer `painter` skill
(`skills/painter/SKILL.md`, v1.1.0 — HTML artifacts, `basic|detailed` drill-down,
multi-agent parallel scanning) lives disconnected from it. There are **no shipped
sample diagrams** (`docs/diagrams/` holds only `.gitkeep`), the README has no rendered
architecture diagrams (only an ASCII migration block at L292–310), and the GitHub repo
description omits both Antigravity and the diagram/painter capability.

## Goals

1. Make `*diagram` a thin, Zeus/Horus/Migration-aware entry point that **delegates to
   the `painter` skill** as its rendering engine.
2. Ship **3 sample diagrams**, each in **two formats**: Mermaid (renders inline on
   GitHub) and Painter HTML in **`detailed` drill-down mode**.
3. Document the capability in `docs/` (gallery index + usage guide).
4. Surface the diagrams in the README (English + zh-TW + zh-CN) and update the GitHub
   repo description + topics.

## Non-Goals

- No changes to the `painter` skill's engine logic — we consume it, not rewrite it.
- No new CLI tooling; Mermaid/HTML are authored as static artifacts in this round.
- No screenshot automation (HTML is for manual screenshot / browser preview).

## Deliverables

### D1 — Enhanced pipeline `prompts/zeus/diagram.md`
Rewrite (~29 → ~80 lines):
- **Step 0**: delegate to `devops:painter` as the engine; document `--level basic|detailed`,
  `--output`, `--parallel` and the default output paths.
- **Three recipes**:
  - **Zeus** — Kustomize `base/ → overlays/{dev,stg,prd} → ArgoCD Application → GKE`,
    plus the `common.traefik` (controller) / `common.service` (data plane) split.
  - **Horus** (*new — pipeline was Zeus-only*) — Terraform modules + Helm charts →
    ArtifactHub version discovery → GKE.
  - **Migration** — ingress-nginx → Traefik → Gateway API state journey (S0→S3, 7 commands).
- **Dual output contract**:
  - Mermaid → `docs/diagrams/<name>.md`
  - Painter HTML (detailed) → `docs/diagrams/html/<name>/diagram.html` + `.../diagrams/<slug>.html`

### D2 — Three sample diagrams (two formats each)

| Diagram | Mermaid (`docs/diagrams/`) | Painter HTML (detailed) |
|---|---|---|
| Zeus GitOps | `zeus-gitops.md` | `html/zeus/diagram.html` + `html/zeus/diagrams/*.html` |
| Horus IaC | `horus-iac.md` | `html/horus/diagram.html` + `html/horus/diagrams/*.html` |
| Migration journey | `migration-journey.md` | `html/migration/diagram.html` + `html/migration/diagrams/*.html` |

**Mermaid content:**
- `zeus-gitops.md` — `flowchart`: base→overlays→ArgoCD→GKE; controller/data-plane split;
  `*full`/`*review`/`*scaffold` touchpoints.
- `horus-iac.md` — `flowchart`: Terraform+Helm→ArtifactHub→GKE; `*full`/`*upgrade`/`*security`/`*validate` touchpoints.
- `migration-journey.md` — `stateDiagram-v2`: S0 (nginx only) → S1 (both) → S2 (mixed) →
  S3 (Traefik only), edges labeled with the 7 Zeus commands.

**Painter HTML (`detailed`) — each = overview page + drill-down sub-pages:**
- **zeus**: overview + drill pages for `kustomize`, `argocd`, `common-traefik`, `common-service`.
- **horus**: overview + drill pages for `terraform`, `helm`, `gke`, `artifacthub`.
- **migration**: overview + drill pages per state/command (e.g. `install-traefik`,
  `nginx-to-traefik`, `gateway-migrate`, `decommission-nginx`).
- All follow the painter style rules: blue-white tech palette, card UI w/ shadows +
  rounded corners, SVG flow arrows, dark code blocks, `← Back to overview` links,
  relative paths.

### D3 — Docs
- `docs/diagrams/README.md` — **gallery index**: embeds the 3 Mermaid diagrams inline,
  links each Painter HTML overview, links the usage guide.
- `docs/diagrams-guide.md` — **usage doc**: when to use `*diagram` vs `devops:painter`,
  the three recipes, params (`--level/--output/--parallel`), output layout, and how to
  regenerate.

### D4 — README updates (English + zh-TW + zh-CN)
- New **"Architecture Diagrams"** section that embeds the 3 Mermaid diagrams inline and
  links the gallery + HTML + guide.
- Replace/upgrade the ASCII migration block (README L292–310) with the Mermaid
  `migration-journey` (keeping the `*migration-quickstart` pointer).
- Mirror the section into `docs/README.zh-TW.md` and `docs/README.zh-CN.md`.

### D5 — GitHub repo metadata
- **Description** →
  `⚡ Cross-platform DevOps AI Skill Pack — Horus (IaC) + Zeus (GitOps) agents, ingress→Gateway migration & architecture-diagram painter for Claude Code, Codex CLI, Gemini CLI & Antigravity`
- **Topics** → `devops gitops terraform helm kustomize argocd gateway-api claude-code`
- Set via `gh repo edit` (outward-facing — user already authorized in the request).

## File Layout (after)

```
docs/
├── diagrams/
│   ├── README.md                 # gallery (D3)
│   ├── zeus-gitops.md            # mermaid (D2)
│   ├── horus-iac.md              # mermaid (D2)
│   ├── migration-journey.md      # mermaid (D2)
│   └── html/
│       ├── zeus/{diagram.html, diagrams/*.html}
│       ├── horus/{diagram.html, diagrams/*.html}
│       └── migration/{diagram.html, diagrams/*.html}
├── diagrams-guide.md             # usage doc (D3)
prompts/zeus/diagram.md           # enhanced pipeline (D1)
README.md / docs/README.zh-TW.md / docs/README.zh-CN.md   # (D4)
```

## Verification

- `pnpm test` (structure tests) stays green; add no broken links.
- Every Mermaid block parses (manual GitHub preview or mermaid CLI if available).
- Every Painter HTML opens in a browser; overview→detail→back links resolve via relative paths.
- README diagram section renders on GitHub (Mermaid).
- `gh repo view` shows the new description + topics.
- No version bump required (docs/pipeline-only); note as candidate for next feature release.

## Risks / Notes

- **Detailed mode = many HTML files** (~3 overviews + ~12 drill-downs). Mitigate by
  keeping drill-down pages concise and sharing one inline `<style>` pattern per diagram.
- Painter HTML won't render on GitHub — README relies on Mermaid; HTML is linked for
  local/browser/screenshot use. This is by design.
- Localized READMEs must stay structurally in sync (existing project preference).
