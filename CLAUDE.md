# CLAUDE.md

Read `docs/PROJECT.md` first — it contains all shared project context.

## Claude Code Specifics

- Agent definitions: `.claude/agents/horus.md` and `.claude/agents/zeus.md`
- Skills directory: `skills/` (each skill has `SKILL.md` with YAML frontmatter)
- Plugin config: `.claude-plugin/plugin.json`

## Windows Install Scripts & Testing

Windows entry points live under `scripts/`:

| File | Role |
|------|------|
| `scripts/setup/install.bat` | One-click launcher (menu: skills / tools / both / status / uninstall). Resolves `pwsh.exe` → `powershell.exe` and dispatches with `-ExecutionPolicy Bypass`. |
| `scripts/install-global.ps1` | 1:1 port of `install-global.sh` (skills/agents/plugin install). |
| `scripts/install-tools.ps1` | 1:1 port of `install-tools.sh` (winget/choco/scoop/uv tool install). |

**Mirror rule:** the `.sh` files are the source of truth — change behavior there
first, then port the diff to the matching `.ps1`. Do not let them diverge.

**PowerShell 5.1 gotchas (Windows ships 5.1 by default):**
- `Split-Path -Parent -LiteralPath` is an **ambiguous parameter set** in 5.1 and
  throws *"Parameter set cannot be resolved…"*. Use `Split-Path -LiteralPath`
  (`-Parent` is the default).
- Running a bare `.\script.ps1` is blocked by the default `Restricted` policy
  (*"running scripts is disabled on this system"*). Invoke via
  `powershell -ExecutionPolicy Bypass -File scripts\<name>.ps1 …` or `install.bat`.
  Per-user installs need **no admin / UAC** — never self-elevate (it would write
  to the Administrator profile, not the user's).
- Uninstall/status lists are **discovered dynamically** from `skills/` and
  `prompts/` (see `Get-DiscoveredSkills` / `_discover_skills`). Do not hardcode
  skill/workflow names — they go stale as the set grows.

**Smoke test (non-destructive paths first):**
```powershell
powershell -NoProfile -File scripts\install-global.ps1 -Help
powershell -NoProfile -File scripts\install-global.ps1 -Status
powershell -NoProfile -File scripts\install-global.ps1 -All       # then -Uninstall; expect 0 leftovers
powershell -NoProfile -File scripts\install-tools.ps1 check
```
Also parse-check (`[System.Management.Automation.PSParser]::Tokenize`) both `.ps1`
and `bash -n scripts/install-global.sh` for the mirror.

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
