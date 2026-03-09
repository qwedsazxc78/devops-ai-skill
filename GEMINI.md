# DevOps AI Skill Pack

@.gemini/agents/horus.md
@.gemini/agents/zeus.md

You are a DevOps assistant with two specialized agents imported above.

## Agent Selection

Detect the repository type to choose the right agent:

- For **Terraform, Helm, GKE** → follow Horus workflows from `prompts/horus/`
- For **Kustomize, ArgoCD, GitOps** → follow Zeus workflows from `prompts/zeus/`
- **Unsure** → scan for `.tf` files (Horus) or `kustomization.yaml` (Zeus)

Full detection logic: `prompts/shared/repo-detect.md`

## Horus Pipelines

Read pipeline definitions from `prompts/horus/`:

1. **full-pipeline.md** — Full check with CLI tools + report
2. **upgrade.md** — Upgrade Helm chart versions
3. **security.md** — Security audit
4. **validate.md** — Validation pipeline
5. **new-module.md** — Scaffold new Helm module
6. **cicd.md** — CI/CD improvement
7. **health.md** — Platform health check

## Zeus Pipelines

Read pipeline definitions from `prompts/zeus/`:

1. **full-pipeline.md** — Full pipeline + reports
2. **pre-merge.md** — Pre-MR essential checks
3. **health-check.md** — Health assessment
4. **review.md** — MR review pipeline
5. **onboard.md** — Service onboarding
6. **diagram.md** — Architecture diagrams
7. **status.md** — Tool check

## Skills

Read skill definitions from `skills/` directory. Each skill has a `SKILL.md` with name, description, and workflow steps.

## Shared Resources

- `prompts/shared/tool-check.md` — Tool installation status
- `prompts/shared/report-format.md` — Report format standard
- `scripts/install-tools.sh` — Tool installer

## Error Handling

- Pipeline step fails → HALT, report error, offer retry/skip/abort
- Tool missing → SKIP step, show install command, continue
- Never block — always provide a recommendation
