# Repository Type Detection

Analyzes the current repository to determine whether it is an IaC (Terraform+Helm) or GitOps (Kustomize+ArgoCD) repo, and recommends the appropriate agent.

## Steps

### Step 1: Identify Repository

Report the current working directory and git remote origin:

```bash
git remote get-url origin 2>/dev/null || echo "(no remote)"
```

### Step 2: Scan for IaC Indicators

```bash
find . -maxdepth 3 -name "*.tf" -not -path "./.terraform/*" | head -20
ls -d modules/helm/ 2>/dev/null
ls .terraform.lock.hcl 2>/dev/null
ls infra/*.json 2>/dev/null
```

Scoring:
- `*.tf` files found → +3 (HIGH)
- `modules/helm/` exists → +3 (HIGH)
- `.terraform.lock.hcl` exists → +2 (MEDIUM)
- `infra/*.json` exists → +1 (LOW)
- `.tflint.hcl` exists → +1 (LOW)

### Step 3: Scan for GitOps Indicators

```bash
find . -maxdepth 4 -name "kustomization.yaml" | head -20
find . -maxdepth 3 -type d -name "overlays" | head -10
find . -maxdepth 3 -type d -name "base" | head -10
grep -rl "kind: Application" --include="*.yaml" -l 2>/dev/null | head -10
```

Scoring:
- `kustomization.yaml` files found → +3 (HIGH)
- `base/` + `overlays/` structure → +3 (HIGH)
- ArgoCD Application manifests → +3 (HIGH)
- `.pre-commit-config.yaml` with kustomize → +1 (LOW)

### Step 4: Present Results

- IaC only → recommend Horus agent
- GitOps only → recommend Zeus agent
- Both detected → show both with scores, let user choose
- Neither detected → show both agents as options

### Graceful Degradation

- If `git` unavailable, skip remote detection
- If `find`/`grep` fail, fall back to manual file checks
- Always produce a recommendation even with partial data
