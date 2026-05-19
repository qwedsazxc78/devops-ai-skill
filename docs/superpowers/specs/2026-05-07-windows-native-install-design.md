# Windows-Native Install — Design Spec

**Status:** implemented — shipped in v1.10.0 (install-global.ps1, install-tools.ps1, install.bat); install.bat moved to scripts/setup/ in v1.13.1
**Date:** 2026-05-07
**Author:** alexhsieh (via brainstorming session)
**Target release:** devops-ai-skill v1.10.0
**Touches:** `scripts/`, repo root, `README.md`, `docs/quick-start*.md`, `docs/setup.md`, `docs/README.zh-*.md`

## 1. Overview

Today the DevOps AI Skill Pack installs cleanly on macOS and Linux via three bash
scripts (`install-global.sh`, `install-tools.sh`, `setup.sh`). Windows is
"supported" only via Git Bash / WSL — `docs/quick-start.md` line 162 punts
Windows users to those bash environments.

This spec adds **first-class native Windows install** through two PowerShell 5.1
scripts plus a one-click `install.bat` launcher at the repo root. The bash
scripts remain authoritative for macOS/Linux and unchanged. The PowerShell
scripts are line-for-line ports — same flags, same behavior, same observable
side effects — translated into pwsh idioms.

The user-visible Windows UX becomes:

```
git clone <repo>
cd devops-ai-skill
.\install.bat
```

with a 3-option menu (skills / tools / both) and the same `--status` /
`--uninstall` semantics as bash.

## 2. Goals & Non-Goals

### Goals
1. **Native one-click on a stock Windows 10/11 box** — no Git Bash, no WSL,
   no PowerShell 7 install required.
2. **Behavioral parity with bash** — same flags, same auto-detect, same
   per-platform layout, same idempotent re-run semantics.
3. **Slim port** — minimum new code, zero Windows-specific feature creep.
   If bash doesn't do it, the .ps1 doesn't do it.
4. **Four observable acceptance signals** all reachable from `--status`:
   tool install, status check, slash-command discoverability, agent + skill
   installation.

### Non-Goals
1. **Porting `setup.sh` (per-repo symlinks).** Symlinks on Windows require
   Administrator or Developer Mode; the per-repo flow is replaced by
   `install-global.ps1` for Windows users.
2. **Auto-installing prerequisites.** Git for Windows, winget, PowerShell 7
   are documented but not bootstrapped — matches bash behavior on macOS
   without Homebrew.
3. **Windows CI matrix.** Manual smoke test on a Windows VM is sufficient
   for v1; CI is a follow-up.
4. **Refactoring the bash scripts.** No "while we're here" cleanup.

## 3. File Layout

Files added (3):

```
install.bat                     ~25 LoC   Repo-root launcher
scripts/install-global.ps1      ~600 LoC  Mirrors install-global.sh
scripts/install-tools.ps1       ~400 LoC  Mirrors install-tools.sh
```

No file is removed or restructured. `package.json` gains optional `setup:win`
entries (see §11).

## 4. Detailed Design — `install.bat`

Single-purpose: pick a PowerShell host, dispatch to the right .ps1, keep the
window open on error.

```bat
@echo off
setlocal

REM Prefer pwsh.exe (PowerShell 7+) if present, else fall back to powershell.exe
where /q pwsh.exe && set "PS=pwsh.exe" || set "PS=powershell.exe"

echo.
echo === DevOps AI Skill Pack — Windows Install ===
echo.
echo  [1] Install skills (recommended) — agents, skills, pipelines
echo  [2] Install tools                — terraform, helm, kustomize, etc.
echo  [3] Both
echo  [Q] Quit
echo.
set /p CHOICE=Choose:

if /i "%CHOICE%"=="1" %PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1"
if /i "%CHOICE%"=="2" %PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-tools.ps1" install
if /i "%CHOICE%"=="3" (
  %PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1"
  if errorlevel 1 (echo Skill install failed, skipping tool install. & pause & exit /b 1)
  %PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-tools.ps1" install
)

echo.
pause
endlocal
```

`%~dp0` resolves to the .bat's own directory, so `install.bat` works whether
double-clicked from File Explorer, run from `cmd`, or invoked from
PowerShell. The `pause` keeps error output visible after a double-click.

## 5. Detailed Design — `install-global.ps1`

Line-for-line port of `install-global.sh`. Same CLI surface:

