# CLAUDE.md

Read `docs/PROJECT.md` first — it contains all shared project context.

## Claude Code Specifics

- Agent definitions: `.claude/agents/horus.md` and `.claude/agents/zeus.md`
- Skills directory: `skills/` (each skill has `SKILL.md` with YAML frontmatter)
- Plugin config: `.claude-plugin/plugin.json`

## Agent Activation

On session start:
1. Read `docs/PROJECT.md` for project context
2. Run `prompts/shared/repo-detect.md` to detect repository type
3. Activate the appropriate agent from `.claude/agents/`

## Horus Commands

| Command | Pipeline |
|---------|----------|
| *full | `prompts/horus/full-pipeline.md` |
| *upgrade | `prompts/horus/upgrade.md` |
| *security | `prompts/horus/security.md` |
| *validate | `prompts/horus/validate.md` |
| *scaffold | `prompts/horus/scaffold.md` |
| *cicd | `prompts/horus/cicd.md` |
| *health | `prompts/horus/health.md` |

## Zeus Commands

| Command | Pipeline |
|---------|----------|
| *full | `prompts/zeus/full-pipeline.md` |
| *pre-merge | `prompts/zeus/pre-merge.md` |
| *health | `prompts/zeus/health.md` |
| *review | `prompts/zeus/review.md` |
| *scaffold | `prompts/zeus/scaffold.md` |
| *diagram | `prompts/zeus/diagram.md` |
| *status | `prompts/zeus/status.md` |
| *gateway-migrate | `prompts/zeus/gateway-migrate.md` |
| *nginx-to-traefik | `prompts/zeus/nginx-to-traefik.md` |
| *nginx-to-gateway | `prompts/zeus/nginx-to-gateway.md` |
| *ingress-to-gateway | `prompts/zeus/ingress-to-gateway.md` |
| *ingress-migration-advisor | `prompts/zeus/ingress-migration-advisor.md` |
| *install-traefik | `prompts/zeus/install-traefik.md` |
| *decommission-nginx | `prompts/zeus/decommission-nginx.md` |
| *retire-nginx | `prompts/zeus/retire-nginx.md` |
| *migration-quickstart | `prompts/zeus/migration-quickstart.md` |
