# Validation Pipeline

Full validation with format check, file analysis, and consistency verification.

## Pipeline Steps

### Step 0: Discover Terraform Root Directory

- Same as full pipeline Step 0
- Set TF_DIR for all subsequent steps

### Step 1: Full Validation

- Skill: `terraform-validate`
- `cd $TF_DIR && terraform fmt -check -recursive`
- `cd $TF_DIR && terraform validate` (syntax + schema) — requires init; skip if .terraform missing
- JSON schema validation (infra/*.json)
- Cross-file consistency (versions, sources, configs)
- Naming convention audit

### Step 2: Light Security Scan

- Skill: `terraform-security`
- Critical findings only
- Hardcoded secrets check
- Abbreviated security report

### Step 3: Present Pass/Fail Report

- Format: category + status + details
- Overall pass/fail verdict

### Step 4: Offer Fixes

1. Auto-fix formatting issues
2. Auto-fix version mismatches
3. List items requiring manual review