```
.\install-global.ps1                # Auto-detect installed CLIs
.\install-global.ps1 -All           # Force all 4 platforms
.\install-global.ps1 -Claude        # Single platform
.\install-global.ps1 -Status        # Show what's installed
.\install-global.ps1 -Uninstall     # Remove all
.\install-global.ps1 -Help
```

Bash → PowerShell translation table:

| Bash construct | PowerShell equivalent |
|---|---|
| `$HOME` | `$env:USERPROFILE` |
| `command -v claude &>/dev/null` | `$null -ne (Get-Command claude -ErrorAction SilentlyContinue)` |
| `cp -r src dst` | `Copy-Item -Path src -Destination dst -Recurse -Force` |
| `mkdir -p dir` | `New-Item -ItemType Directory -Force -Path dir` &#124; Out-Null |
| `rm -rf dir` | `Remove-Item -Recurse -Force -Path dir -ErrorAction SilentlyContinue` |
| `diff -q src dst &>/dev/null` | `(Get-FileHash src).Hash -eq (Get-FileHash dst).Hash` |
| `[[ -d dir ]]` | `Test-Path -LiteralPath dir -PathType Container` |
| `[[ -f file ]]` | `Test-Path -LiteralPath file -PathType Leaf` |
| ANSI color escape `\033[0;32m` | `Write-Host -ForegroundColor Green` |
| `python3 - <<EOF ... PYEOF` JSON edit | Native `ConvertFrom-Json` / `ConvertTo-Json` (see §7) |
| `cat "$VERSION_FILE"` | `Get-Content -Raw -LiteralPath $VersionFile` |
| Heredoc `cat >> file <<'ENTRY'` | `Add-Content -LiteralPath file -Value $here` |
| `set -euo pipefail` | `$ErrorActionPreference = 'Stop'` + explicit `try`/`catch` |

Function mapping (bash → ps1):

| `install-global.sh` | `install-global.ps1` |
|---|---|
| `log_ok` / `log_skip` / `log_warn` / `log_new` / `log_upd` | `Write-Ok` / `Write-Skip` / `Write-Warn` / `Write-New` / `Write-Upd` |
| `cli_exists` / `dir_exists` | `Test-Cli` / `Test-Dir` |
| `detect_platform` | `Test-Platform` |
| `copy_dir` / `copy_file` | `Copy-DirIdempotent` / `Copy-FileIdempotent` |
| `install_claude` | `Install-Claude` |
| `_claude_purge_legacy_direct_install` | `Clear-ClaudeLegacy` |
| `_claude_register_plugin` | `Register-ClaudePlugin` |
| `install_codex` | `Install-Codex` |
| `install_gemini` | `Install-Gemini` |
| `install_antigravity` | `Install-Antigravity` |
| `_antigravity_purge_legacy_workflows` | `Clear-AntigravityLegacy` |
| `do_uninstall` | `Invoke-Uninstall` |
| `_claude_unregister_plugin` | `Unregister-ClaudePlugin` |
| `do_status` / `_status_section` | `Show-Status` / `Show-StatusSection` |
| `main` | top-level `param()` block + dispatch |

Per-platform install paths are byte-identical to bash:

- Claude: `$env:USERPROFILE\.claude\plugins\cache\devops-ai-skill\devops\<version>\…`
  + patches `settings.json` (`extraKnownMarketplaces`, `enabledPlugins`)
  + patches `plugins\installed_plugins.json`
