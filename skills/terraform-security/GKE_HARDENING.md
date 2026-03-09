# GKE Hardening Checklist

> **Note:** File paths and "Current State" values below are from a reference implementation. The terraform-security skill discovers actual file paths and values dynamically at runtime.

Security controls checklist for GKE clusters managed via Terraform. Reference against the cluster configuration file (discovered by the skill's Step 0a).

## Network Security

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Private nodes | `enable_private_nodes = true` | true | Critical | Nodes have no public IPs |
| Private endpoint | `enable_private_endpoint = false` | true (for prd) | High | Control plane is publicly accessible. Consider enabling for production. |
| Master authorized networks | Configured via `local.authorized_networks` | Configured | High | Verify CIDR ranges are minimal |
| Network policy | `network_policy = true` | true | High | Calico network policies enabled |
| VPC-native | Pod/service IP ranges configured | Configured | Critical | Using alias IP ranges |
| Disable default SNAT | `disable_default_snat = true` | true | Medium | Correct for shared VPC |
| DNS cache | `dns_cache = true` | true | Low | NodeLocal DNSCache enabled |

## Node Security

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Node image | `image_type = "COS_CONTAINERD"` | COS_CONTAINERD | Critical | All node pools use Container-Optimized OS |
| Auto-repair | `auto_repair = true` | true | High | All pools enabled |
| Auto-upgrade | `auto_upgrade = true` | true | High | All pools enabled |
| Remove default pool | `remove_default_node_pool = true` | true | Medium | Default pool removed |
| Service account | `create_service_account = false` | Create dedicated SA | High | Using compute default SA — should create a dedicated least-privilege SA |
| OAuth scopes | `logging.write`, `monitoring`, `cloud-platform`, `compute`, `devstorage.read_only` | Minimal scopes | Medium | Includes `cloud-platform` which is broad and overrides other scopes; consider removing it and relying on the specific scopes listed |
| Shielded nodes | Not configured | Enable | Medium | Add `enable_shielded_nodes = true` |
| Integrity monitoring | Not configured | Enable | Medium | Add to shielded instance config |

## Cluster Security

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Security posture | `VULNERABILITY_BASIC` | VULNERABILITY_ENTERPRISE for prd | Medium | Basic scanning enabled |
| Binary authorization | Not configured | Enable for prd | High | Consider enabling `enable_binary_authorization = true` |
| Pod Security Standards | Not configured | Enable | High | Add pod security policy/standards |
| Config connector | `config_connector = true` | true | Info | Enabled for GCP resource management |
| GKE Backup Agent | `gke_backup_agent_config = true` | true | Medium | Backup agent enabled |
| Cost allocation | `enable_cost_allocation = true` | true | Info | Cost tracking enabled |
| Workload identity | Configured in `3-gke-identity.tf` | Configured | Critical | Preferred over node SA |
| Release channel | Not specified | Use REGULAR | Medium | Pin to a release channel for automatic security patches |

## Maintenance

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Maintenance window | Mon-Thu 16:00-00:00 UTC | Configured | Info | Business hours maintenance |
| Maintenance exclusion | Not configured | Add for critical periods | Low | Consider holiday/launch exclusions |

## IAM & Access

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Compute default SA | Used as node SA | Create dedicated SA | High | Default SA has broad permissions |
| Workload identity SAs | 6 SAs configured | Review periodically | Medium | airflow, external-secrets, loki, tempo, litellm, langfuse |
| Cross-project roles | Extensively configured | Audit quarterly | High | airflow SA has roles in 10+ projects |
| IAM role scope | Various | Least privilege | Medium | Review `roles/storage.objectAdmin` vs more specific roles |

## Observability for Security

| Control | Current State | Recommended | Severity | Notes |
|---------|--------------|-------------|----------|-------|
| Audit logging | Default | Enable data access logs | Medium | GKE admin activity logged by default |
| Security Command Center | Unknown | Enable | Medium | GCP SCC for threat detection |
| kube-bench | Deployed (`module.kube-bench`) | Running | Info | CIS benchmark scanning in-cluster |

## Remediation Priority

### Immediate (Critical/High)

1. **Create dedicated node service account** — Replace compute default SA with a dedicated SA having minimal permissions
2. **Enable binary authorization** — Prevent deployment of unsigned container images in production
3. **Enable Pod Security Standards** — Enforce security contexts on pods
4. **Review private endpoint** — Consider enabling `enable_private_endpoint = true` for production environments
5. **Audit cross-project IAM** — airflow SA has extensive permissions across 10+ projects

### Short-Term (Medium)

6. Enable shielded nodes
7. Upgrade security posture to ENTERPRISE for production
8. Set release channel
9. Review OAuth scopes for node pools
10. Enable audit data access logging

### Long-Term (Low/Info)

11. Add maintenance exclusion windows
12. Implement node auto-provisioning constraints
13. Enable Confidential GKE Nodes for sensitive workloads
