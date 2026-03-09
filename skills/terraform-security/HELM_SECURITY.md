# Helm Chart Security Patterns

> **Note:** The data below reflects a reference implementation. The terraform-security skill discovers actual configurations dynamically at runtime. Replace specific chart names, SA names, and IAM roles with your own when adapting.

Per-chart security configuration patterns for Helm modules deployed via Terraform.

## Workload Identity Configuration

Charts that require GCP workload identity:

| Chart | SA Name | SA Name (DR) | Namespace | IAM Roles |
|-------|---------|-------------|-----------|-----------|
| airflow | sa-airflow | sa-airflow-dr | airflow | monitoring.viewer, container.clusterViewer, container.viewer, pubsub.viewer, storage.objectAdmin, storage.bucketViewer, artifactregistry.writer + cross-project (12 projects: pubsub, bigquery, aiplatform, dataproc, storage, artifactregistry) |
| external-secrets | sa-external-secrets | sa-external-secrets-dr | external-secrets | secretmanager.secretAccessor, iam.serviceAccountTokenCreator, +cross-project |
| loki | sa-loki | sa-loki-dr | monitoring | storage.objectAdmin, storage.bucketViewer |
| tempo | sa-tempo | sa-tempo-dr | monitoring | storage.objectAdmin, storage.bucketViewer |
| litellm | sa-litellm | sa-litellm-dr | litellm | storage.objectViewer |
| langfuse | sa-langfuse | sa-langfuse-dr | langfuse | storage.objectAdmin, storage.bucketViewer |

### Workload Identity Namespaces

From `local.workload_namespace`:
```
airflow, mlflow, external-secrets, postgresql-ha, monitoring, litellm, langfuse
```

Note: `mlflow` and `postgresql-ha` are in the namespace list but their modules are not actively deployed. Consider cleanup.

## Per-Chart Security Assessment

### Monitoring Stack

#### grafana
- **RBAC:** Admin access controlled via OAuth (Google auth)
- **Secrets:** Google OAuth client secret managed via K8s secret `grafana-google-oauth`
- **RISK:** OAuth secret visible in `helm_install.md` — should be redacted
- **Network Policy:** Not configured — recommend enabling
- **Service Account:** Uses workload identity namespace (monitoring)

#### kube-prometheus-stack
- **RBAC:** ClusterRole for metrics collection (expected)
- **Secrets:** Thanos objstore secret created manually
- **Network Policy:** Not configured — monitoring namespace is shared
- **Service Account:** Uses workload identity namespace (monitoring)
- **Note:** Manages CRDs — must be upgraded carefully

#### thanos
- **RBAC:** Needs access to monitoring namespace
- **Secrets:** Objstore config contains GCS credentials
- **Network Policy:** Should restrict to monitoring namespace peers
- **OCI Registry:** Uses `registry-1.docker.io/bitnamicharts`

#### loki
- **RBAC:** ClusterRole for log collection
- **Workload Identity:** SA injected via `yamlencode` in main.tf
- **Storage:** GCS bucket for log storage
- **Secrets:** SA annotation handles auth
- **Timeout:** 600s for deployment

#### tempo
- **RBAC:** ClusterRole for trace collection
- **Workload Identity:** SA injected via `yamlencode` in main.tf
- **Storage:** GCS bucket for trace storage
- **Timeout:** 600s for deployment

#### opentelemetry
- **RBAC:** ClusterRole for telemetry collection
- **Network Policy:** Should restrict egress to monitoring backends only
- **No workload identity:** Uses in-cluster credentials

### CI/CD

#### argocd
- **RBAC:** ClusterAdmin-level for deployments (expected for GitOps)
- **Secrets:** Git repository credentials, SSO config
- **Network Policy:** Restrict to git repos + K8s API
- **Namespace:** Dedicated `argocd` namespace
- **RISK:** Broad cluster access — ensure RBAC projects are configured

#### argo-rollouts
- **RBAC:** Namespace-scoped CRD management
- **Low risk:** Only manages rollout CRDs
- **No env/dr config:** Stateless controller

