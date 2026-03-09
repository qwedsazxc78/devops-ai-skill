# CI/CD Improvement Pipeline

Analyze and improve CI/CD pipeline configuration.

## Pipeline Steps

### Step 1: Analyze Current Pipeline

- Skill: `cicd-enhancer`
- Read CI/CD configuration files
- Identify missing stages
- Gap analysis against best practices

### Step 2: Generate Recommendations

- Skill: `cicd-enhancer`
- CI job YAML snippets for each missing stage
- Quality gate definitions
- Caching and optimization suggestions

### Step 3: Validate CI Changes

- Skill: `terraform-validate`
- YAML syntax check on generated snippets
- Verify job dependencies and stage ordering

### Step 4: Present Improvement Plan

- Phased rollout (immediate → short-term → long-term)
- Each phase with specific CI jobs to add

### Step 5: Offer Implementation

1. Generate updated CI configuration
2. Show diff of changes
3. Apply specific phase only
