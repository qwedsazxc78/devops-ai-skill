# gitops-template-ai-skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a standalone, buildable Kustomize + ArgoCD practice repository at `/Users/MH/Documents/git_awoo/infra-iac/gitops-template-ai-skill` for beginners to explore and validate with the Zeus agent.

**Architecture:** Standard GitOps layout — `base/` holds canonical K8s manifests, `overlays/{dev,stg,prd}` patch per-environment, `argocd/` holds ArgoCD Application CRDs. Uses `nginx:1.25` as a universal container image with no registry auth required.

**Tech Stack:** Kustomize, ArgoCD, Kubernetes YAML manifests, bash

**Spec:** `docs/superpowers/specs/2026-04-13-gitops-template-ai-skill-design.md`

---

### Task 1: Initialize Git Repo and Config Files

**Files:**
- Create: `/Users/MH/Documents/git_awoo/gitops-template-ai-skill/.yamllint.yml`
- Create: `/Users/MH/Documents/git_awoo/gitops-template-ai-skill/.yamlfmt`
- Create: `/Users/MH/Documents/git_awoo/gitops-template-ai-skill/.gitignore`

- [ ] **Step 1: Create directory and init git**

```bash
mkdir -p /Users/MH/Documents/git_awoo/gitops-template-ai-skill
cd /Users/MH/Documents/git_awoo/gitops-template-ai-skill
git init
```

- [ ] **Step 2: Create .gitignore**

```gitignore
# OS
.DS_Store

# IDE
.idea/
.vscode/

# Kustomize build output
output/
```

- [ ] **Step 3: Create .yamllint.yml**

```yaml
---
extends: default

rules:
  line-length: disable
  indentation:
    spaces: 2
    indent-sequences: true
  document-start: disable
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no', 'on', 'off']
  key-duplicates: disable

ignore: |
  .git/
```

- [ ] **Step 4: Create .yamlfmt**

```yaml
formatter:
  indent: 2
  include_document_start: true
  retain_line_breaks: true

exclude:
  - .git/
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore .yamllint.yml .yamlfmt
git commit -m "chore: 初始化 gitops-template-ai-skill 專案"
```

---

### Task 2: Create Base Manifests

**Files:**
- Create: `base/kustomization.yaml`
- Create: `base/app.deployment.yaml`
- Create: `base/app.service.yaml`
- Create: `base/app.ingress.yaml`
- Create: `base/app.hpa.yaml`
- Create: `base/app.pdb.yaml`

- [ ] **Step 1: Create base/kustomization.yaml**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gitops-template-ai-skill
resources:
  - app.hpa.yaml
  - app.service.yaml
  - app.ingress.yaml
  - app.deployment.yaml
```

Note: `app.pdb.yaml` is intentionally NOT listed in kustomization.yaml resources — matching the reference project pattern where PDB exists as a file but is not included in the base kustomization.

- [ ] **Step 2: Create base/app.deployment.yaml**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  labels:
    app: gitops-template-ai-skill
spec:
  revisionHistoryLimit: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 2
  selector:
    matchLabels:
      app: gitops-template-ai-skill
  template:
    metadata:
      labels:
        app: gitops-template-ai-skill
    spec:
      automountServiceAccountToken: false
      containers:
        - image: nginx:1.25
          name: gitops-template-ai-skill
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: gitops-template-ai-skill
            - secretRef:
                name: gitops-template-ai-skill-secrets
          ports:
            - containerPort: 80
              name: http
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 3
            periodSeconds: 10
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 3
            periodSeconds: 10
            timeoutSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 30"]
      terminationGracePeriodSeconds: 30
```

- [ ] **Step 3: Create base/app.service.yaml**

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  labels:
    app: gitops-template-ai-skill
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      protocol: TCP
      targetPort: http
  selector:
    app: gitops-template-ai-skill
```

- [ ] **Step 4: Create base/app.ingress.yaml**

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: base-gitops-template.example.com
      http:
        paths:
          - backend:
              service:
                name: gitops-template-ai-skill
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
```

