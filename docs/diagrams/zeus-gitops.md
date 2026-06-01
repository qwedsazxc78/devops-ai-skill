# Zeus — GitOps Architecture (Kustomize + ArgoCD)

Zeus operates a GitOps repo where Kustomize renders per-environment manifests and
ArgoCD continuously syncs them to GKE. The ingress layer is split into a **controller
plane** (`common.traefik/`) and a **data plane** (`common.service/`).

```mermaid
flowchart LR
  subgraph repo["Git Repo (source of truth)"]
    base["common.service/base/<br/>kustomization.yaml"]
    ov["overlays/{dev,stg,prd}/"]
    traefik["common.traefik/<br/>(controller, --enable-helm)"]
    base --> ov
  end

  subgraph argo["ArgoCD"]
    app["Application<br/>(per env)"]
    sync["auto-sync + prune"]
    app --> sync
  end

  subgraph gke["GKE Cluster"]
    ctrl["Traefik / ingress-nginx<br/>controller"]
    svc["Service Pods<br/>+ Ingresses/HTTPRoutes"]
    ctrl --> svc
  end

  ov -->|"kustomize build"| app
  traefik -->|"kustomize build"| app
  sync --> ctrl
  sync --> svc

  %% Zeus pipeline touchpoints
  zfull(["*full / *review"]):::cmd -.->|validate + lint| ov
  zscaf(["*scaffold"]):::cmd -.->|new service| base
  zinst(["*install-traefik"]):::cmd -.->|controller edits| traefik

  classDef cmd fill:#0052CC,color:#fff,stroke:#0D6EFD;
```

**Pipeline touchpoints:** `*full`/`*review` validate overlays, `*scaffold` adds a new
service to `base/`, `*install-traefik` edits the controller plane. See
[diagrams-guide.md](../diagrams-guide.md).