#### gitlab-runner
- **RBAC:** Pod creation in runner namespace
- **Secrets:** Runner registration token (via variable `GITLB_RUNNER_TOKEN`)
- **RISK:** Runner pods can execute arbitrary CI jobs — ensure runner config limits
- **Multi-instance:** Two instances share the same module
- **Tags:** `common-pool` and `common-pool-env` have different tag configurations

### Platform Services

#### keda
- **RBAC:** ClusterRole for scaling CRDs
- **Low risk:** Autoscaler controller, no data access
- **CRDs:** `installCRDs = true`
- **Simple pattern:** No values files, minimal config

#### cert-manager
- **RBAC:** ClusterRole for certificate management
- **CRDs:** Manages cert CRDs
- **Network Policy:** Needs egress to ACME endpoints
- **Low risk:** Certificate lifecycle management

#### cert-exporter
- **RBAC:** Read-only access to cert resources
- **Depends on:** cert-manager
- **Low risk:** Monitoring/exporting only

#### external-secrets
- **RBAC:** ClusterRole for secret CRDs + secret creation
- **Workload Identity:** Accesses GCP Secret Manager
- **CRITICAL:** Has `secretmanager.secretAccessor` across 11+ projects
- **CRITICAL:** Has `iam.serviceAccountTokenCreator` — can impersonate other SAs
- **CRDs:** `installCRDs = true`
- **RISK:** Highest privilege workload — compromise means access to all secrets

#### kube-bench
- **RBAC:** Read-only cluster access for CIS scanning
- **Low risk:** Security scanning tool
- **Namespace:** Dedicated `kube-bench` namespace

### Applications

#### airflow
- **RBAC:** Namespace-scoped for workflow execution
- **Workload Identity:** Most permissive SA (10+ cross-project roles)
- **CRITICAL:** Has `storage.objectAdmin`, `artifactregistry.writer`, `dataproc.editor`, `aiplatform.user`, `bigquery.dataEditor` across 12 projects
- **Base roles:** monitoring.viewer, container.clusterViewer, container.viewer, pubsub.viewer, storage.objectAdmin, storage.bucketViewer, artifactregistry.writer
- **Depends on:** keda (for worker autoscaling), workload identity
- **Secrets:** Database credentials, Fernet key, webserver secret

#### uptime-kuma
- **RBAC:** Minimal — uptime monitoring
- **Low risk:** Read-only monitoring tool
- **Custom namespace:** `uptime`

#### metabase
- **RBAC:** Minimal — BI dashboard
- **Secrets:** Database connection strings
- **Risk:** May have access to sensitive data via queries

#### qdrant
- **RBAC:** Minimal — vector database
- **Secrets:** API keys for authentication
- **Network Policy:** Should restrict to application namespace clients

#### langfuse
- **RBAC:** Namespace-scoped
- **Workload Identity:** GCS access for storage
- **Secrets:** Database credentials, encryption keys

#### litellm
- **RBAC:** Namespace-scoped
- **Workload Identity:** Read-only GCS access
- **OCI Registry:** `oci://docker.litellm.ai/berriai`
- **Secrets:** LLM API keys (highly sensitive)
- **RISK:** Proxy to multiple LLM APIs — compromise exposes all API keys

## Security Priority Matrix

### Critical Risk
1. **external-secrets** — SA token creator + secret accessor across 12 projects (primary + 11 additional)
2. **airflow** — Broad cross-project IAM across 12 projects with admin-level storage/compute/AI roles
3. **litellm** — LLM API key aggregator

### High Risk
4. **argocd** — Cluster-admin GitOps controller
5. **gitlab-runner** — Arbitrary code execution in CI pods
6. **grafana** — OAuth secret in helm_install.md

### Medium Risk
7. **kube-prometheus-stack** — CRD management, cluster-wide metrics
8. **loki/tempo** — GCS storage access
9. **metabase** — Database query access

### Low Risk
10. All others — Minimal RBAC, namespace-scoped, limited data access
