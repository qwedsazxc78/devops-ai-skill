# Naming Conventions

Reference naming patterns for Terraform + Helm codebases. Use these as the baseline for naming convention audits.

## File Naming

| Pattern | Convention | Examples |
|---------|-----------|----------|
| Provider config | `0-provider.tf` | Numeric prefix for ordering |
| Main/locals | `2-main.tf` | Contains locals and data sources |
| Primary resources | `3-gke.tf`, `3-gke-package.tf` | Numeric prefix + resource type |
| Identity resources | `3-gke-identity.tf` | Grouped by concern |
| Environment configs | `infra/{env}-app.json` | `dev-app.json`, `stg-app.json`, `prd-app.json` |
| DR configs | `infra/{env}-dr-app.json` | `dev-dr-app.json`, `prd-dr-app.json` |
| CI config | `app-ci.yml` | Root-level CI definition |
| Helm module dirs | `modules/helm/{chart-name}/` | Kebab-case matching chart name |
| Variable files | `variables.tf` or `variable.tf` | **Inconsistent** — see note below |
| Value files | `common.yaml`, `configs-{env}.yaml` | Per-environment Helm values |
| DR value files | `configs-{env}-dr.yaml` | DR-specific overrides |

### Variable File Inconsistency

Two modules use singular `variable.tf`:
- `modules/helm/grafana/variable.tf`
- `modules/helm/external-secrets/variable.tf`

All other modules use plural `variables.tf`. **Recommendation:** Standardize to `variables.tf` across all modules.

## Resource Naming

### Terraform Resource Names

| Resource Type | Pattern | Examples |
|---|---|---|
| Helm releases | `helm_release.<chart_name>` or `helm_release.this` | `helm_release.loki`, `helm_release.this` |
| GKE module | `module.gke` | Single instance |
| Helm modules | `module.<chart-name>` | `module.grafana`, `module.argocd` |
| Workload identity modules | `module.<name>-workload-identity` | `module.airflow-workload-identity` |
| Namespaces | `kubernetes_namespace.workload_identity` | Count-based |
| Storage buckets | `google_storage_bucket.<name>_storage` | `google_storage_bucket.loki_storage` |

### Helm Release Resource Name Inconsistency

Some modules use descriptive names, others use `this`:

| Pattern | Modules |
|---------|---------|
| `helm_release.this` | argocd, keda, argo-rollouts |
| `helm_release.<chart_name>` | loki, tempo, litellm, n8n, langfuse, gitlab_runner, external-secrets |

**Recommendation:** Standardize to `helm_release.this` for single-instance modules.

### Module Block Naming

| Pattern | Example | Notes |
|---------|---------|-------|
| Kebab-case matching chart | `module "argocd"` | Most common |
| Underscore (legacy typo) | `module "gitlb_runner"` | Note: missing 'a' in gitlab |
| Underscore variant | `module "gitlb_runner_env"` | Multi-instance suffix |

## Variable Naming

### Root Variables (`1-variables.tf` or similar)

| Pattern | Examples |
|---------|---------|
| SCREAMING_CASE for env vars | `WORKSPACE_ENV`, `GCP_PROJECT` |
| snake_case for others | `cluster_name` |

### Module Variables

| Variable | Convention | Notes |
|----------|-----------|-------|
| `name` | string, with default | Chart release name |
| `namespace` | string, with default | K8s namespace |
| `install_version` | string, with default | Chart version |
| `environment` | string, no default | Set by caller |
| `dr` | bool, no default | Set by caller |
| `project_id` | string, no default | Only for workload-identity modules |
| `tags` | string, optional | Only for gitlab-runner |

### Environment JSON Keys

All keys in `infra/*.json` use **snake_case**:

```
dr, environment, region, zones, regional,
vpc_host_project, vpc, vpc_subnet,
default_pool_name, default_pool_spot_type, ...
```

## Namespace Naming

| Pattern | Examples | Notes |
|---------|---------|-------|
| Match chart name | `argocd`, `keda`, `airflow` | Most common |
| Shared namespace | `monitoring` (grafana, kube-prometheus-stack, thanos, loki, tempo, opentelemetry) | Monitoring stack shares namespace |
| Custom namespace | `uptime` (uptime-kuma), `gitlab-runner` (gitlab-runner) | Some differ from chart name |

## Label Naming

From `3-gke.tf` node pool labels:

| Key | Pattern |
|-----|---------|
| Node pool identity | `spot-worker-pool`, `on-demand-worker-pool` |
| Boolean flags | `spot-worker-pool = true/false` |
| Special flags | `cud = true`, `airflow = true` |

## Audit Checklist

When auditing naming conventions, check:

- [ ] All new modules use `variables.tf` (plural)
- [ ] All new helm release resources use `helm_release.this`
- [ ] Module names in `3-gke-package.tf` use kebab-case
- [ ] Environment JSON files follow `{env}-app.json` pattern
- [ ] New variables use snake_case
- [ ] Root variables for environment injection use SCREAMING_CASE
- [ ] Workload identity modules follow `<name>-workload-identity` pattern
- [ ] Namespace names are documented in `local.workload_namespace` when using workload identity
