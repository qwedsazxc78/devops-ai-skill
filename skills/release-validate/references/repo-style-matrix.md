# Repo-Style Coverage Matrix

Plain markdown data table read at runtime by
`scripts/check_repo_style_coverage.sh`. Declares which skills need fixtures
for which repo deployment styles. Edit via PR to add new skills or styles.

## Styles

| Style | Definition |
|---|---|
| `kustomize-argocd` | Pure Kustomize + ArgoCD Application manifests (eye-of-horus-gitops shape) |
| `helm-only` | Direct Helm release; no Kustomize, no ArgoCD |
| `mixed` | Some modules Kustomize, some direct Helm |

## Coverage requirements

| Skill | kustomize-argocd | helm-only | mixed |
|---|---|---|---|
| nginx-to-traefik | required | optional | optional |
| nginx-to-gateway | required | optional | optional |
| gateway-api-migration | required | optional | optional |
| ingress-migration-advisor | required | optional | optional |
| ingress-controller-install | required | optional | optional |
| traefik-controller-decommission | required | optional | optional |

## How a fixture counts as "present"

`tests/<skill>/fixtures/` contains at least one subdirectory whose name
matches the style (e.g. `tests/nginx-to-traefik/fixtures/kustomize-argocd-basic/`,
`tests/nginx-to-traefik/fixtures/basic-three-services/` counts as
`kustomize-argocd` by convention since all current fixtures are that style).

For v1.15.0 introduction the script treats EVERY existing fixture as
`kustomize-argocd`-style (the current reality). Gaps surface only when a
new style row is added to the matrix.
