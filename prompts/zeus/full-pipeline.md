# Full Pipeline + YAML/MD Reports

Run the complete validation, security, and analysis pipeline. Each step writes a YAML record. Final markdown summary report is generated.

**Step YAML directory:** `docs/reports/YYYY-MM-DD/` (per-step records)
**Final report:** `docs/reports/devops-zeus-full-check-YYYY-MM-DD.md`

## Pipeline Steps

### Step 1: Pre-Commit Hooks

- Run: `pre-commit run --all-files`
- Write: `docs/reports/YYYY-MM-DD/01-pre-commit.yaml`
- Gate: WARN on failure (continue)

### Step 2: Full Validation

- Discover all Kustomize modules dynamically
- `kustomize build` each module/overlay
- kubeconform, kube-score, polaris, kube-linter, pluto, conftest
- Write: `docs/reports/YYYY-MM-DD/02-validate.yaml`
- Gate: HALT on kustomize build failure

### Step 3: Multi-Tool Security Scan

- checkov, trivy, kube-score, gitleaks, etc.
- Write: `docs/reports/YYYY-MM-DD/03-security-scan.yaml`
- Gate: HALT on HIGH severity findings

### Step 4: Deprecated APIs + Image Drift

- pluto detect-all-in-cluster, image tag analysis
- Write: `docs/reports/YYYY-MM-DD/04-upgrade-check.yaml`
- Gate: WARN on deprecated APIs

### Step 5: CI/CD Pipeline Audit

- Analyze CI config, pre-commit config
- Write: `docs/reports/YYYY-MM-DD/05-pipeline-check.yaml`
- Gate: WARN only

### Step 6: Branch Diff vs Main

- `git diff main...HEAD` rendered manifests
- Risk assessment
- Write: `docs/reports/YYYY-MM-DD/06-diff-preview.yaml`
- Gate: informational

### Step 7: Architecture Diagrams

- Mermaid/D2 diagrams of discovered structure
- Write: `docs/reports/YYYY-MM-DD/07-diagram.yaml`

### Step 8: Final Markdown Report

- Read all step YAML files
- Aggregate into: `docs/reports/devops-zeus-full-check-YYYY-MM-DD.md`
- Failed checks first, warnings second, passed last (collapsed)
- Print report path and summary to user