- Codex: `$env:USERPROFILE\.codex\agents\`, `\skills\`, `\prompts\`,
  appends section to `instructions.md`
- Gemini: `$env:USERPROFILE\.gemini\skills\`, `\agents\`,
  `\commands\devops\` (TOML files), `\extensions\devops\`
- Antigravity: `$env:USERPROFILE\.agents\rules\devops.md`, `\skills\`,
  `\workflows\<agent>-<pipeline>.md`

Same legacy-purge logic (the duplicate-prevention work in `install-global.sh`
lines 113–158 and 438–456) ports verbatim.

## 6. Detailed Design — `install-tools.ps1`

Line-for-line port of `install-tools.sh`. Same TOOLS registry, same
`check` / `install [zeus|horus]` subcommands, same 3-attempt retry loop.

Bash → PowerShell translation specific to this script:

| Bash construct | PowerShell equivalent |
|---|---|
| `eval "$cmd" &>/dev/null` | `Invoke-Expression $cmd 2>$null \| Out-Null` |
| `read -r answer` | `$answer = Read-Host` |
| `IFS='\|' read -r a b c <<< "$entry"` | `$a, $b, $c = $entry -split '\|', 7` |
| `printf "%-18s"` table formatting | `'{0,-18}' -f $name` or `Format-Table` |

Package-manager detection probes the same set: `winget`, `choco`, `scoop`
(plus `uv` / `pip3` / `pip` for Python tools). On stock Windows 11, winget
is present by default; on older Windows 10 it may be absent.

**Fail-fast on missing package manager** (matches bash on macOS without
Homebrew):

```powershell
if (-not $PkgManager -and -not $Pip) {
  Write-Host 'No package manager found.' -ForegroundColor Red
  Write-Host 'Install winget:     https://aka.ms/getwinget'
  Write-Host 'Install Chocolatey: https://chocolatey.org/install'
  Write-Host 'Install Scoop:      https://scoop.sh'
  Write-Host 'Install uv:         https://docs.astral.sh/uv/'
  exit 1
}
```

`get_install_cmd` and `get_go_install_path` port directly — both already
encode `winget` / `choco` / `scoop` columns so no logic change is needed.

## 7. JSON Patching Strategy

`install-global.sh` uses python3 heredocs to patch `~/.claude/settings.json`
and `~/.claude/plugins/installed_plugins.json` (lines 203–229 and 237–263).

The PowerShell equivalent uses native cmdlets:

```powershell
$settings = Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json
if (-not $settings.extraKnownMarketplaces) {
  $settings | Add-Member -NotePropertyName 'extraKnownMarketplaces' -NotePropertyValue ([pscustomobject]@{})
}
$settings.extraKnownMarketplaces | Add-Member -NotePropertyName $MarketplaceId -NotePropertyValue ([pscustomobject]@{
  source     = [pscustomobject]@{ source = 'github'; repo = 'qwedsazxc78/devops-ai-skill' }
  autoUpdate = $true
}) -Force
if (-not $settings.enabledPlugins) {
  $settings | Add-Member -NotePropertyName 'enabledPlugins' -NotePropertyValue ([pscustomobject]@{})
}
$settings.enabledPlugins | Add-Member -NotePropertyName $PluginKey -NotePropertyValue $true -Force

$settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
```

### Cosmetic JSON differences (accepted)

- bash `json.dump(..., indent=2, ensure_ascii=False)` → 2-space indent, raw UTF-8
- ps1 `ConvertTo-Json -Depth 20` → 4-space indent, escapes non-ASCII as `\u00xx`

These differ on disk but parse identically. Claude Code reads the file; it
does not diff it. Investing in 2-space + non-escaped output (would require
custom serialization) is **not** in scope.

### Encoding

`Set-Content -Encoding UTF8` on PowerShell 5.1 writes a BOM by default. Use
`[System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))`
to write BOM-less UTF-8, matching bash output. **This is a real risk** —
Claude Code may or may not tolerate a BOM in `settings.json`. Implementation
must use the no-BOM form.

## 8. Acceptance Criteria

All four are observable on a clean Windows 11 VM with Claude Code installed.

| # | Criterion | Verification |
|---|---|---|
| 1 | Tool install works | `.\install.bat` → [2] → `terraform --version` etc. resolve |
| 2 | Status check works | `.\scripts\install-global.ps1 -Status` shows agents, skills, plugin, commands all `[ok]` |
| 3 | Slash commands discoverable | Inside `claude`, `/devops:` autocomplete shows full pipeline list (full, upgrade, security, validate, scaffold, cicd, health, pre-merge, review, diagram, status, gateway-migrate) |
| 4 | Agents + skills installed | Inside `claude`, `@horus` and `@zeus` resolve; `-Status` lists every skill |

Smoke test sequence (all four exercised):

```powershell
git clone https://github.com/qwedsazxc78/devops-ai-skill.git
cd devops-ai-skill
.\install.bat                                       # Choose [3] Both
.\scripts\install-global.ps1 -Status                # Expect all [ok]
.\install.bat                                       # Re-run [1] — expect all [skip]
claude                                              # Type /devops: and @horus
.\scripts\install-global.ps1 -Uninstall             # Clean removal
.\scripts\install-global.ps1 -Status                # Expect "no devops-ai-skill components found"
```

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `Copy-Item -Recurse` over an existing destination produces nested layout (`dst/dst/...`) instead of replacing | Always `Remove-Item -Recurse -Force` first, mirroring `install-global.sh:78` |
| `Set-Content -Encoding UTF8` on PS 5.1 emits BOM, may break Claude's JSON parsing | Use `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)` for both `settings.json` and `installed_plugins.json` |
| Drift between `.sh` and `.ps1` over time | (a) Header comment block on each .ps1 stating "1:1 port of <bash file> — keep in sync"; (b) structure test asserting both files exist and CLI flag set matches |
| `Invoke-Expression` of winget / choco strings is potentially injection-prone | Tool names + commands come from a hard-coded TOOLS array, not user input — same trust model as bash `eval` on the same data |
| ANSI color codes in `Write-Host -ForegroundColor` don't render in legacy `cmd.exe` | Acceptable: PowerShell host (where the .ps1 runs) renders them correctly; cmd-only output is functional, just plain |
| Path separator confusion (`/` vs `\`) | Use `Join-Path` everywhere; never string-concatenate paths |
| `powershell.exe` (5.1) Unicode output may garble box-drawing chars | Set `$OutputEncoding = [System.Text.Encoding]::UTF8` and `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` at script top |

## 10. Out of Scope (Restated, for clarity)

- `setup.sh` per-repo symlink flow (Windows users go through `install-global.ps1`)
- Auto-installing Git for Windows, PowerShell 7, winget, Chocolatey, Scoop
- Windows CI in `.github/workflows/ci.yml`
- Refactoring `install-global.sh` or `install-tools.sh`
- Translating ANY of the bash scripts under `scripts/setup/` (`setup-claude.sh`, etc.) — those are sub-helpers of `setup.sh`, which is itself out of scope
- Translating `release.sh`, `version-*.sh`, `postinstall.js`

## 11. Documentation Updates

| File | Specific change |
|---|---|
| `README.md` (root, ~line 28–92) | Quick Start section: add Windows tab next to bash. Replace `<details>` for Per-repo Install caveat: noted as "Windows: use install-global.ps1 instead". |
| `docs/quick-start.md` (line 22–28 Step 1; line 162–172 FAQ Q: Windows) | Step 1: add Windows alternative `(.\install.bat)`. FAQ Q: replace Git Bash/WSL fallback with native instructions; keep WSL as secondary option. |
| `docs/quick-start.zh-TW.md`, `docs/quick-start.zh-CN.md` | Mirror translated. |
| `docs/setup.md` | New "Windows" section. |
| `docs/README.zh-TW.md`, `docs/README.zh-CN.md` | Mirror Quick Start changes. |
| `package.json` | Add optional script entries: `"setup:win": "powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-global.ps1"`, `"setup:win:tools": "powershell -ExecutionPolicy Bypass -NoProfile -File scripts/install-tools.ps1 install"`. |

## 12. Testing Strategy

### Automated
Extend `tests/test-structure.sh` with three checks:

1. `install.bat` exists at repo root.
2. `scripts/install-global.ps1` exists and references `.claude`, `.codex`,
   `.gemini`, `.agents` (smoke check that all 4 platforms are still wired).
3. CLI flag set in `.ps1` matches the `.sh` set: parse `--all|--claude|...`
   from bash, compare to `param([switch]$All, [switch]$Claude, ...)` in ps1.

### Manual smoke test (per release)
On a clean Windows 11 VM with Claude Code installed, run the §8 sequence
and capture screenshots for `docs/guide/` (mirroring the existing
`01-install-global-run.png` etc.).

### Not done in v1
- Windows runner in GitHub Actions
- Pester unit tests for the .ps1 functions

## 13. Drift Control

Header on both `.ps1` files:

```powershell
# =============================================================================
# install-global.ps1 — 1:1 port of scripts/install-global.sh
# =============================================================================
# IMPORTANT: This file mirrors install-global.sh. When changing behavior,
# update the bash file FIRST (it is the source of truth for macOS/Linux),
# then port the diff here. Do not let these two files diverge.
# =============================================================================
```

Same comment on `install-tools.ps1`. Future PR reviewers should reject any
PR that touches one without the matching change in the other (or with an
explicit "Windows-only" carve-out justification).

## 14. Implementation Order

1. `scripts/install-global.ps1` (largest, riskiest — do first)
2. `scripts/install-tools.ps1` (smaller, follows pattern)
3. `install.bat` (tiny, glues 1 + 2)
4. Manual smoke test on Windows VM
5. Doc updates (6 files)
6. `tests/test-structure.sh` extensions
7. CHANGELOG.md entry
