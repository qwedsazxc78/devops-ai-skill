# Generate Architecture Diagrams

Generate visual architecture documentation.

## Pipeline Steps

### Step 1: Parse Repository Structure

- Discover all modules, overlays, ArgoCD apps
- Map dependencies

### Step 2: Architecture Diagrams

- Mermaid: module dependency graph
- Mermaid: ArgoCD application topology
- Mermaid: Kustomize overlay tree
- D2 or KubeDiagrams (if available)

### Step 3: Workflow Flowcharts

- CI/CD pipeline flow
- Deployment workflow
- Sync/reconciliation flow

### Step 4: Render and Output

- Save diagrams to docs/diagrams/
- Print paths and preview
