---
name: helm-scaffold
description: >
  Generates new Helm module directories following established patterns.
  Ensures consistency with existing modules and registers new modules
  across all required files. Use when adding new Helm charts or
  scaffolding module structures.
version: "1.0.0"
---

# Helm Scaffold Skill

## Purpose

Generates new Helm module directories following established patterns in Terraform+Helm codebases. Ensures consistency with existing modules and registers the new module across all required files.

## Activation

This skill activates when the user requests:
- Adding a new Helm chart to the platform
- Scaffolding a new module
- Creating module files for a new chart

## Step 0: Discover Repository Layout

**Do NOT assume a fixed directory structure.** Discover the Helm module conventions at runtime:

### 0a: Find Existing Helm Module Directory
Search for directories containing `helm_release` resources or Helm chart configs:
```bash
grep -rl 'helm_release\|resource.*helm' --include="*.tf" . | grep -v '.terraform/' | xargs dirname | sort -u
```
This identifies the module directory pattern (e.g., `modules/helm/<name>/`, `modules/<name>/`, `helm/<name>/`).

### 0b: Find the Helm Module Orchestrator File
Search for the Terraform file that registers Helm modules:
```bash
grep -rl 'source\s*=.*modules.*helm\|module.*helm' --include="*.tf" . | grep -v '.terraform/'
```
Store as `<orchestrator-file>` (e.g., `3-gke-package.tf`, `main.tf`, `helm.tf`).

### 0c: Analyze Existing Module Patterns
Read 2-3 existing modules to discover the conventions used in this repo:
- Variable naming: `install_version` vs `chart_version` vs `version`
- File naming: `variable.tf` vs `variables.tf`, `main.tf` structure
- Values file patterns: `common.yaml` + `configs-{env}.yaml`, or `values.yaml` + `values-{env}.yaml`
- Resource naming: `helm_release.this` vs `helm_release.<name>`
- `depends_on` patterns used in the orchestrator file

### 0d: Find Version-Tracking Documentation (if any)
```bash
find . -name "*.md" -not -path "./.terraform/*" | xargs grep -l '\-\-version\|helm.*install\|helm.*upgrade' 2>/dev/null
```
Store as `<version-doc>` if found. New modules should be registered here.

### 0e: Find Identity/Workload Identity File (if any)
```bash
grep -rl 'workload_identity\|google_service_account' --include="*.tf" . | grep -v '.terraform/'
```
Store as `<identity-file>` if found. Needed when `workload_identity = true`.

## Workflow

### Step 1: Gather Inputs

Ask the user for:

| Input | Required | Default | Example |
|-------|----------|---------|---------|
| Chart name | Yes | — | `redis` |
| Helm repository URL | Yes | — | `https://charts.bitnami.com/bitnami` |
| Chart version | Yes | — | `17.11.3` |
| Namespace | Yes | Chart name | `redis` |
| Release name | No | Chart name | `redis` |
| Environments | No | `dev,stg,prd` | `dev,stg,prd` |
| DR support | No | `true` | `true` or `false` |
| Workload identity | No | `false` | `true` (needs SA name + roles) |
| CRDs | No | `false` | `true` if chart needs `installCRDs` |
| Shared namespace | No | `false` | `true` if using existing namespace like `monitoring` |

### Step 2: Select Pattern

Based on inputs, select from 5 module patterns defined in MODULE_PATTERNS.md:

| Pattern | When to Use |
|---------|------------|
| **Simple** | No env-specific config, minimal setup (like keda) |
| **Standard** | Env-specific configs, DR support (like argocd) |
| **Workload Identity** | Needs GCP SA with `yamlencode` injection (like loki) |
| **OCI** | Chart from OCI registry, no `repository` field (like litellm) |
| **Multi-Instance** | Same chart deployed multiple times (like gitlab-runner) |

### Step 3: Generate Module Files

Create the new module directory following the pattern discovered in Step 0a (e.g., `modules/helm/<chart-name>/` or whatever convention the repo uses). Generate files matching the conventions from Step 0c:

#### 3a: `main.tf`
- `helm_release` resource (use the naming convention discovered in Step 0c, e.g., `this` or `<chart-name>`)
- Repository URL, chart name, version, namespace
- Values file loading (concat/compact pattern based on DR + workload identity)
- CRD set block if needed
- Timeout for long-deploying charts

#### 3b: Variable file (use naming convention from Step 0c: `variables.tf` or `variable.tf`)
- `name` — string with default matching chart name
- `namespace` — string with default matching namespace input
- Version variable (use the naming convention from Step 0c: `install_version`, `chart_version`, or `version`) — string with default matching version input
- `environment` — string, no default (if env configs needed)
- `dr` — bool, no default (if DR support)
- `project_id` — string, no default (if workload identity)
- Any chart-specific variables

#### 3c: `common.yaml`
- Base Helm values shared across environments
- Resource requests/limits template
- Service account configuration (if applicable)
- Network policy template (if applicable)

#### 3d: `configs-{env}.yaml` (per environment)
- Environment-specific overrides
- Typically: replica counts, resource sizes, ingress hosts
- Placeholder values with TODO comments

#### 3e: `configs-{env}-dr.yaml` (if DR support)
- DR-specific overrides
- Typically: reduced replicas, DR-specific endpoints

### Step 4: Register in Orchestrator File

Add a module block to the discovered `<orchestrator-file>` (from Step 0b), following the established pattern from existing modules:

```hcl
module "<chart-name>" {
  name            = "<release-name>"
  source          = "<discovered-module-path>/<chart-name>"  # Match Step 0a pattern
  install_version = "<version>"  # Use the version variable name from Step 0c
  namespace       = "<namespace>"
  environment     = local.environment
  dr              = local.dr
  depends_on      = [module.gke]
}
```

Adjust `depends_on` based on:
- Workload identity -> add `kubernetes_namespace.workload_identity`
- Depends on keda -> add `module.keda`
- Depends on cert-manager -> add `module.cert-manager`

### Step 5: Register in Version-Tracking Doc (if found)

**Skip if no version doc was discovered in Step 0d.**

Add a new section to `<version-doc>` with the manual helm install command:

```markdown
# <chart-name>

\`\`\`bash
helm repo add <repo-name> <repo-url>
helm repo update

helm upgrade --install <release-name> <repo-name>/<chart-name> --create-namespace --version <version> -n <namespace> --values common.yaml --values configs-dev.yaml
\`\`\`
```

### Step 6: Update Workload Identity (if needed)

**Skip if no identity file was discovered in Step 0e.**

If workload identity is required:

1. Add namespace to the workload namespace list in `<identity-file>`
2. Add workload identity module block following existing patterns in that file

### Step 7: Summary

List all created/modified files and suggest next steps:
1. Run `terraform validate`
2. Run `terraform plan -target=module.<chart-name>`
3. Review generated values files
4. Test with `terraform apply -target=module.<chart-name>`

## Dependencies

- MODULE_PATTERNS.md — Reference implementations for each pattern