- [ ] **Step 5: Create base/app.hpa.yaml**

```yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gitops-template-ai-skill
  minReplicas: 1
  maxReplicas: 1
  metrics:
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 75
```

- [ ] **Step 6: Create base/app.pdb.yaml**

```yaml
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: gitops-template-ai-skill
```

- [ ] **Step 7: Commit**

```bash
git add base/
git commit -m "feat(base): 新增基礎 Kubernetes manifests"
```

---

### Task 3: Create Dev Overlay

**Files:**
- Create: `overlays/dev/kustomization.yaml`
- Create: `overlays/dev/app.deployment.yaml`
- Create: `overlays/dev/app.ingress.yaml`
- Create: `overlays/dev/env/app.env`
- Create: `overlays/dev/env/secrets.env`

- [ ] **Step 1: Create overlays/dev/kustomization.yaml**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gitops-template-ai-skill
resources:
  - ../../base

patches:
  - path: app.ingress.yaml
  - path: app.deployment.yaml

configMapGenerator:
  - envs:
      - ./env/app.env
    name: gitops-template-ai-skill
secretGenerator:
  - envs:
      - ./env/secrets.env
    name: gitops-template-ai-skill-secrets

images:
  - name: nginx
    newTag: latest
```

- [ ] **Step 2: Create overlays/dev/app.deployment.yaml**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  labels:
    app: gitops-template-ai-skill
spec:
  selector:
    matchLabels:
      app: gitops-template-ai-skill
  template:
    metadata:
      labels:
        app: gitops-template-ai-skill
    spec:
      containers:
        - image: nginx:1.25
          name: gitops-template-ai-skill
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: gitops-template-ai-skill
            - secretRef:
                name: gitops-template-ai-skill-secrets
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 30"]
      terminationGracePeriodSeconds: 30
```

- [ ] **Step 3: Create overlays/dev/app.ingress.yaml**

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: dev-gitops-template.example.com
      http:
        paths:
          - backend:
              service:
                name: gitops-template-ai-skill
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
```

- [ ] **Step 4: Create overlays/dev/env/app.env**

```env
ENVIRONMENT=dev
APP_NAME=gitops-template-ai-skill
APP_PORT=80
LOG_LEVEL=debug
```

- [ ] **Step 5: Create overlays/dev/env/secrets.env**

```env
API_KEY=CHANGE_ME
DB_PASSWORD=CHANGE_ME
```

- [ ] **Step 6: Validate dev overlay builds**

```bash
cd /Users/MH/Documents/git_awoo/gitops-template-ai-skill
kustomize build overlays/dev
```

Expected: YAML output with merged manifests, no errors.

- [ ] **Step 7: Commit**

```bash
git add overlays/dev/
git commit -m "feat(overlay): 新增 dev 環境 overlay"
```

---

### Task 4: Create Stg Overlay

**Files:**
- Create: `overlays/stg/kustomization.yaml`
- Create: `overlays/stg/app.deployment.yaml`
- Create: `overlays/stg/app.ingress.yaml`
- Create: `overlays/stg/env/app.env`
- Create: `overlays/stg/env/secrets.env`

- [ ] **Step 1: Create overlays/stg/kustomization.yaml**

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gitops-template-ai-skill
resources:
  - ../../base

patches:
  - path: app.ingress.yaml
  - path: app.deployment.yaml

configMapGenerator:
  - envs:
      - ./env/app.env
    name: gitops-template-ai-skill
secretGenerator:
  - envs:
      - ./env/secrets.env
    name: gitops-template-ai-skill-secrets

images:
  - name: nginx
    newTag: stable
```

- [ ] **Step 2: Create overlays/stg/app.deployment.yaml**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  labels:
    app: gitops-template-ai-skill
spec:
  selector:
    matchLabels:
      app: gitops-template-ai-skill
  template:
    metadata:
      labels:
        app: gitops-template-ai-skill
    spec:
      containers:
        - image: nginx:1.25
          name: gitops-template-ai-skill
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: gitops-template-ai-skill
            - secretRef:
                name: gitops-template-ai-skill-secrets
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 400m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 30"]
      terminationGracePeriodSeconds: 30
