# MR Review Pipeline

Automated merge request review with verdict.

## Pipeline Steps

### Step 1: Determine Changed Files

- `git diff main...HEAD --name-only`
- Identify affected modules and environments
- Gate: informational

### Step 2: YAML Lint Changed Files

- yamllint on changed files
- Gate: HALT on errors

### Step 3: Validate Affected Modules

- `kustomize build` only changed modules
- kubeconform, kube-score on changed manifests
- Gate: HALT on errors

### Step 4: Quick Security Scan

- Scan changed files only
- Gate: HALT on HIGH

### Step 5: API Compatibility

- Check changed manifests for deprecated APIs
- Gate: WARN on deprecated

### Step 6: Rendered Diff

- Before/after manifest comparison
- Risk assessment
- Gate: informational

### Step 7: Impact Diagram

- Show affected components
- Gate: informational

### Step 8: Verdict

- APPROVE / REQUEST CHANGES / NEEDS DISCUSSION
- Summary of all findings
- Suggested commit message improvements
