---
name: terraform-security
description: >
  Security auditing for GKE platforms managed via Terraform + Helm.
  Covers GKE cluster hardening, Terraform code scanning, Helm chart
  security review, and CIS benchmark alignment. Use when performing
  security audits, checking for hardcoded secrets, or reviewing IAM.
version: "1.0.0"
---

# Terraform Security Skill

## Purpose

Security auditing for GKE platforms managed via Terraform + Helm. Covers GKE cluster hardening, Terraform code scanning, Helm chart security review, and CIS benchmark alignment.

## Activation

This skill activates when the user requests:
- Security audit of the infrastructure
- GKE hardening review
- Helm security assessment
- Checking for hardcoded secrets
- CIS benchmark compliance check

## Step 0: Discover Repository Layout

**Do NOT assume hardcoded file names.** Discover security-relevant files at runtime:

### 0a: Find Cloud/Cluster Configuration
Search for files defining cloud infrastructure resources:
```bash
# GKE / Kubernetes clusters
grep -rl 'google_container_cluster\|google_container_node_pool\|azurerm_kubernetes_cluster\|aws_eks_cluster' --include="*.tf" . | grep -v '.terraform/'

# General cloud resources
grep -rl 'resource\s*"google_\|resource\s*"aws_\|resource\s*"azurerm_' --include="*.tf" . | grep -v '.terraform/'
```
Store discovered files as `<cluster-config-files>`.

### 0b: Find IAM/Identity Configuration
```bash
grep -rl 'google_service_account\|workload_identity\|google_project_iam\|aws_iam_role\|azurerm_role_assignment' --include="*.tf" . | grep -v '.terraform/'
```
Store discovered files as `<identity-config-files>`.

### 0c: Find Helm Module Files
```bash
grep -rl 'helm_release\|helm_install' --include="*.tf" . | grep -v '.terraform/'
```

### 0d: Find Values and Docs with Potential Secrets
```bash
find . -name "*.yaml" -o -name "*.yml" -o -name "*.md" | grep -v '.terraform/' | xargs grep -l 'password\|secret\|token\|credential\|api.key' 2>/dev/null
```

## Workflow

### Step 1: Cloud/Cluster Security Audit

**Skip if no cluster config files were found in Step 0a.**

Analyze the discovered cluster configuration files against the GKE_HARDENING.md checklist (or equivalent cloud provider hardening guide):

1. **Network Security**
   - Private cluster configuration (enable_private_nodes, enable_private_endpoint)
   - Network policy status
   - Master authorized networks
   - VPC native networking (ip_range_pods, ip_range_services)

2. **Node Security**
   - Node image type (COS_CONTAINERD preferred)
   - Auto-repair and auto-upgrade status
   - OAuth scopes (least privilege check)
   - Default service account usage (flag if using compute default SA)

3. **Cluster Security**
   - Security posture mode
   - Binary authorization
   - Pod Security Standards
   - Config connector status
   - GKE Backup Agent

4. **Maintenance**
   - Maintenance window configuration
   - Auto-upgrade windows

Report each finding with severity (Critical/High/Medium/Low/Info) and remediation steps from GKE_HARDENING.md.

### Step 2: Terraform Code Security Scan

Scan all `.tf` files in the Terraform root directory for:

1. **Hardcoded Secrets**
   - Search for patterns: `password`, `secret`, `token`, `key`, `credential` in string literals
   - Check discovered docs and values files (Step 0d) for exposed secrets
   - Check values YAML files for sensitive data

2. **Permissive IAM**
   - Flag overly broad roles in the discovered identity config files (Step 0b):
     - `roles/owner`, `roles/editor`, `AdministratorAccess` → Critical
     - `roles/storage.admin` (vs objectAdmin), overly broad `Action` blocks → Medium
     - Excessive cross-project/cross-account permissions → High
   - Check service account token creator permissions

3. **Insecure Defaults**
   - `create_namespace = true` without RBAC → Info (acceptable in this context)
   - Missing resource limits in Helm values → Medium
   - Missing network policies in Helm values → Medium

4. **State Security**
   - HTTP backend configuration (is it HTTPS?)
   - State file encryption
   - State file access controls

### Step 3: Helm Chart Security Review

For each active module, check against HELM_SECURITY.md:

1. **Service Account Configuration**
   - Does the chart create a service account?
   - Is workload identity properly configured?
   - Are RBAC permissions scoped correctly?

2. **Network Policies**
   - Does the chart support network policies?
   - Are they enabled in the values?
   - Are ingress/egress rules properly scoped?

3. **Image Security**
   - Are images pinned to digests or specific tags?
   - Are images from trusted registries?
   - Is image pull policy set correctly?

4. **Secrets Management**
   - Are secrets managed via external-secrets operator?
   - Any secrets in plain text in values files?
   - Proper secret rotation strategy?

5. **Resource Limits**
   - CPU/memory requests and limits set?
   - PDB (Pod Disruption Budget) configured?

### Step 4: CIS Benchmark Mapping

Map findings to CIS Kubernetes Benchmark controls:

