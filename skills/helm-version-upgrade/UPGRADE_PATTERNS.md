# Upgrade Patterns

Exact patterns for finding and replacing version strings in each of the 3 files. Used by the helm-version-upgrade skill for atomic updates.

## File 1: `3-gke-package.tf`

### Standard Module Block Pattern

```hcl
module "<tf_module_name>" {
  ...
  install_version = "<version>"
  ...
}
```

**Find pattern:** Within the `module "<tf_module_name>"` block, locate `install_version = "<old_version>"`.

**Replace with:** `install_version = "<new_version>"`

### Edge Cases

#### Multi-Instance (gitlab-runner)

Two separate module blocks reference the same source:

```hcl
module "gitlb_runner" {
  source          = "./modules/helm/gitlab-runner"
  name            = "common-pool"
  install_version = "0.84.1"       # ← Update this
  ...
}

module "gitlb_runner_env" {
  source          = "./modules/helm/gitlab-runner"
  name            = "common-pool-env"
  install_version = "0.84.1"       # ← AND this
  ...
}
```

**MUST update both blocks.** They share the same chart so versions must stay in sync.

#### Commented Module (n8n)

```hcl
# module "n8n" {
#   ...
#   install_version = "2.0.1"
#   ...
# }
```

**Do NOT update.** Skip commented modules. Report their existence in the version check output.

#### Version with Comment (langfuse)

```hcl
  install_version = "1.5.19" # Using the version from variables.tf default, but explicit here is good too
```

**Update only the version value**, preserve any trailing comments.

#### Nightly/Pre-release Version (litellm)

```hcl
  install_version = "1.81.8-nightly-latest"
```

Handle non-standard semver. The full string including suffix is the version.

## File 2: `modules/helm/<name>/variable(s).tf`

### Standard Variable Block Pattern

```hcl
variable "install_version" {
  type    = string
  default = "<version>"
}
```

**Find pattern:** Check if `variable.tf` exists (singular); if not, use `variables.tf` (plural). Locate the `install_version` variable block and its `default` value.

**Replace with:** `default = "<new_version>"`

### File Name Lookup

| Module | Variable File |
|--------|-------------|
| grafana | `variable.tf` |
| external-secrets | `variable.tf` |
| All others | `variables.tf` |

### Edge Cases

#### Missing default

Some modules may not have a default value for `install_version`:

```hcl
variable "install_version" {
  type = string
}
```

If no default exists, **add one**:

```hcl
variable "install_version" {
  type    = string
  default = "<new_version>"
}
```

## File 3: `modules/helm/helm_install.md`

### Standard Helm Command Pattern

Each module has a markdown section with a helm upgrade command:

```bash
helm upgrade --install <release_name> <repo>/<chart> --version <version> -n <namespace> ...
```

**Find pattern:** `--version <old_version>` within the section for this module.

**Replace with:** `--version <new_version>`

### Section Identification

Modules are identified by their markdown heading:

```markdown
# argocd

\`\`\`bash
helm upgrade --install argocd argo/argo-cd --version 9.2.4 ...
\`\`\`
```

### Edge Cases

#### OCI Charts

Thanos and litellm use OCI format:

```bash
# thanos
helm upgrade --install thanos oci://registry-1.docker.io/bitnamicharts/thanos \
--version 17.3.1 ...

# litellm
helm upgrade --install litellm oci://docker.litellm.ai/berriai/litellm-helm --version 1.81.8-nightly-latest ...
```

The `--version` flag is the same, just the repo reference differs.

#### n8n OCI

```bash
helm upgrade --install n8n oci://8gears.container-registry.com/library/n8n --version 1.0.15 ...
```

#### Multiple Commands per Section

Some sections (e.g., kube-prometheus-stack) have multiple commands. Only update the `helm upgrade --install` command's `--version`, not `kubectl` commands or comments.

#### Missing Section

If a module has no section in `helm_install.md`, add one following the existing format:

```markdown
# <module_name>

\`\`\`bash
helm repo add <repo_name> <repo_url>
helm repo update

helm upgrade --install <release_name> <repo_name>/<chart_name> --create-namespace --version <version> -n <namespace> --values common.yaml --values configs-dev.yaml
\`\`\`
```

## Version Comparison Logic

```
Parse versions as semver (major.minor.patch[-prerelease]):
- If major changed → "Major" (breaking changes likely)
- If minor changed → "Minor" (new features, usually backwards-compatible)
- If patch changed → "Patch" (bug fixes)
- If identical → "Up to date"
- If pre-release suffix changed → "Pre-release"
- If unparseable → "Unknown" (flag for manual review)
```

## ArtifactHub API Reference

### Endpoint

```
GET https://artifacthub.io/api/v1/packages/helm/{owner}/{chart}
```

### Response Fields

```json
{
  "version": "10.5.4",           // Latest chart version
  "app_version": "11.5.0",      // Application version
  "deprecated": false,
  "repository": {
    "url": "https://grafana.github.io/helm-charts"
  },
  "links": [
    {"name": "changelog", "url": "..."}
  ]
}
```

### Rate Limiting

ArtifactHub has rate limits. When checking all modules:
- Add a small delay between requests (1-2 seconds)
- Cache responses within the same session
- If rate-limited (HTTP 429), wait and retry

### Release Notes URL Pattern

```
https://artifacthub.io/packages/helm/{owner}/{chart}/{version}
```
