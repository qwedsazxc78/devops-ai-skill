# Repository Health Assessment

Comprehensive health assessment of the GitOps repository.

## Pipeline Steps

### Step 1: Full Validation

- All modules, all environments
- Gate: report status

### Step 2: Full Security Scan

- All tools, all modules
- Gate: report status

### Step 3: Secret Inventory

- Discover secrets, check for hardcoded values
- Cross-environment drift analysis
- Gate: WARN on drift

### Step 4: Version + API Check

- Deprecated APIs, outdated images
- Gate: report status

### Step 5: CI/CD Health

- Pipeline config analysis
- Gate: report status

### Step 6: Generate Health Dashboard

```text
+----------------------------------------------+
| GitOps Repository Health Dashboard           |
+----------------------------------------------+
| Kustomize Builds: N/M passing                |
| Security:         N high, N medium           |
| Secrets:          N total, N drifted          |
| API Compat:       N deprecated               |
| CI/CD:            N recommendations           |
| Overall:          HEALTHY / NEEDS ATTENTION   |
+----------------------------------------------+
```
