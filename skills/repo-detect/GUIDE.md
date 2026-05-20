---
name: repo-detect
description: >
  Detects repository type (IaC or GitOps) and recommends the correct agent.
  Auto-triggers on plugin activation. Checks for Terraform, Helm, Kustomize,
  and ArgoCD indicators to determine which agent (Horus or Zeus) is appropriate.
version: "1.0.0"
---

# Repo Type Detection Skill

Automatically detects the repository type and recommends the correct DevOps agent.

## Activation

This skill activates automatically when:
- The devops plugin is first loaded
- A user runs `/devops:horus` or `/devops:zeus` (as a pre-check)
- A user asks which agent to use

## Detection Logic

### Step 1: Scan for IaC Indicators (Horus)

Check for the presence of these files/patterns:

| Indicator | Weight | Check |
|-----------|--------|-------|
| `*.tf` files | HIGH | `find . -name "*.tf" -not -path "./.terraform/*"` |
| `terraform.tfvars` or `*.auto.tfvars` | HIGH | File exists |
| `modules/helm/` directory | HIGH | Directory exists |
| `3-gke-package.tf` or similar Helm module file | MEDIUM | File exists |
| `.terraform.lock.hcl` | MEDIUM | File exists |
| `backend.tf` or backend config | MEDIUM | File contains `backend` block |
| `.tflint.hcl` | LOW | File exists |
| `infra/*.json` (environment configs) | LOW | Files exist |

### Step 2: Scan for GitOps Indicators (Zeus)

Check for the presence of these files/patterns:

| Indicator | Weight | Check |
|-----------|--------|-------|
| `kustomization.yaml` files | HIGH | `find . -name "kustomization.yaml"` |
| `base/` + `overlays/` directory structure | HIGH | Directories exist together |
| `argocd/` directories with Application manifests | HIGH | Contains `kind: Application` |
| ArgoCD Application YAML files | MEDIUM | Files with `apiVersion: argoproj.io` |
| `.pre-commit-config.yaml` with kustomize hooks | LOW | File references kustomize |
| `helmfile.yaml` or `helmfile.d/` | LOW | Helm-based GitOps variant |

### Step 3: Score and Recommend

Calculate scores:
- HIGH indicator = 3 points
- MEDIUM indicator = 2 points
- LOW indicator = 1 point

Decision matrix:

| IaC Score | GitOps Score | Recommendation |
|-----------|-------------|----------------|
| > 0 | 0 | Horus (IaC) — Use `/devops:horus` |
| 0 | > 0 | Zeus (GitOps) — Use `/devops:zeus` |
| > 0 | > 0 | Both detected — show scores, let user choose |
| 0 | 0 | Unknown repo type — list both agents |

### Step 4: Display Result

```
Repository Analysis
====================

Repo: <repo-name> (<git remote origin>)
Path: <working directory>

Detection Results:
| Type   | Score | Key Indicators Found          |
|--------|-------|-------------------------------|
| IaC    | 12    | *.tf (15), modules/helm/, ... |
| GitOps | 0     | (none)                        |

Recommendation: Use Horus (IaC Operations Engineer)
  Command: /devops:horus

Horus specializes in:
  - Terraform validation and formatting
  - Helm chart version management
  - GKE security auditing
  - CI/CD pipeline improvement
```

Or for GitOps repos:

```
Repository Analysis
====================

Repo: <repo-name>
Path: <working directory>

Detection Results:
| Type   | Score | Key Indicators Found                    |
|--------|-------|-----------------------------------------|
| IaC    | 0     | (none)                                  |
| GitOps | 14    | kustomization.yaml (6), overlays/, ...  |

Recommendation: Use Zeus (GitOps Engineer)
  Command: /devops:zeus

Zeus specializes in:
  - Kustomize validation and linting
  - Multi-environment overlay management
  - ArgoCD application management
  - Security scanning for K8s manifests
```

Or for mixed repos:

```
Repository Analysis
====================

Repo: <repo-name>
Path: <working directory>

Detection Results:
| Type   | Score | Key Indicators Found                    |
|--------|-------|-----------------------------------------|
| IaC    | 8     | *.tf (5), modules/helm/                 |
| GitOps | 11    | kustomization.yaml (4), overlays/, ...  |

Both IaC and GitOps patterns detected.

Available Agents:
  1. /devops:horus — IaC Operations (Terraform + Helm + GKE)
  2. /devops:zeus  — GitOps Operations (Kustomize + ArgoCD)

Choose the agent that matches your current task.
```

## Graceful Behavior

- Never block agent activation — this is advisory only
- If detection takes too long, skip and show both agents
- Detection should complete in under 2 seconds (file existence checks only, no heavy scanning)

## Error Handling

### Discovery Failures
- **Empty repository (no files)**: Show both agents as options with a note that no indicators were found.
- **Permission denied on directories**: Skip those directories, continue scanning accessible areas.
- **Very large repository (> 10,000 files)**: Limit `find` depth to `-maxdepth 4` and respect `.gitignore` patterns. Speed is more important than exhaustive scanning.

### Edge Cases
- **Monorepo with multiple IaC/GitOps areas**: If both IaC and GitOps scores are high (both > 5), present both agents and note that this appears to be a monorepo. Suggest the user specify which subdirectory to focus on.
- **Minimum score threshold**: If a type's score is > 0 but < 3 (only LOW indicators), present it as "weak signal" rather than a confident recommendation.
- **Helm-only repo (no Terraform, no Kustomize)**: Score will be low for both types. Suggest Horus if `Chart.yaml` or `helmfile.yaml` is found, as Helm management aligns with Horus capabilities.

## Dry-Run Support

This skill is **read-only** — it only scans files and reports findings. No modifications, no rollback needed.