| CIS Control | Description | Status |
|---|---|---|
| 5.1.1 | RBAC enabled | Check |
| 5.2.1 | Pod Security Standards | Check |
| 5.4.1 | Secrets encryption | Check |
| 5.6.1 | Network policies | Check |

Note: `kube-bench` module is deployed for runtime CIS checking. This skill focuses on configuration-level compliance.

### Step 5: Findings Report

Generate report using FINDINGS_TEMPLATE.md format:

```
## Security Audit Report

### Summary
- Critical: N
- High: N
- Medium: N
- Low: N
- Info: N

### Critical Findings
[Details per FINDINGS_TEMPLATE.md]

### Remediation Priority
1. [Highest priority fix]
2. [Next priority fix]
...
```

## Quick Scan Mode

When invoked from `*validate` pipeline:
- Only check for Critical and High findings
- Skip informational items
- Abbreviated report format

## Auto-Fix Capabilities

The skill can offer to auto-fix:
- **Low risk:** Enable network policies in Helm values (if chart supports it)
- **Low risk:** Add resource limits to Helm values
- **Low risk:** Remove hardcoded secrets from discovered docs (replace with `<REDACTED>`)

The skill CANNOT auto-fix (requires user decision):
- IAM role changes (may break functionality)
- GKE cluster-level security settings (requires terraform apply)
- Network policy rules (requires understanding of traffic patterns)

## Hardcoded Secret Detection Patterns

When scanning for secrets in Step 2, use these specific patterns to reduce false positives:

### High Confidence (likely real secrets)
- Base64-encoded strings > 20 chars assigned to `password`, `secret`, `token`, or `key` fields
- Strings matching `AKIA[0-9A-Z]{16}` (AWS access keys)
- Strings matching `ghp_[a-zA-Z0-9]{36}` (GitHub personal tokens)
- Strings matching `gcp_[a-zA-Z0-9-]+\.json` referenced inline (GCP service account keys)
- Private keys: `-----BEGIN (RSA |EC )?PRIVATE KEY-----`

### Medium Confidence (check context)
- Any string literal assigned to a variable named `*password*`, `*secret*`, `*token*`, `*api_key*`
- URLs containing `@` (may contain embedded credentials)
- `.env` files referenced without being in `.gitignore`

### Low Confidence (informational)
- Variables with `sensitive = true` not set (Terraform best practice)
- Secrets not using `data.google_secret_manager_secret_version` or equivalent

### False Positive Exclusions
- Example/placeholder values: `"changeme"`, `"REPLACE_ME"`, `"TODO"`, `"<secret>"`
- Terraform data source references: `data.google_secret_manager_*`
- Variable references: `var.secret_name` (the reference is fine, the value matters)
- Helm value paths: `"{{ .Values.secret }}"` (template, not actual secret)

## Multi-Cloud Awareness

While this skill was designed for GKE, the discovery step (Step 0a) already detects AWS and Azure resources. When non-GKE cloud resources are found:

- **AWS (EKS)**: Check for `aws_eks_cluster` settings — public endpoint access, encryption, logging. Reference AWS CIS benchmarks instead of GKE_HARDENING.md.
- **Azure (AKS)**: Check for `azurerm_kubernetes_cluster` settings — network profile, RBAC, Azure AD integration. Reference Azure CIS benchmarks.
- **Multi-cloud**: If multiple providers detected, run checks for each provider separately and note in the report header which cloud providers were analyzed.
- **Unknown provider**: If no cloud provider is detected (pure Helm/K8s), skip cluster hardening (Step 1) and focus on Steps 2-4.

## Error Handling

### Discovery Failures
- **0 cloud/cluster config files found**: Skip Step 1 (cluster hardening). Continue with Steps 2-5 — code-level security scanning still works.
- **0 Helm module files found**: Skip Step 3 (Helm security). Continue with other steps.
- **0 IAM/identity files found**: Skip IAM portions of Step 2. Continue with other checks.

### Tool Failures
- **`tfsec` not installed**: Skip external tool-based scanning. Rely on pattern-based analysis (Steps 1-4 are all file-reading, no external tools required).
- **`checkov` not installed**: Same as above — skip and note install command.
- **File too large to read**: Skip that file, warn user, suggest using `tfsec` or `checkov` CLI directly.

### Report Generation
- If all steps are skipped due to missing files, still generate a report explaining what was checked and what was skipped. Never produce an empty report.

## Dry-Run Support

This skill is **read-only by default** — security auditing doesn't modify files. The only modifications are auto-fix suggestions:

- When offering auto-fixes (adding network policies, resource limits), always show the exact changes as a diff preview
- Never auto-fix IAM changes, cluster settings, or anything requiring `terraform apply`

## Rollback Strategy

- Auto-fix changes are applied via file edits — use `git checkout -- <file>` to revert
- For Helm values changes, the original values are displayed in the finding report
- Security audit itself is non-destructive — no rollback needed for read-only analysis

## Dependencies

- GKE_HARDENING.md — GKE security checklist with current state
- HELM_SECURITY.md — Per-chart security patterns
- FINDINGS_TEMPLATE.md — Standard report format
