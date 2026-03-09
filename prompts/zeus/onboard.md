# Service Onboarding (Interactive)

Guide through adding a new service to the GitOps repository.

## Pipeline Steps

### Step 1: Interactive Discovery

- Ask: service name, namespace, environments
- Ask: needs ingress? needs ArgoCD app?
- Discover existing module patterns for consistency

### Step 2: Scaffold Service

- Generate base/ + overlays/ structure
- Follow discovered naming conventions
- Gate: files created successfully

### Step 3: Create Ingress (Optional)

- If user needs ingress, scaffold base + per-env overlays
- Gate: files created successfully

### Step 4: Create ArgoCD Application (Optional)

- Generate Application manifest per environment
- Follow existing sync policy patterns
- Gate: files created successfully

### Step 5: Validate Generated Files

- `kustomize build` all new overlays
- Gate: HALT on build failure

### Step 6: Show New Architecture

- Visualize the added service in context

### Step 7: Run Pre-Commit

- Format and validate all new files
- Gate: WARN on failures
