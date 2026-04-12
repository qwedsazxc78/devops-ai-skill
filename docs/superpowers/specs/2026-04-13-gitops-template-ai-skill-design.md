# Design: gitops-template-ai-skill

## Overview

A standalone, buildable Kustomize + ArgoCD practice repository for beginners. Mirrors the production pattern from `llmo-service-api` with all company-specific values replaced by generic placeholders.

**Goal:** Provide a complete, valid GitOps project that beginners can explore, modify, and validate using the Zeus agent (`*full`, `*review`, etc.) from the `devops-ai-skill` plugin.

**Location:** `/Users/MH/Documents/git_awoo/gitops-template-ai-skill` (standalone git repo)

## File Structure

```
gitops-template-ai-skill/
├── README.md
├── .yamllint.yml
├── .yamlfmt
├── argocd/
│   ├── dev.yaml
│   ├── stg.yaml
│   └── prd.yaml
├── base/
│   ├── kustomization.yaml
│   ├── app.deployment.yaml
│   ├── app.service.yaml
│   ├── app.ingress.yaml
│   ├── app.hpa.yaml
│   └── app.pdb.yaml
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── app.deployment.yaml
│   │   ├── app.ingress.yaml
│   │   └── env/
│   │       ├── app.env
│   │       └── secrets.env
│   ├── stg/
│   │   ├── kustomization.yaml
│   │   ├── app.deployment.yaml
│   │   ├── app.ingress.yaml
│   │   └── env/
│   │       ├── app.env
│   │       └── secrets.env
│   └── prd/
│       ├── kustomization.yaml
│       ├── app.deployment.yaml
│       ├── app.hpa.yaml
│       ├── app.ingress.yaml
│       └── env/
│           ├── app.env
│           └── secrets.env
└── scripts/
    └── validate.sh
```

## Design Decisions

### Service Identity

- **Service name:** `gitops-template-ai-skill` (used in all resource names, labels, selectors)
- **Namespace:** `gitops-template-ai-skill`
- **Naming convention:** `app: gitops-template-ai-skill` label on all resources

### Container Configuration

- **Image:** `nginx:1.25` — universally available, no registry auth required
- **Container port:** `80` (nginx default)
- **Health check path:** `/` (nginx returns 200 on root)
- **Image pull policy:** `Always` in dev/stg, omitted in prd (defaults to `IfNotPresent` for tagged images)

### Base Manifests

Replicate the exact same K8s resource types as the reference:

| File | Kind | Notes |
|------|------|-------|
| `app.deployment.yaml` | Deployment | RollingUpdate strategy, liveness/readiness probes, preStop hook |
| `app.service.yaml` | Service | ClusterIP, port 80 → container port 80 |
| `app.ingress.yaml` | Ingress | nginx ingress class, generic host |
| `app.hpa.yaml` | HorizontalPodAutoscaler | CPU + memory targets at 75% |
| `app.pdb.yaml` | PodDisruptionBudget | minAvailable: 1 |

### Per-Environment Overlays

| Aspect | dev | stg | prd |
|--------|-----|-----|-----|
| CPU request | 100m | 200m | 250m |
| Memory request | 128Mi | 256Mi | 512Mi |
| CPU limit | 200m | 400m | 500m |
| Memory limit | 256Mi | 512Mi | 1Gi |
| HPA min/max | 1/1 (from base) | 1/1 (from base) | 2/3 (patched) |
| Image tag (via kustomize `images`) | `latest` | `stable` | `v1.0.0` |
| Ingress host | `dev-gitops-template.example.com` | `stg-gitops-template.example.com` | `prd-gitops-template.example.com` |

**prd-only patches:** `app.hpa.yaml` (scales to 2-3 replicas), matching reference pattern where only prd patches HPA.

### Overlay Kustomization Pattern

Each overlay follows the reference convention:
- `resources: [../../base]`
- `patches:` for deployment + ingress (+ hpa in prd)
- `configMapGenerator` from `env/app.env`
- `secretGenerator` from `env/secrets.env`
- `images:` block to override tag

### ArgoCD Application Manifests

Per-environment Application CRDs in `argocd/`:
- **source.repoURL:** `https://github.com/your-org/gitops-template-ai-skill.git`
- **source.path:** `overlays/{env}`
- **destination.server:** `https://kubernetes.default.svc`
- **syncPolicy:** automated with prune + selfHeal + PruneLast + CreateNamespace

### Environment Variables

**app.env** (per environment):
- `ENVIRONMENT={dev,stg,prd}`
- `APP_NAME=gitops-template-ai-skill`
- `APP_PORT=80`
- `LOG_LEVEL={debug,info,warning}`

**secrets.env** (placeholder only):
- `API_KEY=CHANGE_ME`
- `DB_PASSWORD=CHANGE_ME`

### Omitted from Template

| Item | Reason |
|------|--------|
| `.gitlab-ci.yml` | Company-specific CI; not portable |
| `.pre-commit-config.yaml` | Requires local tool setup; not beginner-friendly |
| `scripts/dns-create.sh`, `scripts/ingress-*.sh` | Company-specific networking scripts |
| `overlays/template/` | Extra complexity; 3 concrete environments are sufficient for learning |
| AGENTS.md / CLAUDE.md | User brings their own tooling |

### Included Tooling

- `.yamllint.yml` — Copied from reference for YAML linting consistency
- `.yamlfmt` — Copied from reference for YAML formatting consistency
- `scripts/validate.sh` — Runs `kustomize build` on all 3 overlays to verify validity

### README

Bilingual (繁體中文 primary, English section). Contents:
1. What this repo is (GitOps practice template)
2. Directory structure with brief explanation of each layer
3. How to validate locally (`kustomize build overlays/<env>`)
4. How to use with Zeus agent for automated review

## Validation Criteria

The template is correct when:
1. `kustomize build overlays/dev` succeeds
2. `kustomize build overlays/stg` succeeds
3. `kustomize build overlays/prd` succeeds
4. Zeus `*review` or `*full` produces a clean report (no structural errors)
5. No real secrets, IPs, or company-specific values remain
