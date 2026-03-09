---
name: yaml-fix-suggestions
description: >
  Auto-trigger skill that activates when YAML files in Kustomize module directories are modified.
  Checks formatting, Kubernetes label compliance, kustomization.yaml references, and build validation.
  Reports only when issues are found.
version: "1.0.0"
---

# YAML Fix Suggestions -- Auto-trigger Skill

Automatically activates when YAML files in Kustomize module directories are modified.

## Activation

**Trigger:** Any `.yaml` or `.yml` file is created or edited inside a Kustomize module directory (any directory containing `base/` and `overlays/` structure).

**Exclude:** Files under `.claude/`, `.bmad-*/`, tool/agent configuration directories, and any paths excluded by a local `.yamllint.yml`.

## Instructions

After the user edits a YAML file, perform these checks silently and only report if issues are found.

### 1. Formatting Check

Read the modified file and check against the repo's `.yamllint.yml` configuration (if present). Fall back to these defaults if no `.yamllint.yml` exists:

- **Indentation:** 2-space indent, sequences indented (`indent-sequences: true`)
- **Trailing whitespace:** Not allowed
- **Line length:** 120 characters (or no limit if the repo disables it)
- **Document start marker:** Optional
- **Duplicate keys:** Not allowed

If formatting issues are found, suggest running the repo's formatter. Example:

```bash
pre-commit run yamlfmt --files <modified-file>
```

If `pre-commit` is not configured, suggest `yamllint` directly:

```bash
yamllint <modified-file>
```

### 2. Label Compliance Check

For any resource with a `metadata:` section, verify standard Kubernetes labels exist.

**Recommended Kubernetes labels (check for presence of at least these 4):**

| Label | Description |
|-------|-------------|
| `app.kubernetes.io/name` | Application name |
| `app.kubernetes.io/component` | Component type (e.g., `service-account`, `ingress`, `deployment`) |
| `app.kubernetes.io/part-of` | Higher-level system or platform |
| `app.kubernetes.io/managed-by` | Management tool (e.g., `kustomize`, `helm`) |

**Optional organizational labels (warn if absent):**

| Label | Description |
|-------|-------------|
| `team` | Owning team |
| `cost-center` | Cost allocation identifier |
| `environment` | Deploy target (e.g., `dev`, `stg`, `prd`) |

**Note:** Labels inherited via Kustomize `commonLabels` in base or overlay `kustomization.yaml` count as present. Check the relevant `kustomization.yaml` chain before reporting missing labels.

If labels are missing, suggest the specific labels to add with values inferred from the resource type, namespace, and file path context.

### 3. Kustomize Reference Check

Check the `kustomization.yaml` in the same directory as the edited file. If the edited file is not referenced as a `resources` entry or a `patches` entry (by `path`), warn:

> WARNING: `<filename>` is not referenced in `<directory>/kustomization.yaml`. It may be orphaned and will not be included in the Kustomize build.

### 4. Build Validation

Discover the available environments by listing subdirectories under `overlays/` in the same Kustomize module.

If the edited file is under an overlay directory (e.g., `<module>/overlays/dev/`), identify the affected module and environment, then suggest running:

```bash
kustomize build <module>/overlays/<env>
```

If the edited file is under a `base/` directory, suggest building all discovered environments for the affected module:

```bash
kustomize build <module>/overlays/<env1>
kustomize build <module>/overlays/<env2>
# ... for each environment discovered under overlays/
```

## Output Format

Only show output if at least one check produces a WARN or FAIL status. Use this format:

```
YAML Fix Suggestions for <filename>

| # | Check     | Status | Details                          |
|---|-----------|--------|----------------------------------|
| 1 | Format    | OK     | No issues found                  |
| 2 | Labels    | WARN   | Missing: team, cost-center       |
| 3 | Reference | OK     | Listed in kustomization.yaml     |
| 4 | Build     | WARN   | Suggest: kustomize build ...     |

Suggested fix: pre-commit run yamlfmt --files <file>
```

If all checks pass, do not produce any output.
