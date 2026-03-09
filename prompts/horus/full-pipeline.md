# Full Pipeline Check (with Report)

Execute real commands + code analysis across 10 steps (Step 0-9). Each step writes its own YAML record. At the end, generate a final markdown summary report.

This is the primary pipeline that runs shell commands (terraform fmt, init, validate). Other pipelines like security perform code-level analysis by reading files. validate also runs fmt check but skips init/validate if .terraform is missing.

**Step YAML directory:** `docs/reports/YYYY-MM-DD/` (per-step records)
**Final report:** `docs/reports/devops-horus-full-check-YYYY-MM-DD.md` (markdown summary)

## Pipeline Steps

### Step 0: Discover — Locate Terraform Root Directory

- Find the directory containing *.tf files (do NOT hardcode paths)
- Strategy: `find . -maxdepth 3 -name "*.tf" -not -path "./.terraform/*" | head -1 | xargs dirname`
- Verify the directory contains a backend configuration (e.g., backend.tf or terraform { backend {} })
- Set TF_DIR=<discovered path> for all subsequent steps
- Write: `docs/reports/YYYY-MM-DD/00-discover.yaml`
- Gate: HALT if no *.tf files found

### Step 1: Terraform Format Check

- Run: `cd $TF_DIR && terraform fmt -check -recursive`
- Write: `docs/reports/YYYY-MM-DD/01-terraform-fmt.yaml`

### Step 2: Terraform Init (user-controlled)

- IMPORTANT: terraform init can timeout due to provider downloads or backend configuration. Each project may have a different init method — do NOT assume one way.
- Before running, ASK the user:
  - a) Run `terraform init -backend=false` (skip backend, still downloads providers)
  - b) Skip init (if .terraform/ already exists from a previous init)
  - c) Skip init + validate (jump directly to read-only steps 4-8)
- Gate: WARN on failure (continue to read-only steps)
- Write: `docs/reports/YYYY-MM-DD/02-terraform-init.yaml`

### Step 3: Terraform Validate (requires successful init)

- Run: `cd $TF_DIR && terraform validate`
- SKIP if Step 2 was skipped or failed, or user chose option (c)
- Write: `docs/reports/YYYY-MM-DD/03-terraform-validate.yaml`

### Step 4: Helm Version Consistency

- Read orchestrator TF file, variable(s).tf, helm_install.md per module
- Write: `docs/reports/YYYY-MM-DD/04-helm-versions.yaml`

### Step 5: JSON Schema Validation

- Read infra/schema + all infra/*-app.json
- Write: `docs/reports/YYYY-MM-DD/05-json-schema.yaml`

### Step 6: Module Source Path Check

- Verify all module source directories exist
- Write: `docs/reports/YYYY-MM-DD/06-module-paths.yaml`

### Step 7: Environment Config Completeness

- Verify config files for all environments
- Write: `docs/reports/YYYY-MM-DD/07-env-configs.yaml`

### Step 8: Light Security Scan

- Check for hardcoded secrets, permissive IAM
- Write: `docs/reports/YYYY-MM-DD/08-security-scan.yaml`

### Step 9: Final Markdown Report

- Read all step YAML files (00-08) from `docs/reports/YYYY-MM-DD/`
- Aggregate into: `docs/reports/devops-horus-full-check-YYYY-MM-DD.md`
- Print report path and summary to user

## Per-Step YAML Schema

Each step YAML file follows a consistent structure:

### Discovery type (Step 0):

```yaml
step:
  number: 0
  name: discover_tf_dir
  type: discovery
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | FAIL
  tf_dir: "./my-infra"
  backend_type: "http"
  details: "Found Terraform root at ./application with http backend"
  tf_files_count: 12
```

### Exec type (Steps 1-3):

```yaml
step:
  number: 1
  name: terraform_fmt
  type: exec
  command: "terraform fmt -check -recursive"
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS | FAIL | SKIP
  exit_code: 0
  details: "0 files need formatting"
  output: |
    # raw command stdout (truncate to 50 lines max)
  files: []
  error: null
  skip_reason: null
```

### Read type (Steps 4-8):

```yaml
step:
  number: 4
  name: helm_version_consistency
  type: read
  executed_at: "YYYY-MM-DDTHH:MM:SSZ"
  status: PASS    # PASS if all match, FAIL if mismatch
  details: "N/N modules consistent"
  total_modules: N
  consistent: N
  mismatched: 0
  modules:
    - name: argocd
      gke_package_tf: "9.2.4"
      variable_tf: "9.2.4"
      helm_install_md: "9.2.4"
      status: PASS
```

## Report Rules

1. **Failed checks first** — show full detail tables for FAIL steps
2. **Warnings second** — show detail for WARN steps
3. **Passed checks last** — collapsed in `<details>` to reduce noise
4. **Auto-fix section** — list available fixes with counts
5. **Step YAML links** — reference all per-step YAML files for drill-down
6. `summary.overall` logic:
   - `PASS` — all steps PASS (0 FAIL, 0 WARN)
   - `NEEDS ATTENTION` — 0 FAIL but 1+ WARN
   - `FAIL` — 1+ FAIL
