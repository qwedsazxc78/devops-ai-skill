---
name: terraform-validate
description: >
  Comprehensive validation and linting of Terraform configurations.
  Covers syntax, formatting, schema validation, cross-file consistency,
  and naming conventions. Use when validating Terraform code, checking
  formatting, or auditing naming conventions.
version: "1.0.0"
---

# Terraform Validate Skill

## Purpose

Comprehensive validation and linting of Terraform configurations for Terraform+Helm platforms. Covers syntax, formatting, schema validation, cross-file consistency, and naming conventions.

## Activation

This skill activates when the user requests:
- Validating Terraform configuration
- Checking formatting / linting
- Verifying cross-file consistency
- Running a pre-commit check
- Auditing naming conventions

## Step 0: Discover Repository Layout

**Do NOT assume hardcoded directory names.** Discover the Terraform root at runtime:

### 0a: Find Terraform Root Directory
Locate directories containing `*.tf` files (excluding `.terraform/` provider cache):
```bash
find . -name "*.tf" -not -path "*/.terraform/*" | xargs dirname | sort -u
```
If multiple directories are found, identify the root (the one containing `backend` or `provider` blocks):
```bash
grep -rl 'backend\s*"\|provider\s*"' --include="*.tf" . | grep -v '.terraform/' | xargs dirname | sort -u
```
Store the result as `<terraform-root>` for all subsequent steps.

### 0b: Find JSON Schema Files (if any)
Search for JSON schema files dynamically:
```bash
find . -name "*.schema.json" -o -name "schema*.json" -o -path "*/schema/*.json" | grep -v '.terraform/'
```
If found, also discover JSON config files that should be validated against them:
```bash
find . -name "*-app.json" -o -name "*.tfvars.json" | grep -v '.terraform/'
```
If no schemas are found, skip JSON schema validation entirely.

### 0c: Find Helm Module Orchestrator (if any)
Search for Terraform files with Helm module blocks (for cross-file consistency checks):
```bash
grep -rl 'source\s*=.*modules.*helm\|helm_release' --include="*.tf" . | grep -v '.terraform/'
```
If not found, skip Helm-specific consistency checks (Steps 4a-4c).

### 0d: Find Identity/IAM Configuration (if any)
```bash
grep -rl 'workload_identity\|google_service_account\|kubernetes_namespace' --include="*.tf" . | grep -v '.terraform/'
```
If not found, skip workload identity checks (Step 4d).

## Workflow

### Step 1: Terraform Format Check

Run `terraform fmt -check -recursive` on the discovered Terraform root.

```bash
cd <terraform-root> && terraform fmt -check -recursive
```

**Output:** List of files that need formatting. Offer to auto-fix with `terraform fmt -recursive`.

### Step 2: Terraform Validate

Run `terraform validate` on the discovered Terraform root.

```bash
cd <terraform-root> && terraform init -backend=false && terraform validate
```

**Note:** Use `-backend=false` since the HTTP backend requires credentials. Validation checks syntax and internal consistency without needing state access.

**Common errors to watch for:**
- Missing required variables
- Invalid resource references
- Module source path errors
- Type constraint violations

### Step 3: JSON Schema Validation

**Skip this step entirely if no schema files were discovered in Step 0b.**

Validate all discovered JSON config files against their corresponding schema files.

**Files to validate:**
- Use the JSON config files and schema files discovered in Step 0b

**Validation approach:**
1. Read the schema file(s) discovered in Step 0b
2. Read each JSON config file
3. Verify all `required` fields are present
4. Verify field types match schema definitions
5. Verify nested object schemas
6. Verify array items match `$def` definitions

**Report:** List any missing fields, type mismatches, or extra fields not in schema.

### Step 4: Cross-File Consistency Checks

#### 4a: Helm Version Consistency

**Skip if no Helm orchestrator was found in Step 0c.**

For each active module in the discovered orchestrator file, verify the version matches across:
1. Orchestrator file -> module block version field
2. Module directory -> variable file version default
3. Version-tracking doc (if any) -> `--version` in helm command

**Dynamic discovery:** For each module directory, find the variable file by checking for `variable.tf`, `variables.tf`, or any `.tf` file containing a version variable. Do NOT rely on a static registry or hardcoded file names.

#### 4b: Module Source Path Consistency

**Skip if no Helm orchestrator was found in Step 0c.**

Verify every `source` path in module blocks points to a directory that actually exists.

#### 4c: Environment Config Completeness

**Skip if no Helm modules were found.**

For modules that use environment-specific config files (e.g., `configs-${var.environment}.yaml`), verify config files exist for all environments the module claims to support.

#### 4d: Workload Identity Alignment

**Skip if no identity/IAM configuration was found in Step 0d.**

Cross-reference the discovered identity file(s):
- Find `local.workload_namespace` or equivalent namespace lists
- Find workload identity module definitions
- Find modules with `depends_on` referencing workload identity resources

Flag any modules that depend on workload identity namespace but aren't in the namespace list, or vice versa.

#### 4e: GKE/Cloud Module Version Consistency

Search for GKE module definitions (`google_container_cluster`) or equivalent cloud provider modules. Verify the `version` is consistent across all files using the same module source.

### Step 5: Naming Convention Audit

Run naming convention checks per NAMING_CONVENTIONS.md:
- Resource naming patterns
- Variable naming patterns
- Module naming patterns
- File naming patterns

### Step 6: TFLint Check

Check if `.tflint.hcl` exists at the repository root.

1. Report current rules from the existing `.tflint.hcl` (see TFLINT_RULES.md for details)
2. Suggest additional rules from TFLINT_RULES.md "Recommended Additions" section
3. Check if TFLint is enabled in `.pre-commit-config.yaml`

### Step 7: Pre-Commit Hook Verification

Check `.pre-commit-config.yaml` status:
1. Verify the file exists and is valid YAML
2. Report which hooks are active vs commented out
3. Suggest enabling commented hooks (tflint, tfsec, detect-secrets) if appropriate

### Step 8: Report

Generate a validation report:

```
## Validation Report

### Format Check
- [PASS/FAIL] terraform fmt — N files need formatting

### Syntax Validation
- [PASS/FAIL] terraform validate — N errors found

### Schema Validation
- [PASS/FAIL] <env>-app.json — compliant / missing field X

### Cross-File Consistency
- [PASS/FAIL] Helm versions — N mismatches
- [PASS/FAIL] Module sources — all paths valid
- [PASS/FAIL] Environment configs — N missing files
- [PASS/FAIL] Workload identity — aligned
- [PASS/FAIL] GKE module version — consistent

### Naming Conventions
- [PASS/WARN] N naming issues found

### Recommendations
- Enable tflint in pre-commit
- Enable tfsec in pre-commit
```

## Light Mode

When invoked from the `*validate` pipeline with "light" security scan:
- Skip Steps 6-7 (TFLint and pre-commit checks)
- Only report critical findings

## Auto-Fix Capabilities

The skill can auto-fix:
- Formatting issues (`terraform fmt`)
- Version mismatches (align to the orchestrator file as source of truth)

The skill CANNOT auto-fix:
- Schema validation errors (require understanding of environment requirements)
- Missing config files (require domain knowledge for values)
- Naming convention violations (may have intentional exceptions)

## Dependencies

- TFLINT_RULES.md — Recommended TFLint rules
- NAMING_CONVENTIONS.md — Extracted naming patterns
