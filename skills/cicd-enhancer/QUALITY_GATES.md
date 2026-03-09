# Quality Gates

Defines what blocks deployment vs. what only warns for Terraform + Helm CI/CD pipelines.

## Gate Definitions

### Gate 1: Format (Blocking)

| Check | Blocks Deploy? | Rationale |
|-------|---------------|-----------|
| `terraform fmt -check` | Yes | Non-formatted code should never merge |
| YAML syntax check | Yes | Invalid YAML breaks Helm deployments |
| End-of-file fixer | No (auto-fixed) | Pre-commit handles this |
| Trailing whitespace | No (auto-fixed) | Pre-commit handles this |

### Gate 2: Lint (Warning → Blocking)

| Check | Phase 1 (now) | Phase 2 (later) | Rationale |
|-------|--------------|-----------------|-----------|
| TFLint core rules | Warning | Blocking | Many existing violations need cleanup first |
| TFLint GCP rules | Warning | Blocking | May flag existing valid patterns |
| Naming conventions | Warning | Warning | Style preference, not security |

**Promotion criteria:** When existing violations reach zero, promote from Warning to Blocking.

### Gate 3: Security (Blocking for Critical/High)

| Check | Severity | Blocks Deploy? | Rationale |
|-------|----------|---------------|-----------|
| Trivy/tfsec CRITICAL | Critical | Yes | Immediate exploitation risk |
| Trivy/tfsec HIGH | High | Yes | Significant security gap |
| Trivy/tfsec MEDIUM | Medium | No (warn in MR) | Defense-in-depth, not urgent |
| Trivy/tfsec LOW | Low | No | Best practice only |
| Hardcoded secrets | Critical | Yes | Secret exposure |
| Private key detection | Critical | Yes | Key compromise |
| Large file check | Medium | Yes (>1MB) | Prevent binary/credential commits |

### Gate 4: Validation (Blocking)

| Check | Blocks Deploy? | Rationale |
|-------|---------------|-----------|
| `terraform validate` | Yes | Invalid config cannot deploy |
| JSON schema validation | Yes | Invalid env config breaks cluster |
| Module source paths | Yes | Missing modules fail apply |

### Gate 5: Plan Review (Environment-Dependent)

| Environment | Gate | Rationale |
|-------------|------|-----------|
| dev, dev-dr | Auto-deploy on merge | Fast iteration |
| stg | Auto-deploy on merge | Staging validation |
| prd, prd-dr | Manual approval required | Production safety |

### Gate 6: Cost Estimation (Informational)

| Check | Blocks Deploy? | Rationale |
|-------|---------------|-----------|
| Cost increase > 20% | No (comment on MR) | Awareness only |
| New resource costs | No (comment on MR) | Awareness only |
| Cost decrease | No (celebrate!) | Positive reinforcement |

### Gate 7: Post-Deploy (Informational)

| Check | Blocks? | Rationale |
|-------|---------|-----------|
| Node health | No (alert) | Post-deploy verification |
| Pod status | No (alert) | Catch deployment failures |
| Helm release status | No (alert) | Verify chart deployment |

## Environment-Specific Gate Matrix

| Gate | MR | dev | stg | prd |
|------|-----|-----|-----|-----|
| Format | Block | Block | Block | Block |
| Lint | Warn | Warn | Warn | Block |
| Security (CRIT/HIGH) | Block | Block | Block | Block |
| Security (MED/LOW) | Warn | Skip | Skip | Warn |
| Validate | Block | Block | Block | Block |
| Plan review | Show diff | Auto | Auto | Manual |
| Cost estimation | Show | Skip | Skip | Show |
| Post-deploy verify | N/A | Run | Run | Run |

## Implementation Phases

### Phase 1: Foundation (Immediate)
- Enable format check (blocking)
- Enable terraform validate (blocking, already exists)
- Enable security scan for CRITICAL only
- Keep all others as warnings

### Phase 2: Harden (1-2 months)
- Promote security scan to block HIGH
- Enable TFLint as warning
- Add cost estimation to MR
- Add drift detection schedule

### Phase 3: Mature (3-6 months)
- Promote TFLint to blocking
- Enable SAST-IaC template
- Add post-deploy verification
- Enable detect-secrets baseline

## MR Comment Templates

### Security Finding

```markdown
## Security Scan Results

| Severity | Count | Status |
|----------|-------|--------|
| Critical | 0 | PASS |
| High | 1 | FAIL |
| Medium | 3 | WARN |

### Blocking Findings
- **HIGH**: Permissive IAM role in `3-gke-identity.tf:45`

> This MR is blocked by HIGH severity security findings. Please fix before merging.
```

### Cost Estimation

```markdown
## Cost Impact

| Resource | Monthly Before | Monthly After | Change |
|----------|---------------|---------------|--------|
| GKE nodes | $1,200 | $1,350 | +$150 (+12.5%) |

> Cost increase is within acceptable range (<20%).
```
