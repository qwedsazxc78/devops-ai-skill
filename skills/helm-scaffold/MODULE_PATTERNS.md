# Module Patterns

Five documented patterns for Helm modules managed via Terraform, with reference implementations.

## Pattern 1: Simple

**Use when:** Chart needs minimal config, no env-specific values, no DR.
**Reference:** `modules/helm/keda/`

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "<REPO_URL>"
  chart            = "<CHART_NAME>"
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]
}
```

### variables.tf

```hcl
variable "name" {
  type    = string
  default = "<CHART_NAME>"
}

variable "namespace" {
  type    = string
  default = "<NAMESPACE>"
}

variable "install_version" {
  type    = string
  default = "<VERSION>"
}
```

### 3-gke-package.tf entry

```hcl
module "<CHART_NAME>" {
  name            = "<CHART_NAME>"
  source          = "./modules/helm/<CHART_NAME>"
  install_version = "<VERSION>"

  depends_on = [module.gke]
}
```

**Characteristics:**
- No `environment` or `dr` variables
- No values YAML files
- Only `set` blocks for config
- Simplest possible module

**Existing modules using this pattern:** keda, cert-manager, cert-exporter, external-secrets

---

## Pattern 2: Standard

**Use when:** Chart needs env-specific config and/or DR support.
**Reference:** `modules/helm/argocd/`

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "<REPO_URL>"
  chart            = "<CHART_NAME>"
  namespace        = var.namespace
  version          = var.install_version
  create_namespace = true

  values = concat(
    [
      file("${path.module}/common.yaml"),
      file("${path.module}/configs-${var.environment}.yaml")
    ],
    var.dr ? [file("${path.module}/configs-${var.environment}-dr.yaml")] : []
  )
}
```

### variables.tf

```hcl
variable "name" {
  type    = string
  default = "<CHART_NAME>"
}

variable "namespace" {
  type    = string
  default = "<NAMESPACE>"
}

variable "install_version" {
  type    = string
  default = "<VERSION>"
}

variable "environment" {
  type = string
}

variable "dr" {
  type = bool
}
```

### Required files

```
modules/helm/<chart-name>/
├── main.tf
├── variables.tf
├── common.yaml           # Shared values across all environments
├── configs-dev.yaml      # Dev-specific values
├── configs-stg.yaml      # Staging-specific values
├── configs-prd.yaml      # Production-specific values
├── configs-dev-dr.yaml   # Dev DR overrides (optional)
└── configs-prd-dr.yaml   # Prd DR overrides (optional)
```

### 3-gke-package.tf entry

```hcl
module "<CHART_NAME>" {
  name            = "<CHART_NAME>"
  source          = "./modules/helm/<CHART_NAME>"
  install_version = "<VERSION>"
  environment     = local.environment
  dr              = local.dr
  depends_on      = [module.gke]
}
```

**Characteristics:**
- Uses `concat()` for conditional DR values
- Environment and DR variables required
- Multiple YAML value files per environment
- Most common pattern

**Existing modules:** argocd, grafana, kube-prometheus-stack, thanos, airflow, uptime-kuma, metabase, qdrant, opentelemetry, langfuse

---

## Pattern 3: Workload Identity

**Use when:** Chart needs GCP workload identity with service account injection.
**Reference:** `modules/helm/loki/`

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "<REPO_URL>"
  chart            = "<CHART_NAME>"
  namespace        = var.namespace
  version          = var.install_version
  create_namespace = true

  values = compact([
    file("${path.module}/common.yaml"),
    file("${path.module}/configs-${var.environment}.yaml"),
    var.dr ? file("${path.module}/configs-${var.environment}-dr.yaml") : "",
    yamlencode({
      serviceAccount = {
        name = (var.dr == true) ? "sa-<CHART_NAME>-dr" : "sa-<CHART_NAME>"
        annotations = {
          "iam.gke.io/gcp-service-account" = "${(var.dr == true) ? "sa-<CHART_NAME>-dr" : "sa-<CHART_NAME>"}@${var.project_id}.iam.gserviceaccount.com"
        }
      }
    })
  ])

  timeout = 600
}
```

### variables.tf

```hcl
variable "name" {
  type    = string
  default = "<CHART_NAME>"
}

variable "namespace" {
  type    = string
  default = "<NAMESPACE>"
}

variable "install_version" {
  type    = string
  default = "<VERSION>"
}

variable "environment" {
  type = string
}

variable "dr" {
  type = bool
}

