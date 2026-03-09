# Pipeline Patterns

Ready-to-use GitLab CI job YAML snippets for Terraform + Helm pipelines.

## Recommended Pipeline Stages

The root `.gitlab-ci.yml` defines stages: `[validate, test, pr_agent, build, deploy, cleanup]`. To add new stages, update the root file:

```yaml
# Root .gitlab-ci.yml stages (add 'cost' and 'verify')
stages:
  - validate    # Format + lint + validate (parallel)
  - test        # Existing (SAST, secret detection)
  - pr_agent    # Existing (PR review bot)
  - build       # Terraform plan
  - cost        # NEW: Cost estimation
  - deploy      # Terraform apply
  - verify      # NEW: Post-deploy health check
  - cleanup     # Existing: terraform destroy
```

## Job Snippets

### 1. Format Check

The `.terraform:fmt` hidden job already exists in `ci/terraform-gitlab-ci.yml`. The simplest approach is to invoke it:

```yaml
# Option A: Use existing template (recommended — one line)
app-fmt:
  extends: .terraform:fmt
  needs: []
```

If you need more control (e.g., MR-only, specific rules):

```yaml
# Option B: Custom format check job
app-fmt-check:
  stage: validate
  script:
    - cd ${TF_ROOT}
    - gitlab-terraform fmt
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH =~ /^(dev|stg|prd|dev-dr|prd-dr)$/
  allow_failure: false
```

**Note:** Uses the pipeline's existing GitLab Terraform image (includes `gitlab-terraform` wrapper), not a separate `hashicorp/terraform` image.

### 2. TFLint

```yaml
app-lint:
  stage: validate
  image:
    name: ghcr.io/terraform-linters/tflint:latest
    entrypoint: [""]
  before_script:
    - tflint --init
  script:
    - cd ${TF_ROOT}
    - tflint --recursive --config ${CI_PROJECT_DIR}/.tflint.hcl
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH =~ /^(dev|stg|prd|dev-dr|prd-dr)$/
  allow_failure: true  # Start as warning, promote to blocking later
```

### 3. Security Scan (tfsec/trivy)

```yaml
app-security-scan:
  stage: validate
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy config ${TF_ROOT}
      --severity HIGH,CRITICAL
      --exit-code 1
      --format table
  artifacts:
    paths:
      - ${TF_ROOT}/trivy-report.json
    when: always
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH =~ /^(dev|stg|prd|dev-dr|prd-dr)$/
  allow_failure: false  # Block on HIGH/CRITICAL
```

### 4. SAST-IaC (GitLab Native)

SAST-IaC is **already active** at the root `.gitlab-ci.yml` level via:
```yaml
include:
  - template: Security/SAST-IaC.gitlab-ci.yml
```

To customize, add exclusions in the application pipeline:

```yaml
sast-iac:
  variables:
    SAST_IaC_EXCLUDED_PATHS: "modules/helm/*/configs-*.yaml"
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

### 5. Cost Estimation (Infracost)

```yaml
app-cost-estimate:
  stage: cost
  image:
    name: infracost/infracost:ci-latest
    entrypoint: [""]
  before_script:
    - export CLEAN_BRANCH=$(echo "${GCP_PROJECT_PREFIX}-${CI_COMMIT_BRANCH}" | sed 's/-dr//')
    - export TF_VAR_GCP_PROJECT=${CLEAN_BRANCH}
  script:
    - cd ${TF_ROOT}
    - infracost breakdown
      --path .
      --format table
      --show-skipped
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  allow_failure: true  # Informational only
```

### 6. Drift Detection (Scheduled)

```yaml
app-drift-detect:
  stage: build
  script:
    - cd ${TF_ROOT}
    - gitlab-terraform init
    - set -o pipefail
    - gitlab-terraform plan -detailed-exitcode -var="WORKSPACE_ENV=${DRIFT_ENV}" 2>&1 | tee plan-output.txt; PLAN_EXIT=${PIPESTATUS[0]}
    - |
      if [ $PLAN_EXIT -eq 2 ]; then
        echo "DRIFT DETECTED in ${DRIFT_ENV}"
        # Send notification (Slack/email webhook)
      fi
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
  parallel:
    matrix:
      - DRIFT_ENV: [dev, stg, prd]
