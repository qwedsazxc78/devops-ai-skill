# Helm Upgrade Pipeline

Safely upgrade Helm chart versions with validation and security checks.

## Pipeline Steps

### Step 1: Check Latest Versions

- Skill: `helm-version-upgrade`
- Read orchestrator TF file, query ArtifactHub
- Present comparison table
- Get user approval for specific upgrades

### Step 2: Apply Atomic 3-File Updates

- Skill: `helm-version-upgrade`
- Update orchestrator TF file
- Update modules/helm/<name>/variable(s).tf
- Update modules/helm/helm_install.md
- One module at a time, verify each update

### Step 3: Validate Changed Files

- Skill: `terraform-validate`
- Discover TF_DIR (same as full pipeline Step 0)
- `cd $TF_DIR && terraform fmt -check`
- `cd $TF_DIR && terraform validate` (skip if .terraform missing)
- Cross-file consistency check
- Halt on any validation error

### Step 4: Quick Security Scan

- Skill: `terraform-security`
- Check changed modules for new vulnerabilities
- Verify no new hardcoded secrets introduced
- Report any new findings

### Step 5: Generate Summary and Commit Message

- List all changes with old → new versions
- Generate commit message: `feat(helm): upgrade <modules> to latest versions`
- Include ticket number if provided

### Step 6: Offer Next Actions

1. Run `terraform plan -var="WORKSPACE_ENV=dev"`
2. Create branch and push
3. Stop here (changes are local)
