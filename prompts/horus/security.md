# Security Audit Pipeline

Full security audit by reading and analyzing files (no CLI tool execution).

## Pipeline Steps

### Step 1: Full Security Audit

- Skill: `terraform-security`
- GKE cluster hardening check
- IAM and workload identity review
- Helm chart security assessment (all modules)
- Terraform code scan (secrets, permissions)

### Step 2: Cross-Reference Findings

- Skill: `terraform-validate`
- Verify findings against validation rules
- Check for configuration inconsistencies
- Map findings to CIS benchmarks

### Step 3: Generate Findings Report

- Use FINDINGS_TEMPLATE.md format
- Severity classification
- Remediation steps for each finding

### Step 4: Offer Remediation Actions

1. Auto-fix low-risk items (formatting, redacting secrets from docs)
2. Generate issues/tasks for high-risk items
3. Show detailed remediation for specific findings