variable "project_id" {
  type = string
}
```

### 3-gke-package.tf entry

```hcl
module "<CHART_NAME>" {
  name            = "<CHART_NAME>"
  source          = "./modules/helm/<CHART_NAME>"
  install_version = "<VERSION>"
  namespace       = "<NAMESPACE>"
  environment     = local.environment
  project_id      = var.GCP_PROJECT
  dr              = local.dr

  depends_on = [
    module.gke,
    google_storage_bucket.<CHART_NAME>_storage,  # If using GCS
    module.<CHART_NAME>-workload-identity
  ]
}
```

### 3-gke-identity.tf additions

```hcl
# Add to local.workload_namespace list
# Add workload identity module (see helm-scaffold SKILL.md Step 6)
```

**Characteristics:**
- Uses `compact()` instead of `concat()` (filters empty strings)
- `yamlencode()` block for SA injection
- Requires `project_id` variable
- Depends on workload identity module
- Longer timeout (600s)

**Existing modules:** loki, tempo

---

## Pattern 4: OCI

**Use when:** Chart is hosted in an OCI registry (not standard Helm repo).
**Reference:** `modules/helm/litellm/`

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "oci://<REGISTRY_HOST>/<REGISTRY_PATH>"
  chart            = "<CHART_NAME>"
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  values = concat(
    [
      file("${path.module}/common.yaml"),
      file("${path.module}/configs-${var.environment}.yaml")
    ],
    var.dr ? [file("${path.module}/configs-${var.environment}-dr.yaml")] : []
  )
}
```

**Key difference:** `repository` uses `oci://` prefix. Some OCI charts put the full OCI URL in `chart` instead (no `repository` field):

```hcl
# thanos pattern — no repository, chart has full OCI URL (same as n8n)
resource "helm_release" "thanos" {
  name  = var.name
  chart = "oci://registry-1.docker.io/bitnamicharts/thanos"
  # No repository field
  ...
}
```

**Existing modules:** litellm (repository-based OCI), thanos (chart-based OCI), n8n (chart-based OCI, commented out)

---

## Pattern 5: Multi-Instance

**Use when:** Same chart deployed multiple times with different configurations.
**Reference:** `modules/helm/gitlab-runner/`

### main.tf

```hcl
resource "helm_release" "this" {
  name             = var.name
  repository       = "<REPO_URL>"
  chart            = "<CHART_NAME>"
  version          = var.install_version
  namespace        = var.namespace
  create_namespace = true

  values = concat(
    [
      file("${path.module}/${var.name}.yaml"),  # Instance-specific values
      file("${path.module}/configs-${var.environment}.yaml")
    ],
    var.dr ? [file("${path.module}/configs-${var.environment}-dr.yaml")] : []
  )

  set = [
    {
      name  = "runners.tags"
      value = var.tags
    }
  ]
}
```

### variables.tf

Includes instance-specific variables:

```hcl
variable "tags" {
  type    = string
  default = ""
}
```

### 3-gke-package.tf entries

```hcl
module "instance_1" {
  source          = "./modules/helm/<CHART_NAME>"
  name            = "instance-1-name"
  install_version = "<VERSION>"
  environment     = local.environment
  dr              = local.dr
  depends_on      = [module.gke]
}

module "instance_2" {
  source          = "./modules/helm/<CHART_NAME>"
  name            = "instance-2-name"
  install_version = "<VERSION>"  # Must match instance_1
  tags            = local.environment
  environment     = local.environment
  dr              = local.dr
  depends_on      = [module.gke]
}
```

### Required files

```
modules/helm/<chart-name>/
├── main.tf
├── variables.tf
├── <instance-1-name>.yaml     # Per-instance values (not common.yaml)
├── <instance-2-name>.yaml     # Per-instance values
├── configs-dev.yaml
├── configs-stg.yaml
└── configs-prd.yaml
```

**Characteristics:**
- Values file selected by `var.name` (instance-specific)
- Multiple module blocks in `3-gke-package.tf` with same source
- All instances must share the same chart version
- Additional instance-specific variables (like `tags`)

**Existing modules:** gitlab-runner (common-pool, common-pool-env)

---

## Pattern Selection Flowchart

```
Start
  ├─ OCI registry? ─────────────── Yes → Pattern 4: OCI
  ├─ Multiple instances? ────────── Yes → Pattern 5: Multi-Instance
  ├─ Needs GCP SA injection? ───── Yes → Pattern 3: Workload Identity
  ├─ Needs env-specific config? ── Yes → Pattern 2: Standard
  └─ Minimal config? ───────────── Yes → Pattern 1: Simple
```
