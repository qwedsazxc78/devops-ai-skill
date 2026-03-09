# Platform Health Check

Comprehensive health assessment of the IaC platform.

## Pipeline Steps

### Step 1: Version Check

- Skill: `helm-version-upgrade` (check-only mode)
- Query latest versions for all active modules
- Report outdated charts with severity
- NO file modifications

### Step 2: Full Security Posture

- Skill: `terraform-security`
- GKE hardening check
- Helm security assessment
- IAM review

### Step 3: Full Consistency Check

- Skill: `terraform-validate`
- Format + validate + schema + consistency
- Naming conventions

### Step 4: Generate Health Dashboard

```text
+--------------------------------------------+
| Cloud Platform Health Dashboard            |
+--------------------------------------------+
| Helm Versions:  N/M up to date             |
| Security:       N high, N medium           |
| Validation:     All checks passing         |
| Overall:        HEALTHY / NEEDS ATTENTION   |
+--------------------------------------------+
```
