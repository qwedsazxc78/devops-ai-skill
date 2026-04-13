# iac-template-ai-skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a minimal GKE Terraform template at `/Users/MH/Documents/git_awoo/infra-iac/iac-template-ai-skill/` that mirrors eye-of-horus patterns for beginner practice with Horus agent review.

**Architecture:** Tiered Terraform files (`0-` through `10-`) with JSON-driven environment config, 2 Helm modules (ingress-nginx, cert-manager) in `modules/helm/`, local backend, single dev environment. Supporting files: Makefile, pre-commit, CLAUDE.md, README.

**Tech Stack:** Terraform (>= 1.0), Google Cloud Provider (~> 6.0), Helm, GKE

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `application/0-provider.tf` | Create | Google + K8s + Helm providers, local backend |
| `application/1-variables.tf` | Create | 4 input variables with defaults |
| `application/2-main.tf` | Create | Locals block, JSON config loading |
| `application/3-gke.tf` | Create | GKE cluster + node pool (native resources) |
| `application/3-gke-package.tf` | Create | Helm module orchestrator (2 modules) |
| `application/10-outputs.tf` | Create | 4 outputs including kubectl command |
| `application/infra/dev-app.json` | Create | Dev environment JSON config |
| `application/modules/helm/ingress-nginx/main.tf` | Create | helm_release for ingress-nginx |
| `application/modules/helm/ingress-nginx/variables.tf` | Create | Module input variables |
| `application/modules/helm/ingress-nginx/configs-dev.yaml` | Create | Dev values override |
| `application/modules/helm/cert-manager/main.tf` | Create | helm_release for cert-manager |
| `application/modules/helm/cert-manager/variables.tf` | Create | Module input variables |
| `application/modules/helm/cert-manager/configs-dev.yaml` | Create | Dev values override |
| `CLAUDE.md` | Create | Minimal pointer to devops-ai-skill |
| `Makefile` | Create | fmt, validate, check, plan, apply, destroy, setup |
| `.pre-commit-config.yaml` | Create | TF fmt + validate + standard hooks |
| `README.md` | Create | Overview, prerequisites, quick start, exercises |
| `.gitignore` | Create | Terraform ignores |

---

### Task 1: Initialize project and create Terraform core files

**Files:**
- Create: `iac-template-ai-skill/application/0-provider.tf`
- Create: `iac-template-ai-skill/application/1-variables.tf`
- Create: `iac-template-ai-skill/application/2-main.tf`
- Create: `iac-template-ai-skill/application/infra/dev-app.json`
- Create: `iac-template-ai-skill/.gitignore`

- [ ] **Step 1: Create project directory and .gitignore**

```bash
mkdir -p /Users/MH/Documents/git_awoo/infra-iac/iac-template-ai-skill/application/infra
cd /Users/MH/Documents/git_awoo/infra-iac/iac-template-ai-skill
git init
```

`.gitignore`:
```
# Terraform
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
.terraform.lock.hcl
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 2: Create 0-provider.tf**

```hcl
##################################################################################
# CONFIGURATION
##################################################################################
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

##################################################################################
# PROVIDERS
##################################################################################
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.default.access_token
  }
}
```

- [ ] **Step 3: Create 1-variables.tf**

```hcl
##################################################################################
# VARIABLES
##################################################################################
variable "WORKSPACE_ENV" {
  description = "Environment name (dev, stg, prd)"
  type        = string
  default     = "dev"
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "iac-template-ai-skill-dev"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-east1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "iac-template-gke-dev"
}
```

- [ ] **Step 4: Create 2-main.tf**

```hcl
##################################################################################
# LOCALS
##################################################################################
locals {
  env    = var.WORKSPACE_ENV
  config = jsondecode(file("${path.module}/infra/${local.env}-app.json"))
}
```

- [ ] **Step 5: Create infra/dev-app.json**

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

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Terraform core files (provider, variables, locals, env config)"
```

---

### Task 2: Create GKE cluster and outputs

**Files:**
- Create: `iac-template-ai-skill/application/3-gke.tf`
- Create: `iac-template-ai-skill/application/10-outputs.tf`

- [ ] **Step 1: Create 3-gke.tf**

```hcl
##################################################################################
# GKE CLUSTER
##################################################################################
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Remove default node pool — we manage our own
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native cluster
  networking_mode = "VPC_NATIVE"
  network         = local.config.vpc_network
  subnetwork      = local.config.vpc_subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = local.config.ip_range_pods
    services_secondary_range_name = local.config.ip_range_services
  }

  # Release channel
  release_channel {
    channel = "REGULAR"
  }

  # Deletion protection (disable for dev template)
  deletion_protection = false
}

##################################################################################
# NODE POOL
##################################################################################
resource "google_container_node_pool" "default" {
  name     = "default-pool"
  location = var.region
  cluster  = google_container_cluster.primary.name

  initial_node_count = local.config.node_count

  autoscaling {
    min_node_count = local.config.node_count
    max_node_count = local.config.max_node_count
  }

  node_config {
    machine_type = local.config.node_machine_type

    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}
```