```

### 7. Post-Deploy Verification

```yaml
app-verify:
  stage: verify
  image: google/cloud-sdk:slim
  script:
    - export CLEAN_BRANCH=$(echo "${GCP_PROJECT_PREFIX}-${CI_COMMIT_BRANCH}" | sed 's/-dr//')
    - gcloud container clusters get-credentials "${CLUSTER_NAME}-${CI_COMMIT_BRANCH}" --region $(gcloud config get-value compute/region) --project ${CLEAN_BRANCH}
    - kubectl get nodes -o wide
    - kubectl get pods --all-namespaces | grep -v Running | grep -v Completed || true
    - echo "Cluster health check complete"
  rules:
    - if: $CI_COMMIT_BRANCH =~ /^(dev|stg|prd)$/
  when: on_success
  allow_failure: true
```

## Caching Configuration

**Existing:** `ci/terraform-gitlab-ci.yml` already configures `.terraform/` caching with key `${TF_ROOT}`.

**Additional caching** to consider adding:

```yaml
# Provider plugin cache (speeds up init across branches)
variables:
  TF_PLUGIN_CACHE_DIR: ${CI_PROJECT_DIR}/.terraform.d/plugin-cache

# Add to app-ci.yml or extend the shared template
.terraform_plugin_cache:
  cache:
    - key: terraform-plugins
      paths:
        - .terraform.d/plugin-cache/
      policy: pull-push
```

## MR-Triggered Pipeline Pattern

For merge request pipelines (plan + review without deploy):

```yaml
# Run plan on MR, show in MR widget
app-mr-plan:
  extends: .terraform:build
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  artifacts:
    reports:
      terraform: ${TF_ROOT}/plan.json
```

## Complete Updated `app-ci.yml`

This is the recommended updated application pipeline. The root `.gitlab-ci.yml` already includes SAST-IaC, so it is NOT duplicated here.

```yaml
include:
  - 'ci/terraform-gitlab-ci.yml'
  # SAST-IaC is already included at root .gitlab-ci.yml level — do not duplicate

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/application      # Adjust to your Terraform root
  TF_VAR_GITLAB_ACCESS_TOKEN: ${GITLAB_ACCESS_TOKEN}
  TF_VAR_PROJECT_ID: "${CI_PROJECT_ID}"        # Your GitLab project ID
  TF_VAR_WORKSPACE_ENV: ${CI_COMMIT_BRANCH}
  TF_VAR_GCP_PROJECT: ${YOUR_GCP_PROJECT_PREFIX}-${CI_COMMIT_BRANCH}
  TF_VAR_RUNNER_TOKEN: ${RUNNER_TOKEN}         # Your runner registration token
  TF_STATE_NAME: ${YOUR_GCP_PROJECT_PREFIX}-${CI_COMMIT_BRANCH}

before_script:
  - export CLEAN_BRANCH=$(echo "${GCP_PROJECT_PREFIX}-${CI_COMMIT_BRANCH}" | sed 's/-dr//')
  - export TF_VAR_GCP_PROJECT=${CLEAN_BRANCH}
  - echo $TF_VAR_GCP_PROJECT
  - echo $TF_VAR_WORKSPACE_ENV

# === VALIDATE STAGE (parallel) ===
app-validate:
  extends: .terraform:validate
  needs: []

app-fmt:
  extends: .terraform:fmt
  needs: []

app-lint:
  stage: validate
  image:
    name: ghcr.io/terraform-linters/tflint:latest
    entrypoint: [""]
  before_script:
    - tflint --init
  script:
    - cd ${TF_ROOT}
    - tflint --recursive --config ${CI_PROJECT_DIR}/.tflint.hcl
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH =~ /^(dev|stg|prd|dev-dr|prd-dr)$/
  allow_failure: true

# === BUILD STAGE ===
app-build:
  extends: .terraform:build

# === DEPLOY STAGE ===
app-deploy-dev:
  extends: .terraform:deploy
  dependencies:
    - app-build
  environment:
    name: $TF_STATE_NAME
  only:
    refs:
      - dev
      - dev-dr

app-deploy-stg:
  extends: .terraform:deploy
  dependencies:
    - app-build
  environment:
    name: $TF_STATE_NAME
  only:
    refs:
      - stg

app-deploy-prd:
  extends: .terraform:deploy
  dependencies:
    - app-build
  environment:
    name: $TF_STATE_NAME
  only:
    refs:
      - prd
      - prd-dr
  when: manual

app-cleanup:
  extends: .terraform:destroy
  dependencies:
    - app-build
  environment:
    name: $TF_STATE_NAME
```
