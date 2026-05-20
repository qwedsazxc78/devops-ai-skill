# CI/CD Improvement Pipeline

Analyze and improve CI/CD pipeline configuration.

## Pipeline Steps

### Step 1: Analyze Current Pipeline

- Read `skills/cicd-enhancer/GUIDE.md` and follow its step-by-step instructions
- Read CI/CD configuration files
- Identify missing stages
- Gap analysis against best practices

### Step 2: Generate Recommendations

- Read `skills/cicd-enhancer/GUIDE.md` and follow its step-by-step instructions
- CI job YAML snippets for each missing stage
- Quality gate definitions
- Caching and optimization suggestions

### Step 3: Validate CI Changes

- Read `skills/terraform-validate/GUIDE.md` and follow its step-by-step instructions
- YAML syntax check on generated snippets
- Verify job dependencies and stage ordering

### Step 4: Present Improvement Plan

- Phased rollout (immediate → short-term → long-term)
- Each phase with specific CI jobs to add

### Step 5: Offer Implementation

1. Generate updated CI configuration
2. Show diff of changes
3. Apply specific phase only