```

- [ ] **Step 3: Create overlays/stg/app.ingress.yaml**

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: stg-gitops-template.example.com
      http:
        paths:
          - backend:
              service:
                name: gitops-template-ai-skill
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
```

- [ ] **Step 4: Create overlays/stg/env/app.env**

```env
ENVIRONMENT=stg
APP_NAME=gitops-template-ai-skill
APP_PORT=80
LOG_LEVEL=info
```

- [ ] **Step 5: Create overlays/stg/env/secrets.env**

```env
API_KEY=CHANGE_ME
DB_PASSWORD=CHANGE_ME
```

- [ ] **Step 6: Validate stg overlay builds**

```bash
kustomize build overlays/stg
```

Expected: YAML output with merged manifests, no errors.

- [ ] **Step 7: Commit**

```bash
git add overlays/stg/
git commit -m "feat(overlay): 新增 stg 環境 overlay"
```

---

### Task 5: Create Prd Overlay

**Files:**
- Create: `overlays/prd/kustomization.yaml`
- Create: `overlays/prd/app.deployment.yaml`
- Create: `overlays/prd/app.hpa.yaml`
- Create: `overlays/prd/app.ingress.yaml`
- Create: `overlays/prd/env/app.env`
- Create: `overlays/prd/env/secrets.env`

- [ ] **Step 1: Create overlays/prd/kustomization.yaml**

Note: prd has an extra patch for `app.hpa.yaml` compared to dev/stg.

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: gitops-template-ai-skill
resources:
  - ../../base

patches:
  - path: app.ingress.yaml
  - path: app.deployment.yaml
  - path: app.hpa.yaml

configMapGenerator:
  - envs:
      - ./env/app.env
    name: gitops-template-ai-skill
secretGenerator:
  - envs:
      - ./env/secrets.env
    name: gitops-template-ai-skill-secrets

images:
  - name: nginx
    newTag: v1.0.0
```

- [ ] **Step 2: Create overlays/prd/app.deployment.yaml**

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  labels:
    app: gitops-template-ai-skill
spec:
  selector:
    matchLabels:
      app: gitops-template-ai-skill
  template:
    metadata:
      labels:
        app: gitops-template-ai-skill
    spec:
      containers:
        - image: nginx:1.25
          name: gitops-template-ai-skill
          envFrom:
            - configMapRef:
                name: gitops-template-ai-skill
            - secretRef:
                name: gitops-template-ai-skill-secrets
          resources:
            requests:
              cpu: 250m
              memory: 512Mi
            limits:
              cpu: 500m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 10
            periodSeconds: 30
            timeoutSeconds: 10
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 30"]
      terminationGracePeriodSeconds: 30
```

- [ ] **Step 3: Create overlays/prd/app.hpa.yaml**

```yaml
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: gitops-template-ai-skill
  minReplicas: 2
  maxReplicas: 3
  metrics:
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 75
```

- [ ] **Step 4: Create overlays/prd/app.ingress.yaml**

```yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitops-template-ai-skill
  namespace: gitops-template-ai-skill
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
    - host: prd-gitops-template.example.com
      http:
        paths:
          - backend:
              service:
                name: gitops-template-ai-skill
                port:
                  number: 80
            path: /
            pathType: ImplementationSpecific
```

- [ ] **Step 5: Create overlays/prd/env/app.env**

```env
ENVIRONMENT=prd
APP_NAME=gitops-template-ai-skill
APP_PORT=80
LOG_LEVEL=warning
```

- [ ] **Step 6: Create overlays/prd/env/secrets.env**

```env
API_KEY=CHANGE_ME
DB_PASSWORD=CHANGE_ME
```

- [ ] **Step 7: Validate prd overlay builds**

```bash
kustomize build overlays/prd
```

Expected: YAML output with merged manifests, no errors.

