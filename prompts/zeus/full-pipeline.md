# Full Pipeline Check (with Report)

Execute Kustomize validation, security scans, and GitOps analysis across 9 steps (Step 0-8). Each step writes its own YAML record. At the end, generate a final markdown summary report.

This is the primary pipeline that runs shell commands (kustomize build, kubeconform, etc.) and code-level analysis. Other pipelines like pre-merge focus on branch diff review only.

**Step YAML directory:** `docs/reports/YYYY-MM-DD/` (per-step records)
**Final report:** `docs/reports/devops-zeus-full-check-YYYY-MM-DD.md`

## Pipeline Steps

### Step 0: Discover — Locate Kustomize Root Structure

- Find all directories containing kustomization.yaml files
- Strategy: `find . -maxdepth 5 -name "kustomization.yaml" -not -path "./.git/*"`
- Identify base vs overlay structure (base/, overlays/*)
- Detect ArgoCD Application manifests if present
- Set KUSTOMIZE_ROOTS=<discovered paths> for all subsequent steps
- Write: `docs/reports/YYYY-MM-DD/00-discover.yaml`
- Gate: HALT if no kustomization.yaml files found

### Step 1: Pre-Commit Hooks

- Run: `pre-commit run --all-files`
- Write: `docs/reports/YYYY-MM-DD/01-pre-commit.yaml`
- Gate: WARN on failure (continue)

### Step 2: Full Validation

- Use discovered KUSTOMIZE_ROOTS from Step 0
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

- Read all step YAML files (00-07) from `docs/reports/YYYY-MM-DD/`
- Aggregate into: `docs/reports/devops-zeus-full-check-YYYY-MM-DD.md`
- Report format: follow `prompts/shared/report-format.md`
- Print report path and summary to user

## Per-Step YAML Schema

Each step YAML file follows a consistent structure:

### Discovery type (Step 0):

```yaml
step:
  number: 0
  name: discover_kustomize_root
  type: discovery
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | FAIL
  details: "Found N kustomization roots with base + M overlays"
  kustomize_roots:
    - path: "./base"
      role: base
    - path: "./overlays/staging"
      role: overlay
    - path: "./overlays/production"
      role: overlay
  argocd_apps_found: true
  total_roots: N
```

### Exec type (Steps 1-3):

```yaml
step:
  number: 1
  name: pre_commit_hooks
  type: exec
  command: "pre-commit run --all-files"
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | FAIL | WARN | SKIP
  exit_code: 0
  details: "All hooks passed"
  output: |
    # raw command stdout (truncate to 50 lines max)
  files: []
  error: null
  skip_reason: null
```

Step 2 (validation) extends exec with per-module results:

```yaml
step:
  number: 2
  name: full_validation
  type: exec
  command: "kustomize build + kubeconform + kube-score + polaris + kube-linter + pluto + conftest"
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS if all modules build & validate, FAIL if any build failure
  details: "N/N modules validated successfully"
  total_modules: N
  passed: N
  failed: 0
  modules:
    - name: base
      kustomize_build: PASS
      kubeconform: PASS
      kube_score: PASS
      polaris: PASS
      status: PASS
    - name: overlays/staging
      kustomize_build: PASS
      kubeconform: WARN
      kube_score: PASS
      polaris: PASS
      status: WARN
  error: null
```

Step 3 (security) extends exec with findings breakdown:

```yaml
step:
  number: 3
  name: security_scan
  type: exec
  command: "checkov + trivy + kube-score + gitleaks"
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | FAIL | WARN
  details: "No HIGH/CRITICAL findings"
  findings:
    critical: 0
    high: 0
    medium: 2
    low: 5
  tools:
    - name: checkov
      status: PASS
      findings_count: 0
    - name: trivy
      status: WARN
      findings_count: 2
    - name: gitleaks
      status: PASS
      findings_count: 0
```

### Read type (Steps 4-7):

```yaml
step:
  number: 4
  name: deprecated_apis_image_drift
  type: read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | WARN | FAIL
  details: "No deprecated APIs found, 0 image drift issues"
  deprecated_apis: []
  image_drift:
    total_images: N
    drifted: 0
    images: []
```

```yaml
step:
  number: 5
  name: cicd_pipeline_audit
  type: read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | WARN
  details: "CI/CD pipeline follows best practices"
  ci_config_found: true
  pre_commit_config_found: true
  recommendations: []
```

```yaml
step:
  number: 6
  name: branch_diff_preview
  type: read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | WARN
  details: "N files changed, risk level: LOW"
  files_changed: N
  risk_level: LOW    # LOW | MEDIUM | HIGH
  changes_summary: |
    # brief diff summary
```

```yaml
step:
  number: 7
  name: architecture_diagrams
  type: read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS
  details: "Generated N diagrams"
  diagrams:
    - type: mermaid
      name: "kustomize-structure"
      content: |
        # mermaid diagram content
```

## Report Rules

See `prompts/shared/report-format.md` for full rules (ordering, status logic, naming convention).
