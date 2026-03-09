---
name: cicd-enhancer
description: >
  Analyzes and improves CI/CD pipelines for Terraform + Helm platforms.
  Identifies missing stages, recommends quality gates, and generates
  CI job YAML snippets. Use when improving CI/CD pipelines, adding
  quality gates, or optimizing build stages.
version: "1.0.0"
---

# CI/CD Enhancer Skill

## Purpose

Analyzes and improves CI/CD pipelines for Terraform + Helm platforms. Identifies missing stages, recommends quality gates, and generates CI job snippets. Supports multiple CI systems.

## Activation

This skill activates when the user requests:
- CI/CD pipeline review or improvement
- Adding new pipeline stages (lint, security, cost estimation)
- Pipeline optimization
- Quality gate configuration

## Step 0: Discover CI System and Pipeline Files

**Do NOT assume a specific CI system.** Auto-detect at runtime:

### 0a: Detect CI System
Search for CI configuration files in priority order:

| CI System | Detection File(s) |
|-----------|-------------------|
| GitLab CI | `.gitlab-ci.yml` |
| GitHub Actions | `.github/workflows/*.yml` or `.github/workflows/*.yaml` |
| Jenkins | `Jenkinsfile` or `jenkins/` directory |
| CircleCI | `.circleci/config.yml` |
| Azure Pipelines | `azure-pipelines.yml` or `.azure-pipelines/` |
| Bitbucket Pipelines | `bitbucket-pipelines.yml` |

```bash
# Auto-detect CI system
for f in .gitlab-ci.yml Jenkinsfile .circleci/config.yml azure-pipelines.yml bitbucket-pipelines.yml; do [ -f "$f" ] && echo "FOUND: $f"; done
ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null && echo "FOUND: GitHub Actions"
```

Store the detected system as `<ci-system>` and root config as `<ci-root-file>`.

### 0b: Discover All Pipeline Files
Find all CI-related files (includes, templates, shared configs):

**GitLab:**
```bash
grep -r 'include:' .gitlab-ci.yml | grep 'local:' # Find included files
find . -name "*-ci.yml" -o -name "*-ci.yaml" | grep -v node_modules
```

**GitHub Actions:**
```bash
ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
find . -name "action.yml" -o -name "action.yaml" | grep -v node_modules
```

**Other systems:** Read the root config and follow any include/import directives.

### 0c: Discover Terraform Root
Use the same discovery as terraform-validate Step 0a to find `<terraform-root>`.

### 0d: Find Existing Variables/Secrets Config
Look for CI variable definitions, environment configs, and secret references in the discovered pipeline files.

## Current Pipeline Analysis

Read all discovered pipeline files and extract:
- **Stages/jobs** defined and their triggers
- **Variables** (CI variables, environment variables, Terraform variables)
- **Security scanning** already configured (SAST, secret detection, IaC scanning)
- **Deploy targets** and approval gates
- **Caching** configuration
- **Notable patterns** (DR branches, manual gates, template usage)

## Workflow

### Step 1: Pipeline Gap Analysis

Compare current pipeline against recommended stages:

Compare the discovered pipeline against these recommended stages for a Terraform+Helm platform:

| Stage | Check For | Priority | Description |
|-------|-----------|----------|-------------|
| Format check | `terraform fmt` or equivalent job | High | Auto-formatting validation |
| Lint | TFLint or equivalent linter job | High | Static analysis with provider rules |
| Security scan (IaC) | SAST-IaC, tfsec, checkov, trivy | Medium | Infrastructure security scanning |
| Validate | `terraform validate` job | High | Syntax and consistency validation |
| Cost estimation | Infracost or similar | Medium | Cost impact analysis |
| Build/Plan | `terraform plan` job | High | Plan generation with caching |
| Drift detection | Scheduled plan comparison | Medium | Detect out-of-band changes |
| Deploy | `terraform apply` jobs per env | High | Environment-specific deployment |
| Post-deploy verify | Health check after deploy | Low | Smoke test or readiness probe |
| Cleanup | Manual destroy capability | Low | Resource cleanup |

For each stage, report: **Present**, **Partial** (exists but not invoked/incomplete), or **Missing**.

**Note:** If the root CI config defines a stages list, any new stages must be added there.

### Step 2: Generate CI Job Snippets

For each recommended stage, generate ready-to-use CI job snippets for the detected CI system (`<ci-system>`). See PIPELINE_PATTERNS.md for full snippets.

**GitLab CI:** Generate `.gitlab-ci.yml` job definitions using `extends`, `stage`, `script`, `rules`.
**GitHub Actions:** Generate workflow YAML with `jobs`, `steps`, `uses`, `run`, `if` conditions.
**Other systems:** Generate equivalent configuration in the appropriate format.

### Step 3: Quality Gate Definition

Define what blocks deployment vs. what only warns. See QUALITY_GATES.md.

### Step 4: Pipeline Optimization

Analyze and recommend:

1. **Caching** (`.terraform/` caching already configured in `ci/terraform-gitlab-ci.yml` with key `${TF_ROOT}`)
   - Add TFLint plugin cache
   - Add Terraform provider plugin cache (`TF_PLUGIN_CACHE_DIR`)

2. **Parallelism**
   - Run format, lint, and security in parallel
   - Run cost estimation in parallel with plan

3. **Branch strategy alignment**
   - MR-triggered jobs for feature branches
   - Auto-deploy for dev/stg
   - Manual gate for prd

### Step 5: Generate Updated Pipeline

Produce updated pipeline file(s) for the detected CI system incorporating:
- All recommended stages
- Quality gates
- Optimizations
- Preserved existing behavior

**GitLab:** Update the application CI file (discovered in Step 0b) and root `.gitlab-ci.yml` stages list if needed.
**GitHub Actions:** Update or create workflow files in `.github/workflows/`.
**Other systems:** Update the appropriate configuration file(s).

Present as a diff for user review.

## Dependencies

- PIPELINE_PATTERNS.md — CI job YAML snippets
- QUALITY_GATES.md — Quality gate definitions
- terraform-validate skill — Validation rules integrated into CI
- terraform-security skill — Security scan rules integrated into CI
