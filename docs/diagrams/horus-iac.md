# Horus — IaC Architecture (Terraform + Helm + GKE)

Horus manages infrastructure as code: Terraform provisions GKE and cloud resources,
Helm releases land charts onto the cluster, and chart versions are discovered from
ArtifactHub.

```mermaid
flowchart LR
  subgraph code["IaC Repo"]
    tf["Terraform modules<br/>(*.tf)"]
    helm["Helm releases<br/>(values.yaml + versions)"]
    tf --> helm
  end

  subgraph disc["Version Discovery"]
    ah["ArtifactHub<br/>latest chart versions"]
  end

  subgraph gke["GKE Cluster"]
    infra["Cluster + Node Pools<br/>+ Networking"]
    rel["Helm Releases<br/>(workloads)"]
    infra --> rel
  end

  ah -.->|"*upgrade compares"| helm
  tf -->|"terraform apply"| infra
  helm -->|"helm upgrade"| rel

  %% Horus pipeline touchpoints
  hfull(["*full"]):::cmd -.->|fmt+tflint+tfsec| tf
  hupg(["*upgrade"]):::cmd -.->|3-file version bump| helm
  hsec(["*security"]):::cmd -.->|tfsec/checkov| tf
  hval(["*validate"]):::cmd -.->|terraform validate| tf

  classDef cmd fill:#0052CC,color:#fff,stroke:#0D6EFD;
```

**Pipeline touchpoints:** `*full` runs fmt+lint+security, `*upgrade` bumps Helm chart
versions (atomic 3-file update via ArtifactHub), `*security`/`*validate` gate the
Terraform. See [diagrams-guide.md](../diagrams-guide.md).
