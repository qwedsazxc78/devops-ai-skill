# iac-template-ai-skill — Design Spec

**Date:** 2026-04-13
**Status:** Approved
**Author:** Awoo Platform Team

## Overview

A minimal GKE Terraform template for beginners to practice Infrastructure as Code with Horus agent review. Mirrors the eye-of-horus production repo patterns at a dramatically reduced scope so learners can focus on fundamentals.

## Goals

1. Teach Terraform + GKE + Helm patterns using the same structure as eye-of-horus
2. Enable immediate use with devops-ai-skill Horus commands (`*validate`, `*full`, `*security`, `*upgrade`)
3. Provide a safe sandbox — local backend, fictional placeholders, zero cloud dependency to explore

## Non-Goals

- Multi-environment support (dev/stg/prd) — suggested as a follow-up exercise
- Workload Identity / IAM — too advanced for first pass
- Disaster recovery configs
- CI/CD pipeline — can be added via `*cicd` command later
- Community GKE module — use native resources for readability

## Project Structure

```
iac-template-ai-skill/
├── application/
│   ├── 0-provider.tf            # Google + Kubernetes + Helm providers, local backend
│   ├── 1-variables.tf           # WORKSPACE_ENV, project_id, region, cluster_name
│   ├── 2-main.tf               # Locals, JSON config loading
│   ├── 3-gke.tf                # GKE cluster + single node pool
│   ├── 3-gke-package.tf        # Helm module orchestrator (2 modules)
│   ├── 10-outputs.tf           # Cluster info + kubectl command
│   ├── infra/
│   │   └── dev-app.json        # Dev environment configuration
│   └── modules/helm/
│       ├── ingress-nginx/
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── configs-dev.yaml
│       └── cert-manager/
│           ├── main.tf
│           ├── variables.tf
│           └── configs-dev.yaml
├── CLAUDE.md                    # Minimal — points to devops-ai-skill
├── Makefile                     # fmt, validate, plan, apply, destroy
├── .pre-commit-config.yaml      # TF format + validate hooks
└── README.md                    # Overview, prerequisites, quick start, exercises
```

## Terraform Configuration

### 0-provider.tf

- **google provider** (~> 6.0): `project` and `region` from variables
- **kubernetes provider**: wired to GKE cluster data (host, token, CA cert)
- **helm provider**: same GKE cluster connection
- **backend**: local (terraform.tfstate) — no remote state for simplicity

### 1-variables.tf

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `WORKSPACE_ENV` | string | `"dev"` | Environment name |
| `project_id` | string | `"iac-template-ai-skill-dev"` | GCP project ID |
| `region` | string | `"asia-east1"` | GCP region |
| `cluster_name` | string | `"iac-template-gke-dev"` | GKE cluster name |

### 2-main.tf

```hcl
locals {
  env    = var.WORKSPACE_ENV
  config = jsondecode(file("${path.module}/infra/${local.env}-app.json"))
}
```

### 3-gke.tf

- `google_container_cluster` — VPC-native, release channel REGULAR, remove default node pool
- `google_container_node_pool` — e2-medium, autoscaling 1-3 nodes, oauth scopes for logging + monitoring

### 3-gke-package.tf

Two module blocks:
- `module "ingress_nginx"` → `./modules/helm/ingress-nginx`
- `module "cert_manager"` → `./modules/helm/cert-manager`

Each receives `env` and `install_version` variables.

### 10-outputs.tf

- `cluster_name` — cluster resource name
- `cluster_endpoint` — API server endpoint
- `cluster_location` — region
- `kubectl_connect_command` — ready-to-paste `gcloud container clusters get-credentials` command

## Helm Module Pattern

Each module under `modules/helm/<name>/` follows:

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = var.repository
  chart            = var.chart
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  values = [
    file("${path.module}/configs-${var.env}.yaml")
  ]
}
```

### variables.tf

| Variable | Type | Description |
|----------|------|-------------|
| `env` | string | Environment name |
| `name` | string | Release name |
| `repository` | string | Helm chart repository URL |
| `chart` | string | Chart name |
| `install_version` | string | Chart version (pinned) |
| `namespace` | string | Kubernetes namespace |

### Helm Versions

| Chart | Version | Repository |
|-------|---------|------------|
| ingress-nginx | 4.12.1 | https://kubernetes.github.io/ingress-nginx |
| cert-manager | v1.17.2 | https://charts.jetstack.io |

## Environment Configuration

### infra/dev-app.json

```json
{
  "vpc_network": "iac-template-vpc",
  "vpc_subnetwork": "iac-template-subnet-dev",
  "ip_range_pods": "iac-template-pods-dev",
  "ip_range_services": "iac-template-svc-dev",
  "node_machine_type": "e2-medium",
  "node_count": 1,
  "max_node_count": 3
}
```

## Supporting Files

### CLAUDE.md

Minimal pointer to devops-ai-skill:
- States this is a Terraform + Helm + GKE repository (Horus agent)
- Lists available commands: `*validate`, `*full`, `*security`, `*upgrade`, `*scaffold`, `*cicd`
- No agent activation logic — just a reference

### README.md

Sections:
1. **What is this** — beginner Terraform template mirroring production patterns
2. **Prerequisites** — Terraform >= 1.0, gcloud CLI, devops-ai-skill installed
3. **Quick start** — clone, `make check`, explore with `*validate`
4. **File structure** — tiered naming explanation with purpose of each tier
5. **Next steps / Exercises** — add stg environment, add a Helm module via `*scaffold`, run `*security` audit, set up CI via `*cicd`

### Makefile

| Target | Command |
|--------|---------|
| `fmt` | `terraform fmt -recursive` |
| `validate` | `cd application && terraform validate` |
| `check` | `fmt` + `validate` |
| `plan` | `cd application && terraform plan` |
| `apply` | `cd application && terraform apply` |
| `destroy` | Confirmation prompt + `terraform destroy` |
| `setup` | `pre-commit install` |

### .pre-commit-config.yaml

Hooks from `antonbabenko/pre-commit-terraform`:
- `terraform_fmt`
- `terraform_validate`

Standard hooks:
- `end-of-file-fixer`
- `trailing-whitespace`

## Horus Compatibility

The template is structured so all Horus skills work out of the box:

| Skill | Works? | Discovery Path |
|-------|--------|---------------|
| terraform-validate | Yes | `application/*.tf` found |
| terraform-security | Yes | Scans all `.tf` files |
| helm-version-upgrade | Yes | `3-gke-package.tf` → `modules/helm/*/variables.tf` |
| helm-scaffold | Yes | Discovers pattern from existing modules |
| cicd-enhancer | Yes | No CI present → recommends adding one |

## Suggested Beginner Exercises

1. Run `*validate` — see the validation report on the template as-is
2. Run `*security` — review security findings and fix them
3. Run `*upgrade` — check if Helm charts have newer versions
4. Add a staging environment: create `infra/stg-app.json`, adjust variables
5. Add a new Helm module via `*scaffold` (e.g., `external-dns`)
6. Set up CI/CD via `*cicd`
