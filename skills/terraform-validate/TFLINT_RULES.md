# TFLint Rules

Recommended TFLint configuration for GKE platforms managed via Terraform.

## Current Status

TFLint is **commented out** in `.pre-commit-config.yaml`:

```yaml
# - id: terraform_tflint
#   name: Terraform lint
#   args:
#     - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
#     - --hook-config=--delegate-chdir
```

A `.tflint.hcl` file **already exists** at the repository root (`/.tflint.hcl`).

## Current `.tflint.hcl` Configuration

```hcl
config {
  module = true
  force  = false
}

plugin "google" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

rule "terraform_naming_convention" { enabled = true }
rule "terraform_required_version"  { enabled = true }
rule "terraform_required_providers" { enabled = true }
rule "terraform_unused_declarations" { enabled = true }
rule "terraform_typed_variables"    { enabled = true }
rule "terraform_module_pinned_source" { enabled = true }
```

## Recommended Additions

Consider adding these rules to the existing config:

```hcl
# Standard module structure (main.tf, variables.tf, outputs.tf)
rule "terraform_standard_module_structure" {
  enabled = true
}

# Documented variables/outputs (enable after adding descriptions to existing vars)
rule "terraform_documented_variables" {
  enabled = false  # Many existing variables lack descriptions
}
```

## GCP-Specific Rules (google plugin)

### Compute/GKE Rules

| Rule | Severity | Description | Relevance |
|------|----------|-------------|-----------|
| `google_compute_instance_invalid_machine_type` | ERROR | Invalid machine type | Node pool configs |
| `google_container_cluster_invalid_master_version` | ERROR | Invalid K8s version | GKE version in env JSON |
| `google_project_iam_member_invalid_role` | ERROR | Invalid IAM role | Workload identity roles |

### General Rules

| Rule | Severity | Description |
|------|----------|-------------|
| `terraform_deprecated_interpolation` | WARNING | Deprecated `"${var.x}"` syntax |
| `terraform_empty_list_equality` | WARNING | Use `length()` instead of `== []` |
| `terraform_module_pinned_source` | WARNING | Pin module versions |
| `terraform_required_version` | WARNING | Require terraform version constraint |

## Installation

```bash
# Install TFLint
brew install tflint

# Install Google plugin
tflint --init

# Run
cd application && tflint --recursive
```

## Integration with Pre-Commit

To enable in `.pre-commit-config.yaml`, uncomment:

```yaml
- id: terraform_tflint
  name: Terraform lint
  args:
    - --args=--config=__GIT_WORKING_DIR__/.tflint.hcl
    - --hook-config=--delegate-chdir
```

## Known Issues for This Codebase

1. **Module source paths**: TFLint may warn about unpinned local module sources (`./modules/helm/...`). These are intentional local modules and can be excluded.
2. **Variable descriptions**: Most `variables.tf` files in Helm modules lack descriptions. Enable `terraform_documented_variables` only after adding descriptions.
3. **typo in module name**: `gitlb_runner` (missing 'a' in gitlab) — TFLint won't catch this as it's syntactically valid. It's a known naming quirk, not a bug.
