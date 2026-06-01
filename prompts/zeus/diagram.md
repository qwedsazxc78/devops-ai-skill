# Generate Architecture Diagrams

Generate visual architecture documentation. This pipeline is a **thin recipe layer**
over the `devops:painter` skill (the rendering engine). See
[`docs/diagrams-guide.md`](../../docs/diagrams-guide.md) and the
[gallery](../../docs/diagrams/README.md).

## Step 0: Delegate to the painter skill

The painter skill owns rendering (blue-white style, card UI, SVG arrows, dark code
blocks, `basic|detailed` drill-down, multi-agent parallel scanning). This pipeline
supplies the **recipe** (which components, which flow) and the **output contract**.

Parameters passed through to painter:

| Param | Values | Default |
|-------|--------|---------|
| `--level` | `basic` \| `detailed` | `basic` |
| `--output` | path | `docs/diagrams/html/<name>` |
| `--parallel` | `auto` \| `off` \| N | `auto` |

If the user does not pick a recipe, ask which one (Zeus / Horus / Migration) and
whether they want `basic` or `detailed`.

## Step 1: Detect repository type & parse structure

- Run `prompts/shared/repo-detect.md` to detect IaC vs GitOps.
- Discover modules, overlays, ArgoCD apps (GitOps) or Terraform modules + Helm releases
  (IaC). Map dependencies.

## Step 2: Pick a recipe

### Zeus (GitOps) — `--output docs/diagrams/html/zeus`

`common.service/base + overlays/{dev,stg,prd}` → ArgoCD `Application` → GKE, plus the
`common.traefik` controller / `common.service` data-plane split. Components:
kustomize, argocd, common-traefik, common-service.

### Horus (IaC) — `--output docs/diagrams/html/horus`

Terraform modules + Helm releases → ArtifactHub version discovery → GKE. Components:
terraform, helm, gke, artifacthub.

### Migration — `--output docs/diagrams/html/migration`

S0→S1→S2→S3 ingress-nginx → Traefik → Gateway API journey (7 commands). Components:
install-traefik, nginx-to-traefik, gateway-migrate, decommission-nginx.

## Step 3: Render (dual format)

- **Mermaid** → `docs/diagrams/<name>.md` (`flowchart` for Zeus/Horus,
  `stateDiagram-v2` for Migration). Renders inline on GitHub.
- **Painter HTML** → `docs/diagrams/html/<name>/diagram.html` (+ `diagrams/<slug>.html`
  drill-downs when `--level detailed`). Invoke `devops:painter` with the recipe's
  component inventory.
- Workflow flowcharts (optional): CI/CD, deployment, sync/reconciliation flow.

## Step 4: Output & index

- Save Mermaid to `docs/diagrams/`, HTML under `docs/diagrams/html/<name>/`.
- Update / link the [gallery](../../docs/diagrams/README.md).
- Print the overview path and tell the user to open `diagram.html` in a browser.