- [ ] **Step 8: Commit**

```bash
git add overlays/prd/
git commit -m "feat(overlay): 新增 prd 環境 overlay"
```

---

### Task 6: Create ArgoCD Application Manifests

**Files:**
- Create: `argocd/dev.yaml`
- Create: `argocd/stg.yaml`
- Create: `argocd/prd.yaml`

- [ ] **Step 1: Create argocd/dev.yaml**

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-gitops-template-ai-skill
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-template-ai-skill.git
    targetRevision: HEAD
    path: overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-template-ai-skill
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - PruneLast=true
      - CreateNamespace=true
```

- [ ] **Step 2: Create argocd/stg.yaml**

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: stg-gitops-template-ai-skill
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-template-ai-skill.git
    targetRevision: HEAD
    path: overlays/stg
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-template-ai-skill
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - PruneLast=true
      - CreateNamespace=true
```

- [ ] **Step 3: Create argocd/prd.yaml**

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prd-gitops-template-ai-skill
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-template-ai-skill.git
    targetRevision: HEAD
    path: overlays/prd
  destination:
    server: https://kubernetes.default.svc
    namespace: gitops-template-ai-skill
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - PruneLast=true
      - CreateNamespace=true
```

- [ ] **Step 4: Commit**

```bash
git add argocd/
git commit -m "feat(argocd): 新增 ArgoCD Application manifests (dev/stg/prd)"
```

---

### Task 7: Create Validation Script and README

**Files:**
- Create: `scripts/validate.sh`
- Create: `README.md`

- [ ] **Step 1: Create scripts/validate.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ENVS=("dev" "stg" "prd")
PASS=0
FAIL=0

for env in "${ENVS[@]}"; do
  echo "=== Validating overlays/${env} ==="
  if kustomize build "overlays/${env}" > /dev/null 2>&1; then
    echo "PASS: overlays/${env}"
    ((PASS++))
  else
    echo "FAIL: overlays/${env}"
    kustomize build "overlays/${env}"
    ((FAIL++))
  fi
  echo ""
done

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "${FAIL}" -eq 0 ] || exit 1
```

Make executable: `chmod +x scripts/validate.sh`

- [ ] **Step 2: Run validation**

```bash
cd /Users/MH/Documents/git_awoo/gitops-template-ai-skill
bash scripts/validate.sh
```

Expected: All 3 environments pass.

- [ ] **Step 3: Create README.md**

Bilingual README (繁體中文 primary, English section). Content covers:
1. What this repo is
2. Directory structure explanation
3. How to validate locally
4. How to use with Zeus agent

See full README content in implementation — too long to inline in the plan, but must include the 4 sections above.

- [ ] **Step 4: Commit**

```bash
git add scripts/ README.md
git commit -m "docs: 新增 README 與驗證腳本"
```

---

### Task 8: Final Validation

- [ ] **Step 1: Verify all files exist**

```bash
cd /Users/MH/Documents/git_awoo/gitops-template-ai-skill
find . -type f -not -path './.git/*' | sort
```

Expected: 27 files matching the spec file structure.

- [ ] **Step 2: Run kustomize build on all overlays**

```bash
kustomize build overlays/dev > /dev/null && echo "dev: OK"
kustomize build overlays/stg > /dev/null && echo "stg: OK"
kustomize build overlays/prd > /dev/null && echo "prd: OK"
```

Expected: All 3 print OK.

- [ ] **Step 3: Verify no company-specific values leaked**

```bash
grep -r "awoo" . --include="*.yaml" --include="*.yml" --include="*.env" || echo "No awoo references found"
grep -r "llmo" . --include="*.yaml" --include="*.yml" --include="*.env" || echo "No llmo references found"
grep -r "35\.\(194\|229\)" . --include="*.yaml" || echo "No real IPs found"
```

Expected: All three print "No ... found".

- [ ] **Step 4: Verify git log**

```bash
git log --oneline
```

Expected: 6 commits (init, base, dev, stg, prd, argocd, docs).