- [ ] **Step 2: Create 10-outputs.tf**

```hcl
##################################################################################
# OUTPUTS
##################################################################################
output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location (region)"
  value       = google_container_cluster.primary.location
}

output "kubectl_connect_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${google_container_cluster.primary.location} --project ${var.project_id}"
}
```

- [ ] **Step 3: Commit**

```bash
git add application/3-gke.tf application/10-outputs.tf
git commit -m "feat: add GKE cluster, node pool, and outputs"
```

---

### Task 3: Create Helm modules (ingress-nginx + cert-manager)

**Files:**
- Create: `application/modules/helm/ingress-nginx/main.tf`
- Create: `application/modules/helm/ingress-nginx/variables.tf`
- Create: `application/modules/helm/ingress-nginx/configs-dev.yaml`
- Create: `application/modules/helm/cert-manager/main.tf`
- Create: `application/modules/helm/cert-manager/variables.tf`
- Create: `application/modules/helm/cert-manager/configs-dev.yaml`

- [ ] **Step 1: Create ingress-nginx module**

`modules/helm/ingress-nginx/main.tf`:
```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  values = [
    file("${path.module}/configs-${var.env}.yaml")
  ]
}
```

`modules/helm/ingress-nginx/variables.tf`:
```hcl
variable "env" {
  description = "Environment name"
  type        = string
}

variable "name" {
  description = "Helm release name"
  type        = string
  default     = "ingress-nginx"
}

variable "install_version" {
  description = "Helm chart version"
  type        = string
  default     = "4.12.1"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "ingress-nginx"
}
```

`modules/helm/ingress-nginx/configs-dev.yaml`:
```yaml
# ingress-nginx dev environment values
controller:
  replicaCount: 1
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 250m
      memory: 256Mi
  service:
    type: LoadBalancer
```

- [ ] **Step 2: Create cert-manager module**

`modules/helm/cert-manager/main.tf`:
```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  values = [
    file("${path.module}/configs-${var.env}.yaml")
  ]
}
```

`modules/helm/cert-manager/variables.tf`:
```hcl
variable "env" {
  description = "Environment name"
  type        = string
}

variable "name" {
  description = "Helm release name"
  type        = string
  default     = "cert-manager"
}

variable "install_version" {
  description = "Helm chart version"
  type        = string
  default     = "v1.17.2"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "cert-manager"
}
```

`modules/helm/cert-manager/configs-dev.yaml`:
```yaml
# cert-manager dev environment values
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 100m
    memory: 128Mi
```

- [ ] **Step 3: Commit**

```bash
git add application/modules/
git commit -m "feat: add Helm modules (ingress-nginx, cert-manager)"
```

---

### Task 4: Create Helm orchestrator

**Files:**
- Create: `application/3-gke-package.tf`

- [ ] **Step 1: Create 3-gke-package.tf**

```hcl
##################################################################################
# Helm Packages
##################################################################################
module "ingress_nginx" {
  source          = "./modules/helm/ingress-nginx"
  name            = "ingress-nginx"
  install_version = "4.12.1"
  env             = local.env

  depends_on = [google_container_cluster.primary, google_container_node_pool.default]
}

module "cert_manager" {
  source          = "./modules/helm/cert-manager"
  name            = "cert-manager"
  install_version = "v1.17.2"
  env             = local.env

  depends_on = [google_container_cluster.primary, google_container_node_pool.default]
}
```

- [ ] **Step 2: Commit**

```bash
git add application/3-gke-package.tf
git commit -m "feat: add Helm package orchestrator (ingress-nginx, cert-manager)"
```

---

### Task 5: Create supporting files (Makefile, pre-commit, CLAUDE.md)

**Files:**
- Create: `Makefile`
- Create: `.pre-commit-config.yaml`
- Create: `CLAUDE.md`

- [ ] **Step 1: Create Makefile**

```makefile
.PHONY: help setup fmt validate check plan apply destroy

.DEFAULT_GOAL := help

## help: Show this help message
help:
	@echo "iac-template-ai-skill - Terraform Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make setup       - Install pre-commit hooks"
	@echo ""
	@echo "Validation:"
	@echo "  make fmt         - Format Terraform files"
	@echo "  make validate    - Validate Terraform configuration"
	@echo "  make check       - Format + validate"
	@echo ""
	@echo "Deployment:"
	@echo "  make plan        - Create Terraform plan"
	@echo "  make apply       - Apply Terraform changes"
	@echo "  make destroy     - Destroy infrastructure (with confirmation)"
	@echo ""

## setup: Install pre-commit hooks
setup:
	@echo "Setting up pre-commit hooks..."
	pre-commit install
	@echo "Pre-commit hooks installed!"

## fmt: Format Terraform files
fmt:
	terraform -chdir=application fmt -recursive

## validate: Validate Terraform configuration
validate:
	terraform -chdir=application validate

## check: Format + validate
check: fmt validate

## plan: Create Terraform plan
plan:
	terraform -chdir=application plan

## apply: Apply Terraform changes
apply:
	terraform -chdir=application apply

## destroy: Destroy infrastructure with confirmation
destroy:
	@echo "WARNING: This will destroy all infrastructure!"
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	terraform -chdir=application destroy
```

