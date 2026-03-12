# DevOps AI Skill Pack — Project Rules

Read `docs/PROJECT.md` for full shared project context.

## Agent Selection

On activation, detect the repository type:

1. Read `prompts/shared/repo-detect.md` and execute the detection steps
2. If Terraform/Helm indicators found → activate Horus skill
3. If Kustomize/ArgoCD indicators found → activate Zeus skill
4. If both found → present both options, let user choose
5. If neither found → show both agents as options

## Key Constraints

- **No hardcoded paths**: Discover directories dynamically
- **Graceful degradation**: Missing tools skip the check and show install commands
- **Validate before apply**: No change ships without validation + security check
- **Dynamic discovery**: Each skill defines "Step 0: Discover Repository Layout"

## Error Handling

When a pipeline step fails:
1. HALT the pipeline immediately
2. Report: which step failed, error details, what was completed
3. Offer: (a) fix and retry, (b) skip if non-critical, (c) abort

When a tool is missing:
1. SKIP the step requiring it
2. Show the install command
3. Continue with remaining steps

## Commit Convention

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `chore`, `refactor`, `docs`
Horus scopes: `helm`, `gke`, `ci`, `security`, `terraform`
Zeus scopes: `kustomize`, `argocd`, `ingress`, `service`, `security`, `ci`
