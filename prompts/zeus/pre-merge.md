# Pre-Merge Essential Checks

Quick validation before creating a merge request.

## Pipeline Steps

### Step 1: YAML Lint + Kustomize Build

- Discover modules dynamically
- yamllint + `kustomize build` all overlays
- Gate: HALT on build failure

### Step 2: Full Validation

- kubeconform, kube-score, polaris, kube-linter, pluto, conftest
- Gate: HALT on errors

### Step 3: Quick Security Scan

- Quick mode — critical findings only
- Gate: HALT on HIGH severity

### Step 4: Branch Diff + Risk Assessment

- Show changed manifests, risk level
- Gate: informational — present verdict