- [ ] **Step 2: Create .pre-commit-config.yaml**

```yaml
# Pre-commit hooks for Terraform
# Install: pre-commit install
# Run manually: pre-commit run --all-files

repos:
  # Terraform formatting and validation
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.1
    hooks:
      - id: terraform_fmt
        name: Terraform format
        description: Rewrites all Terraform configuration files to canonical format
        files: ^application/.*\.tf$
        args:
          - --args=-recursive

      - id: terraform_validate
        name: Terraform validate
        description: Validates all Terraform configuration files
        files: ^application/.*\.tf$
        exclude: ^application/modules/
        args:
          - --hook-config=--retry-once-with-cleanup=true
          - --tf-init-args=-upgrade

  # Standard hooks
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-yaml
        name: Check YAML syntax
        args: ['--unsafe']

      - id: end-of-file-fixer
        name: Fix end of files

      - id: trailing-whitespace
        name: Trim trailing whitespace

      - id: check-added-large-files
        name: Check for large files
        args: ['--maxkb=1000']

      - id: check-merge-conflict
        name: Check for merge conflicts

      - id: detect-private-key
        name: Detect private keys
```

- [ ] **Step 3: Create CLAUDE.md**

```markdown
# CLAUDE.md

This is a **Terraform + Helm + GKE** repository (Horus agent).

## Skills

Install [devops-ai-skill](https://github.com/qwedsazxc78/devops-ai-skill) for AI-assisted IaC operations.

## Horus Commands

| Command | Purpose |
|---------|---------|
| `*validate` | Validate Terraform configuration |
| `*full` | Full pipeline check (format, validate, security, versions) |
| `*security` | Security audit (GKE hardening, IAM, Helm) |
| `*upgrade` | Check and upgrade Helm chart versions |
| `*scaffold` | Generate a new Helm module |
| `*cicd` | Analyze and improve CI/CD pipeline |
```

- [ ] **Step 4: Commit**

```bash
git add Makefile .pre-commit-config.yaml CLAUDE.md
git commit -m "feat: add Makefile, pre-commit config, and CLAUDE.md"
```

---

### Task 6: Create README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

```markdown
# iac-template-ai-skill

A minimal GKE Terraform template for beginners to practice Infrastructure as Code. Mirrors production patterns from [eye-of-horus](https://github.com/qwedsazxc78/eye-of-horus) at a reduced scope.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [pre-commit](https://pre-commit.com/#install)
- [devops-ai-skill](https://github.com/qwedsazxc78/devops-ai-skill) (for Horus agent)

## Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd iac-template-ai-skill

# Install pre-commit hooks
make setup

# Validate the Terraform configuration
make check

# Explore with Horus agent (requires devops-ai-skill)
# *validate    — validate Terraform config
# *full        — full pipeline check
```

## File Structure

```
application/
├── 0-provider.tf         # Tier 0: Providers and backend
├── 1-variables.tf        # Tier 1: Input variables
├── 2-main.tf             # Tier 2: Locals and config loading
├── 3-gke.tf              # Tier 3: GKE cluster resources
├── 3-gke-package.tf      # Tier 3: Helm package orchestrator
├── 10-outputs.tf         # Tier 10: Outputs
├── infra/
│   └── dev-app.json      # Environment-specific configuration
└── modules/helm/
    ├── ingress-nginx/    # NGINX Ingress Controller
    └── cert-manager/     # TLS Certificate Manager
```

### Tiered Naming Convention

| Tier | Purpose | Example |
|------|---------|---------|
| 0 | Provider and backend configuration | `0-provider.tf` |
| 1 | Input variables | `1-variables.tf` |
| 2 | Locals, data sources, API enablement | `2-main.tf` |
| 3 | Core resources (GKE, Helm packages) | `3-gke.tf` |
| 4-9 | Supporting resources (IAM, networking, storage) | — |
| 10 | Outputs | `10-outputs.tf` |

## Exercises

Practice with the Horus agent from [devops-ai-skill](https://github.com/qwedsazxc78/devops-ai-skill):

1. **Validate** — Run `*validate` to see the validation report
2. **Security audit** — Run `*security` to review findings and fix them
3. **Upgrade Helm** — Run `*upgrade` to check for newer chart versions
4. **Add staging** — Create `infra/stg-app.json` and deploy a second environment
5. **Add a module** — Run `*scaffold` to generate a new Helm module (e.g., `external-dns`)
6. **Set up CI/CD** — Run `*cicd` to generate a CI pipeline

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with structure guide and exercises"
```
