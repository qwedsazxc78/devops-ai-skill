# Diagram Guide — `*diagram` & the Painter skill

The Zeus `*diagram` pipeline turns a repo's architecture into visuals. It is a thin
**recipe layer** over the [`devops:painter`](../skills/painter/SKILL.md) skill, which is
the rendering engine.

## `*diagram` vs `devops:painter`

| Use | When |
|-----|------|
| `*diagram` | You want a ready-made recipe (Zeus / Horus / Migration) with sensible defaults and output paths. |
| `devops:painter` directly | You want full control over components, level, and output for any custom diagram. |

## Parameters (passed through to painter)

| Param | Values | Default | Meaning |
|-------|--------|---------|---------|
| `--level` | `basic` \| `detailed` | `basic` | `detailed` = overview + clickable per-component drill-down pages |
| `--output` | path | `docs/diagrams/html/<name>` | output directory |
| `--parallel` | `auto` \| `off` \| N | `auto` | multi-agent scan; auto-on when components ≥ 5 |

## Recipes

### Zeus (GitOps)

Maps `common.service/base + overlays` → ArgoCD `Application` → GKE, plus the
`common.traefik` controller / `common.service` data-plane split.

- Mermaid: [`diagrams/zeus-gitops.md`](diagrams/zeus-gitops.md)
- HTML: [`diagrams/html/zeus/diagram.html`](diagrams/html/zeus/diagram.html)

### Horus (IaC)

Maps Terraform modules + Helm releases → ArtifactHub version discovery → GKE.

- Mermaid: [`diagrams/horus-iac.md`](diagrams/horus-iac.md)
- HTML: [`diagrams/html/horus/diagram.html`](diagrams/html/horus/diagram.html)

### Migration

The S0→S3 ingress-nginx → Traefik → Gateway API state journey (7 commands).

- Mermaid: [`diagrams/migration-journey.md`](diagrams/migration-journey.md)
- HTML: [`diagrams/html/migration/diagram.html`](diagrams/html/migration/diagram.html)

## Dual-format output

| Format | Path | Renders on GitHub | Use |
|--------|------|:--:|-----|
| Mermaid | `docs/diagrams/<name>.md` | ✅ | README, inline docs |
| Painter HTML | `docs/diagrams/html/<name>/` | ❌ | slides, screenshots, drill-down |

## Regenerate

```text
# Inside Zeus
*diagram                       # interactive: pick recipe + level
# Or call the skill directly
devops:painter --level detailed --output docs/diagrams/html/zeus
```

Optional tools improve fidelity: `d2` (`brew install d2`). Without them painter still
produces HTML — graceful degradation.

See the [gallery](diagrams/README.md) for all rendered samples.
