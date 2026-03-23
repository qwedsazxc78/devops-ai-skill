# New Helm Module Pipeline

Scaffold a new Helm module with full validation and security checks.

## Pipeline Steps

### Step 1: Gather Inputs and Generate

- Skill: `helm-scaffold`
- Ask for chart name, repo, version, namespace
- Select pattern (simple/standard/workload-identity/OCI/multi)
- Generate all module files
- Register in orchestrator TF file
- Register in helm_install.md
- Update identity TF file if workload identity needed

### Step 2: Validate Generated Module

- Skill: `terraform-validate`
- terraform fmt on new files
- terraform validate
- Cross-file consistency check

### Step 3: Security Check

- Skill: `terraform-security`
- Review generated RBAC/SA config
- Check for security best practices
- Report any concerns

### Step 4: Generate Commit Message

- `feat(helm): add <chart-name> module`
- List all created files

### Step 5: Offer Next Actions

1. Run `terraform plan -target=module.<chart-name>`
2. Create branch and push
3. Stop here
