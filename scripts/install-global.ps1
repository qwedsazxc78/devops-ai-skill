# =============================================================================
# install-global.ps1 -- 1:1 port of scripts/install-global.sh
# =============================================================================
# IMPORTANT: This file mirrors install-global.sh. When changing behavior,
# update the bash file FIRST (it is the source of truth for macOS/Linux),
# then port the diff here. Do not let these two files diverge.
# =============================================================================
# DevOps AI Skill Pack -- Global Install (Windows)
# =============================================================================
# Installs skills and agents into user-level config directories
# (%USERPROFILE%\.claude\, %USERPROFILE%\.codex\, %USERPROFILE%\.gemini\,
# %USERPROFILE%\.agents\) so they are available across ALL projects without
# per-repo symlinks.
#
# Usage:
#   .\install-global.ps1                 # Auto-detect installed CLIs
#   .\install-global.ps1 -All            # Force all platforms
#   .\install-global.ps1 -Claude         # Single platform
#   .\install-global.ps1 -Claude -Gemini # Multiple platforms
#   .\install-global.ps1 -Uninstall      # Remove global installations
#   .\install-global.ps1 -Status         # Show what's installed where
#
# Graceful: skips any platform whose CLI is not installed (unless forced).
# Targets PowerShell 5.1+ (built-in on Windows 10/11).
# =============================================================================

[CmdletBinding()]
param(
  [switch]$All,
  [switch]$Claude,
  [switch]$Codex,
  [switch]$Gemini,
  [switch]$Antigravity,
  [switch]$Uninstall,
  [switch]$Status,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 console output so legacy console hosts render box characters cleanly.
try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# NOTE: Use `Split-Path -LiteralPath` WITHOUT `-Parent`. In Windows PowerShell 5.1,
# `Split-Path -Parent -LiteralPath` is an ambiguous parameter set and throws
# "Parameter set cannot be resolved using the specified named parameters." at
# script start -- which aborted the entire installer on Windows. `-Parent` is the
# default behavior anyway, so omitting it is both correct and unambiguous.
$ScriptDir     = Split-Path -LiteralPath $MyInvocation.MyCommand.Path
$SkillPackDir  = (Resolve-Path -LiteralPath (Join-Path $ScriptDir '..')).Path

# --- Counters ---
$script:Pass = 0
$script:Skip = 0
$script:Warn = 0

# --- Logging helpers (mirror bash log_* functions) ---
function Write-Ok   ([string]$msg) { Write-Host '  [ok]   ' -ForegroundColor Green -NoNewline; Write-Host $msg; $script:Pass++ }
function Write-Skip ([string]$msg) { Write-Host '  [skip] ' -ForegroundColor Yellow -NoNewline; Write-Host $msg; $script:Skip++ }
function Write-WarnLog ([string]$msg) { Write-Host '  [warn] ' -ForegroundColor Yellow -NoNewline; Write-Host $msg; $script:Warn++ }
function Write-New  ([string]$msg) { Write-Host '  [new]  ' -ForegroundColor Green -NoNewline; Write-Host $msg; $script:Pass++ }
function Write-Upd  ([string]$msg) { Write-Host '  [upd]  ' -ForegroundColor Green -NoNewline; Write-Host $msg; $script:Pass++ }
function Write-Purge ([string]$msg) { Write-Host '  [purge]' -ForegroundColor Yellow -NoNewline; Write-Host " $msg" }
function Write-Rm   ([string]$msg) { Write-Host '  [rm]  '  -ForegroundColor Red -NoNewline; Write-Host $msg }
function Write-Dim  ([string]$msg) { Write-Host $msg -ForegroundColor DarkGray }

# --- Detection ---
function Test-Cli ([string]$name) {
  $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Test-Dir ([string]$path) {
  Test-Path -LiteralPath $path -PathType Container
}

# --- Dynamic discovery (keeps uninstall/status in sync with the source tree) ---
# Enumerate skill names straight from skills/ so the lists below never go stale
# when skills are added or removed.
function Get-DiscoveredSkills {
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir 'skills') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Name }
}

# Enumerate the workflow filenames Install-Antigravity writes, derived from the
# same prompts/ sources and the same naming rule (shared-* / <agent>-*).
function Get-DiscoveredWorkflows {
  foreach ($promptDir in @('horus','zeus','shared')) {
    $srcDir = Join-Path $SkillPackDir ('prompts\' + $promptDir)
    if (-not (Test-Dir $srcDir)) { continue }
    Get-ChildItem -LiteralPath $srcDir -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
      $fname = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
      if ($promptDir -eq 'shared') { "shared-$fname" } else { "$promptDir-$fname" }
    }
  }
}

function Test-Platform ([string]$displayName, [string]$cliCmd, [string]$configDir) {
  if (Test-Cli $cliCmd) {
    $ver = ''
    try {
      $ver = (& $cliCmd --version 2>$null | Select-Object -First 1) -join ''
    } catch { $ver = 'installed' }
    if ([string]::IsNullOrWhiteSpace($ver)) { $ver = 'installed' }
    Write-Host '  [ok]   ' -ForegroundColor Green -NoNewline
    Write-Host ("{0,-13} " -f $displayName) -NoNewline
    Write-Host "($ver)" -ForegroundColor DarkGray
    return $true
  } elseif (Test-Dir $configDir) {
    Write-Host '  [dir]  ' -ForegroundColor Yellow -NoNewline
    Write-Host ("{0,-13} " -f $displayName) -NoNewline
    Write-Host '(config dir exists, CLI not in PATH)' -ForegroundColor DarkGray
    return $true
  } else {
    Write-Host '  [--]   ' -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,-13} " -f $displayName) -NoNewline
    Write-Host '(not installed -- skipping)' -ForegroundColor DarkGray
    return $false
  }
}

# --- File / dir copy helpers (idempotent, mirror copy_dir / copy_file) ---
function Copy-DirIdempotent ([string]$src, [string]$dst, [string]$label) {
  if (-not (Test-Dir $src)) {
    Write-WarnLog "$label source not found: $src"
    return
  }
  if (Test-Path -LiteralPath $dst) {
    # Update: remove old, copy new
    Remove-Item -Recurse -Force -LiteralPath $dst
    New-Item -ItemType Directory -Force -Path (Split-Path -LiteralPath $dst) | Out-Null
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-Upd $label
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path -LiteralPath $dst) | Out-Null
    Copy-Item -Path $src -Destination $dst -Recurse -Force
    Write-New $label
  }
}

function Copy-FileIdempotent ([string]$src, [string]$dst, [string]$label) {
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Write-WarnLog "$label source not found: $src"
    return
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -LiteralPath $dst) | Out-Null
  if (Test-Path -LiteralPath $dst -PathType Leaf) {
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) {
      Write-Skip "$label (unchanged)"
      return
    }
    Copy-Item -Path $src -Destination $dst -Force
    Write-Upd $label
  } else {
    Copy-Item -Path $src -Destination $dst -Force
    Write-New $label
  }
}

# Write JSON to disk WITHOUT a UTF-8 BOM (PS 5.1 Set-Content -Encoding UTF8
# would inject one; Claude Code / our other tooling consume BOM-less files).
function Write-JsonNoBom ([string]$path, [string]$json) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path, $json, $utf8NoBom)
}

# --- Platform installers ---

function Install-Claude {
  $base = Join-Path $env:USERPROFILE '.claude'
  Write-Host ''
  Write-Host '=== Claude Code (~/.claude/) ===' -ForegroundColor White

  # --- Legacy cleanup ---
  # Earlier versions of this script copied skills/agents/prompts directly
  # under ~/.claude/{skills,agents,prompts}/ in ADDITION to registering the
  # plugin. That caused every item to appear twice in Claude Code (once
  # unscoped, once under the `devops:` namespace). Remove those legacy
  # duplicates so only the plugin-scoped entries remain.
  Clear-ClaudeLegacy $base

  # Claude Code is plugin-only now: everything lives in the plugin cache
  # and is exposed under the `devops:` namespace via marketplace registration.
  Register-ClaudePlugin $base
}

function Clear-ClaudeLegacy ([string]$base) {
  $legacySkills = @(
    'cicd-enhancer','gateway-api-migration','helm-scaffold',
    'helm-version-upgrade','kustomize-resource-validation','release-validate',
    'repo-detect','terraform-security','terraform-validate','yaml-fix-suggestions'
  )
  $purged = 0
  foreach ($skill in $legacySkills) {
    $p = Join-Path $base ('skills\' + $skill)
    if (Test-Dir $p) {
      Remove-Item -Recurse -Force -LiteralPath $p
      Write-Purge "legacy skill: $skill"
      $purged++
    }
  }
  foreach ($agent in @('horus','zeus')) {
    $p = Join-Path $base ('agents\' + $agent + '.md')
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      Remove-Item -Force -LiteralPath $p
      Write-Purge "legacy agent: $agent.md"
      $purged++
    }
  }
  foreach ($promptDir in @('horus','zeus','shared')) {
    $p = Join-Path $base ('prompts\' + $promptDir)
    if (Test-Dir $p) {
      Remove-Item -Recurse -Force -LiteralPath $p
      Write-Purge "legacy prompts: $promptDir"
      $purged++
    }
  }
  if ($purged -gt 0) {
    Write-Dim "  Removed $purged legacy direct-install items -- now plugin-only"
  }
}

# Register as Claude Code marketplace plugin so /devops:* commands are discoverable
function Register-ClaudePlugin ([string]$base) {
  $settings      = Join-Path $base 'settings.json'
  $installed     = Join-Path $base 'plugins\installed_plugins.json'
  $marketplaceId = 'devops-ai-skill'
  $pluginName    = 'devops'
  $pluginKey     = "$pluginName@$marketplaceId"
  $version       = 'unknown'
  $verFile       = Join-Path $SkillPackDir 'VERSION'
  if (Test-Path -LiteralPath $verFile -PathType Leaf) {
    $version = (Get-Content -Raw -LiteralPath $verFile).Trim()
  }

  # Determine the cache directory
  $cacheDir = Join-Path $base ("plugins\cache\$marketplaceId\$pluginName\$version")

  # Copy plugin files to cache
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

  # .claude-plugin/
  Copy-DirIdempotent (Join-Path $SkillPackDir '.claude-plugin') (Join-Path $cacheDir '.claude-plugin') 'plugin: .claude-plugin'

  # commands/
  $cmdSrc = Join-Path $SkillPackDir 'commands'
  if (Test-Dir $cmdSrc) {
    Copy-DirIdempotent $cmdSrc (Join-Path $cacheDir 'commands') 'plugin: commands'
  }

  # agents/ (flat copy for plugin context)
  $agentsDst = Join-Path $cacheDir 'agents'
  New-Item -ItemType Directory -Force -Path $agentsDst | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir '.claude\agents') -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination (Join-Path $agentsDst $_.Name) -Force
  }

  # skills/
  $skillSrc = Join-Path $SkillPackDir 'skills'
  if (Test-Dir $skillSrc) {
    Copy-DirIdempotent $skillSrc (Join-Path $cacheDir 'skills') 'plugin: skills'
  }

  # prompts/
  foreach ($promptDir in @('horus','zeus','shared')) {
    $srcDir = Join-Path $SkillPackDir ('prompts\' + $promptDir)
    if (-not (Test-Dir $srcDir)) { continue }
    New-Item -ItemType Directory -Force -Path (Join-Path $cacheDir 'prompts') | Out-Null
    $dst = Join-Path $cacheDir ('prompts\' + $promptDir)
    if (Test-Path -LiteralPath $dst) { Remove-Item -Recurse -Force -LiteralPath $dst }
    Copy-Item -Path $srcDir -Destination $dst -Recurse -Force
  }

  # Update settings.json -- add marketplace + enable plugin
  if (Test-Path -LiteralPath $settings -PathType Leaf) {
    try {
      $raw = Get-Content -Raw -LiteralPath $settings
      $obj = $raw | ConvertFrom-Json

      # Add extraKnownMarketplaces entry
      if (-not ($obj.PSObject.Properties.Name -contains 'extraKnownMarketplaces')) {
        $obj | Add-Member -NotePropertyName 'extraKnownMarketplaces' -NotePropertyValue (New-Object PSObject)
      }
      $marketplaceVal = [pscustomobject]@{
        source     = [pscustomobject]@{ source = 'github'; repo = 'qwedsazxc78/devops-ai-skill' }
        autoUpdate = $true
      }
      if ($obj.extraKnownMarketplaces.PSObject.Properties.Name -contains $marketplaceId) {
        $obj.extraKnownMarketplaces.$marketplaceId = $marketplaceVal
      } else {
        $obj.extraKnownMarketplaces | Add-Member -NotePropertyName $marketplaceId -NotePropertyValue $marketplaceVal
      }

      # Enable the plugin
      if (-not ($obj.PSObject.Properties.Name -contains 'enabledPlugins')) {
        $obj | Add-Member -NotePropertyName 'enabledPlugins' -NotePropertyValue (New-Object PSObject)
      }
      if ($obj.enabledPlugins.PSObject.Properties.Name -contains $pluginKey) {
        $obj.enabledPlugins.$pluginKey = $true
      } else {
        $obj.enabledPlugins | Add-Member -NotePropertyName $pluginKey -NotePropertyValue $true
      }

      $json = ($obj | ConvertTo-Json -Depth 20)
      Write-JsonNoBom $settings ($json + "`n")
      Write-Ok 'settings.json: marketplace registered + plugin enabled'
    } catch {
      Write-WarnLog "settings.json: failed to update ($($_.Exception.Message)) -- manual setup needed"
      Write-Dim "    Add to ~/.claude/settings.json enabledPlugins: ""$pluginKey"": true"
    }
  } else {
    Write-WarnLog 'settings.json: not found -- manual setup needed'
    Write-Dim "    Add to ~/.claude/settings.json enabledPlugins: ""$pluginKey"": true"
  }

  # Update installed_plugins.json
  if (Test-Path -LiteralPath $installed -PathType Leaf) {
    try {
      $raw = Get-Content -Raw -LiteralPath $installed
      $data = $raw | ConvertFrom-Json
      $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.000Z')

      if (-not ($data.PSObject.Properties.Name -contains 'plugins')) {
        $data | Add-Member -NotePropertyName 'plugins' -NotePropertyValue (New-Object PSObject)
      }
      $entry = @(
        [pscustomobject]@{
          scope        = 'user'
          installPath  = $cacheDir
          version      = $version
          installedAt  = $now
          lastUpdated  = $now
        }
      )
      if ($data.plugins.PSObject.Properties.Name -contains $pluginKey) {
        $data.plugins.$pluginKey = $entry
      } else {
        $data.plugins | Add-Member -NotePropertyName $pluginKey -NotePropertyValue $entry
      }

      $json = ($data | ConvertTo-Json -Depth 20)
      Write-JsonNoBom $installed ($json + "`n")
      Write-Ok "installed_plugins.json: $pluginKey registered"
    } catch {
      Write-WarnLog "installed_plugins.json: failed to update ($($_.Exception.Message))"
    }
  }
}

function Install-Codex {
  $base = Join-Path $env:USERPROFILE '.codex'
  Write-Host ''
  Write-Host '=== OpenAI Codex CLI (~/.codex/) ===' -ForegroundColor White

  # 1. Agents -- copy agent definitions
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'agents') | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir '.claude\agents') -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileIdempotent $_.FullName (Join-Path $base ('agents\' + $_.Name)) ("agent: " + $_.Name)
  }

  # 2. Skills
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'skills') | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-DirIdempotent $_.FullName (Join-Path $base ('skills\' + $_.Name)) ("skill: " + $_.Name)
  }

  # 3. Prompts -- copy pipeline definitions
  foreach ($promptDir in @('horus','zeus','shared')) {
    $srcDir = Join-Path $SkillPackDir ('prompts\' + $promptDir)
    if (-not (Test-Dir $srcDir)) { continue }
    Copy-DirIdempotent $srcDir (Join-Path $base ('prompts\' + $promptDir)) ("prompts: " + $promptDir)
  }

  # 4. Append agent info to instructions.md if not present
  $instructions = Join-Path $base 'instructions.md'
  $marker       = '<!-- devops-ai-skill -->'
  $hasMarker = $false
  if (Test-Path -LiteralPath $instructions -PathType Leaf) {
    $hasMarker = (Select-String -LiteralPath $instructions -SimpleMatch -Pattern $marker -Quiet)
  }
  if ($hasMarker) {
    Write-Skip 'instructions.md already has devops-ai-skill section'
  } else {
    $entry = @"

<!-- devops-ai-skill -->
## DevOps AI Skill Pack (Global)

Agents at `~/.codex/agents/`, skills at `~/.codex/skills/`, pipelines at `~/.codex/prompts/`.

### Agents
- **Horus** (IaC) -- Read `~/.codex/agents/horus.md` when working with Terraform + Helm + GKE
- **Zeus** (GitOps) -- Read `~/.codex/agents/zeus.md` when working with Kustomize + ArgoCD

### Commands
Horus: `*full`, `*upgrade`, `*security`, `*validate`, `*scaffold`, `*cicd`, `*health`
Zeus: `*full`, `*pre-merge`, `*health`, `*review`, `*scaffold`, `*diagram`, `*status`, `*gateway-migrate`

When a `*command` is triggered, read the corresponding pipeline from `~/.codex/prompts/`.
"@
    Add-Content -LiteralPath $instructions -Value $entry -Encoding UTF8
    Write-Ok 'Appended agent info to instructions.md'
  }
}

function Install-Gemini {
  $base = Join-Path $env:USERPROFILE '.gemini'
  Write-Host ''
  Write-Host '=== Google Gemini CLI (~/.gemini/) ===' -ForegroundColor White

  # 1. Skills -- copy to ~/.gemini/skills/ (User Skills tier)
  Install-GeminiSkills $base

  # 2. Agents -- copy agent definitions
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'agents') | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir '.gemini\agents') -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-FileIdempotent $_.FullName (Join-Path $base ('agents\' + $_.Name)) ("agent: " + $_.Name)
  }

  # 3. Commands -- copy TOML command files for Gemini command palette
  $cmdSrc = Join-Path $SkillPackDir '.gemini\commands\devops'
  if (Test-Dir $cmdSrc) {
    Copy-DirIdempotent $cmdSrc (Join-Path $base 'commands\devops') 'commands: devops'
  }

  # Extension manifest (.gemini/extensions/devops/)
  $extSrc = Join-Path $SkillPackDir '.gemini\extensions\devops'
  if (Test-Dir $extSrc) {
    Copy-DirIdempotent $extSrc (Join-Path $base 'extensions\devops') 'extension: devops'
  }
}

function Install-GeminiSkills ([string]$base) {
  # Copy skills to ~/.gemini/skills/ (the path gemini skills list discovers).
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'skills') | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-DirIdempotent $_.FullName (Join-Path $base ('skills\' + $_.Name)) ("skill: " + $_.Name)
  }
}

function Install-Antigravity {
  Write-Host ''
  Write-Host '=== Antigravity (~/.agents/) ===' -ForegroundColor White

  $base = Join-Path $env:USERPROFILE '.agents'

  # --- Legacy cleanup ---
  Clear-AntigravityLegacy $base

  # 1. Rules
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'rules') | Out-Null
  $rulesSrc = Join-Path $SkillPackDir '.agents\rules\devops.md'
  if (Test-Path -LiteralPath $rulesSrc -PathType Leaf) {
    Copy-FileIdempotent $rulesSrc (Join-Path $base 'rules\devops.md') 'rules: devops.md'
  }

  # 2. Agent skill wrappers (horus/zeus SKILL.md)
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir '.agents\skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-DirIdempotent $_.FullName (Join-Path $base ('skills\' + $_.Name)) ("agent-skill: " + $_.Name)
  }

  # 3. Skills -- Gemini CLI scans BOTH ~/.gemini/skills/ AND ~/.agents/skills/.
  #    If a skill exists in ~/.gemini/skills/, remove it from ~/.agents/skills/
  #    to avoid "Skill conflict" warnings, then skip the copy.
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'skills') | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $SkillPackDir 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $name        = $_.Name
    $geminiCopy  = Join-Path $env:USERPROFILE ('.gemini\skills\' + $name)
    $agentsCopy  = Join-Path $base ('skills\' + $name)
    if (Test-Dir $geminiCopy) {
      if (Test-Dir $agentsCopy) {
        Remove-Item -Recurse -Force -LiteralPath $agentsCopy
        Write-Ok "skill: $name (removed from ~/.agents/, using ~/.gemini/)"
      } else {
        Write-Skip "skill: $name (in ~/.gemini/skills/)"
      }
    } else {
      Copy-DirIdempotent $_.FullName $agentsCopy ("skill: " + $name)
    }
  }

  # 4. Workflows -- copy pipeline prompts to ~/.agents/workflows/
  New-Item -ItemType Directory -Force -Path (Join-Path $base 'workflows') | Out-Null
  foreach ($promptDir in @('horus','zeus','shared')) {
    $srcDir = Join-Path $SkillPackDir ('prompts\' + $promptDir)
    if (-not (Test-Dir $srcDir)) { continue }
    Get-ChildItem -LiteralPath $srcDir -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object {
      $fname = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
      if ($promptDir -eq 'shared') {
        $wfName = "shared-$fname"
      } else {
        $wfName = "$promptDir-$fname"
      }
      Copy-FileIdempotent $_.FullName (Join-Path $base ('workflows\' + $wfName + '.md')) ("workflow: " + $wfName)
    }
  }
}

# Remove ~/.agents/workflows/ entries that no longer correspond to any
# source pipeline.
function Clear-AntigravityLegacy ([string]$base) {
  $stale = @('horus-new-module','zeus-health-check','zeus-onboard')
  $purged = 0
  foreach ($wf in $stale) {
    $p = Join-Path $base ('workflows\' + $wf + '.md')
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      Remove-Item -Force -LiteralPath $p
      Write-Purge "legacy workflow: $wf"
      $purged++
    }
  }
  if ($purged -gt 0) {
    Write-Dim "  Removed $purged stale workflow(s) from previous installs"
  }
}

# --- Uninstall ---
function Remove-IfExists ([string]$path, [string]$label) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -Recurse -Force -LiteralPath $path -ErrorAction SilentlyContinue
    Write-Rm $label
    return $true
  }
  return $false
}

function Unregister-ClaudePlugin {
  $settings  = Join-Path $env:USERPROFILE '.claude\settings.json'
  $installed = Join-Path $env:USERPROFILE '.claude\plugins\installed_plugins.json'
  $any = $false

  # Remove from settings.json
  if (Test-Path -LiteralPath $settings -PathType Leaf) {
    try {
      $obj = (Get-Content -Raw -LiteralPath $settings) | ConvertFrom-Json
      $changed = $false
      if (($obj.PSObject.Properties.Name -contains 'extraKnownMarketplaces') -and
          ($obj.extraKnownMarketplaces.PSObject.Properties.Name -contains 'devops-ai-skill')) {
        $obj.extraKnownMarketplaces.PSObject.Properties.Remove('devops-ai-skill')
        $changed = $true
      }
      if (($obj.PSObject.Properties.Name -contains 'enabledPlugins') -and
          ($obj.enabledPlugins.PSObject.Properties.Name -contains 'devops@devops-ai-skill')) {
        $obj.enabledPlugins.PSObject.Properties.Remove('devops@devops-ai-skill')
        $changed = $true
      }
      if ($changed) {
        Write-JsonNoBom $settings (($obj | ConvertTo-Json -Depth 20) + "`n")
        Write-Rm 'settings.json: devops-ai-skill entries'
        $any = $true
      }
    } catch { }
  }

  # Remove from installed_plugins.json
  if (Test-Path -LiteralPath $installed -PathType Leaf) {
    try {
      $data = (Get-Content -Raw -LiteralPath $installed) | ConvertFrom-Json
      if (($data.PSObject.Properties.Name -contains 'plugins') -and
          ($data.plugins.PSObject.Properties.Name -contains 'devops@devops-ai-skill')) {
        $data.plugins.PSObject.Properties.Remove('devops@devops-ai-skill')
        Write-JsonNoBom $installed (($data | ConvertTo-Json -Depth 20) + "`n")
        Write-Rm 'installed_plugins.json: devops@devops-ai-skill'
        $any = $true
      }
    } catch { }
  }
  return $any
}

function Invoke-Uninstall {
  Write-Host ''
  Write-Host '=== Uninstall (Global) ===' -ForegroundColor White

  $removed = 0
  $skills = @(Get-DiscoveredSkills)

  # Claude
  foreach ($agent in @('horus','zeus')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".claude\agents\$agent.md")) "~/.claude/agents/$agent.md") { $removed++ }
  }
  foreach ($skill in $skills) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".claude\skills\$skill"))   "~/.claude/skills/$skill")  { $removed++ }
  }
  foreach ($promptDir in @('horus','zeus','shared')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".claude\prompts\$promptDir")) "~/.claude/prompts/$promptDir") { $removed++ }
  }
  if (Remove-IfExists (Join-Path $env:USERPROFILE '.claude\plugins\cache\devops-ai-skill') '~/.claude/plugins/cache/devops-ai-skill') { $removed++ }
  if (Unregister-ClaudePlugin) { $removed++ }

  # Codex
  foreach ($agent in @('horus','zeus')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".codex\agents\$agent.md")) "~/.codex/agents/$agent.md") { $removed++ }
  }
  foreach ($skill in $skills) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".codex\skills\$skill"))   "~/.codex/skills/$skill")   { $removed++ }
  }
  foreach ($promptDir in @('horus','zeus','shared')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".codex\prompts\$promptDir")) "~/.codex/prompts/$promptDir") { $removed++ }
  }

  # Gemini
  foreach ($agent in @('horus','zeus')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".gemini\agents\$agent.md")) "~/.gemini/agents/$agent.md") { $removed++ }
  }
  foreach ($skill in $skills) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".gemini\skills\$skill"))   "~/.gemini/skills/$skill")  { $removed++ }
  }
  if (Remove-IfExists (Join-Path $env:USERPROFILE '.gemini\extensions\devops') '~/.gemini/extensions/devops') { $removed++ }
  if (Remove-IfExists (Join-Path $env:USERPROFILE '.gemini\commands\devops')   '~/.gemini/commands/devops')   { $removed++ }

  # Antigravity / shared ~/.agents/
  if (Remove-IfExists (Join-Path $env:USERPROFILE '.agents\rules\devops.md') '~/.agents/rules/devops.md') { $removed++ }
  foreach ($agent in @('horus','zeus')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".agents\skills\$agent")) "~/.agents/skills/$agent") { $removed++ }
  }
  foreach ($skill in $skills) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".agents\skills\$skill")) "~/.agents/skills/$skill") { $removed++ }
  }
  # Workflows -- enumerated from prompts/ with the same naming rule install
  # uses, so new pipelines are removed too (never goes stale).
  $workflows = @(Get-DiscoveredWorkflows)
  foreach ($wf in $workflows) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".agents\workflows\$wf.md")) "~/.agents/workflows/$wf.md") { $removed++ }
  }
  # Legacy filenames left behind by older installs
  foreach ($wf in @('horus-new-module','zeus-health-check','zeus-onboard','horus-full','zeus-full')) {
    if (Remove-IfExists (Join-Path $env:USERPROFILE (".agents\workflows\$wf.md")) "~/.agents/workflows/$wf.md") { $removed++ }
  }

  Write-Host ''
  Write-Host "Removed " -NoNewline; Write-Host $removed -ForegroundColor Red -NoNewline; Write-Host ' items.'
  Write-Host 'Note:' -ForegroundColor Yellow -NoNewline
  Write-Host ' Entry sections in ~/.codex/instructions.md were NOT removed.'
  Write-Host "Search for '<!-- devops-ai-skill -->' to remove manually."
}

# --- Status ---
function Show-Status {
  Write-Host ''
  Write-Host '=== Global Install Status ===' -ForegroundColor White

  Show-StatusSection 'Claude Code' (Join-Path $env:USERPROFILE '.claude')
  Show-StatusSection 'Codex CLI'   (Join-Path $env:USERPROFILE '.codex')
  Show-StatusSection 'Gemini CLI'  (Join-Path $env:USERPROFILE '.gemini')
  Show-StatusSection 'Antigravity' (Join-Path $env:USERPROFILE '.agents')
}

function Show-StatusSection ([string]$label, [string]$base) {
  $skills = @(Get-DiscoveredSkills)
  $found = 0

  Write-Host ''
  Write-Host "$label " -ForegroundColor White -NoNewline
  Write-Host "($base/)"

  if (-not (Test-Dir $base)) {
    Write-Dim '  not installed'
    return
  }

  # Agents
  foreach ($agent in @('horus','zeus')) {
    if (Test-Path -LiteralPath (Join-Path $base ("agents\$agent.md")) -PathType Leaf) {
      Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " agent: $agent"
      $found++
    } elseif (Test-Path -LiteralPath (Join-Path $base ("skills\$agent\SKILL.md")) -PathType Leaf) {
      Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " agent-skill: $agent"
      $found++
    }
  }

  # Skills
  foreach ($skill in $skills) {
    if (Test-Dir (Join-Path $base ("skills\$skill"))) {
      Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " skill: $skill"
      $found++
    }
  }

  # Rules
  if (Test-Path -LiteralPath (Join-Path $base 'rules\devops.md') -PathType Leaf) {
    Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host ' rules: devops.md'
    $found++
  }

  # Extensions (Gemini)
  if (Test-Dir (Join-Path $base 'extensions\devops')) {
    Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host ' extension: devops'
    $found++
  }

  # Commands (Gemini)
  $cmdDir = Join-Path $base 'commands\devops'
  if (Test-Dir $cmdDir) {
    $cmdCount = (Get-ChildItem -LiteralPath $cmdDir -Filter '*.toml' -Recurse -ErrorAction SilentlyContinue).Count
    Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " commands: $cmdCount toml files"
    $found++
  }

  # Plugin (Claude -- /devops:* commands)
  $cacheDir = Join-Path $base 'plugins\cache\devops-ai-skill'
  if (Test-Dir $cacheDir) {
    $cmdMdCount = (Get-ChildItem -LiteralPath $cacheDir -Filter '*.md' -Recurse -ErrorAction SilentlyContinue |
                   Where-Object { $_.FullName -match '\\commands\\' }).Count
    Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " plugin: devops ($cmdMdCount commands -> /devops:*)"
    $found++
  }

  # Prompts (Codex)
  $promptsDir = Join-Path $base 'prompts'
  if (Test-Dir $promptsDir) {
    $promptCount = (Get-ChildItem -LiteralPath $promptsDir -Filter '*.md' -Recurse -ErrorAction SilentlyContinue).Count
    if ($promptCount -gt 0) {
      Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " prompts: $promptCount pipeline files"
      $found++
    }
  }

  # Workflows (Antigravity)
  $wfDir = Join-Path $base 'workflows'
  if (Test-Dir $wfDir) {
    $wfCount = (Get-ChildItem -LiteralPath $wfDir -Filter '*.md' -Recurse -ErrorAction SilentlyContinue).Count
    if ($wfCount -gt 0) {
      Write-Host '  [ok]' -ForegroundColor Green -NoNewline; Write-Host " workflows: $wfCount pipeline files"
      $found++
    }
  }

  if ($found -eq 0) {
    Write-Dim '  no devops-ai-skill components found'
  }
}

# --- Help ---
function Show-Help {
  Write-Host ''
  Write-Host 'Usage: .\install-global.ps1 [OPTIONS]'
  Write-Host ''
  Write-Host 'Options:'
  Write-Host '  (no flags)        Auto-detect installed CLIs and install'
  Write-Host '  -All              Force install for all 4 platforms'
  Write-Host '  -Claude           Install for Claude Code only'
  Write-Host '  -Codex            Install for Codex CLI only'
  Write-Host '  -Gemini           Install for Gemini CLI only'
  Write-Host '  -Antigravity      Install for Windsurf/Antigravity only'
  Write-Host '  -Status           Show current global install status'
  Write-Host '  -Uninstall        Remove all global installations'
  Write-Host '  -Help             Show this help'
}

# --- Main ---
function Invoke-Main {
  Write-Host ''
  Write-Host '+----------------------------------------------+' -ForegroundColor White
  Write-Host '|   DevOps AI Skill Pack -- Global Install     |' -ForegroundColor White
  Write-Host '+----------------------------------------------+' -ForegroundColor White
  Write-Host ''
  Write-Host '  Source: ' -NoNewline; Write-Host $SkillPackDir -ForegroundColor Cyan

  # Validate source
  if (-not (Test-Dir (Join-Path $SkillPackDir 'skills'))) {
    Write-Host "Error: skills/ directory not found in $SkillPackDir" -ForegroundColor Red
    exit 1
  }

  if ($Help) { Show-Help; exit 0 }
  if ($Status) { Show-Status; exit 0 }
  if ($Uninstall) { Invoke-Uninstall; exit 0 }

  $doClaude = $Claude.IsPresent
  $doCodex  = $Codex.IsPresent
  $doGemini = $Gemini.IsPresent
  $doAg     = $Antigravity.IsPresent
  $parsed   = $doClaude -or $doCodex -or $doGemini -or $doAg -or $All.IsPresent

  # Auto-detect mode: detect which CLIs are installed
  if (-not $parsed) {
    Write-Host ''
    Write-Host 'Detecting installed platforms...' -ForegroundColor White
    if (Test-Platform 'Claude Code'  'claude'      (Join-Path $env:USERPROFILE '.claude'))  { $doClaude = $true }
    if (Test-Platform 'Codex CLI'    'codex'       (Join-Path $env:USERPROFILE '.codex'))   { $doCodex  = $true }
    if (Test-Platform 'Gemini CLI'   'gemini'      (Join-Path $env:USERPROFILE '.gemini'))  { $doGemini = $true }
    if (Test-Platform 'Antigravity'  'antigravity' (Join-Path $env:USERPROFILE '.agents'))  { $doAg     = $true }

    if (-not ($doClaude -or $doCodex -or $doGemini -or $doAg)) {
      Write-Host ''
      Write-Host 'No supported AI coding tools detected.' -ForegroundColor Yellow
      Write-Host 'Install one of: claude, codex, gemini, antigravity'
      Write-Host 'Or use -All to force install for all platforms.'
      exit 1
    }
  }

  # Force all
  if ($All) {
    $doClaude = $true; $doCodex = $true; $doGemini = $true; $doAg = $true
  }

  if ($doClaude) { Install-Claude }
  if ($doCodex)  { Install-Codex }
  if ($doGemini) { Install-Gemini }
  if ($doAg)     { Install-Antigravity }

  # Summary
  Write-Host ''
  Write-Host ('=' * 47) -ForegroundColor White
  Write-Host '  OK: ' -NoNewline; Write-Host $script:Pass -ForegroundColor Green -NoNewline
  Write-Host '  SKIP: ' -NoNewline; Write-Host $script:Skip -ForegroundColor Yellow -NoNewline
  Write-Host '  WARN: ' -NoNewline; Write-Host $script:Warn -ForegroundColor Yellow
  Write-Host ('=' * 47) -ForegroundColor White
  Write-Host ''
  Write-Host 'Global install complete!' -ForegroundColor Green
  Write-Host ''
  Write-Host "To update later:  powershell -ExecutionPolicy Bypass -File $ScriptDir\install-global.ps1"
  Write-Host "To check status:  powershell -ExecutionPolicy Bypass -File $ScriptDir\install-global.ps1 -Status"
  Write-Host "To uninstall:     powershell -ExecutionPolicy Bypass -File $ScriptDir\install-global.ps1 -Uninstall"
}

# Top-level error handler: surface a clean message + non-zero exit instead of a
# raw PowerShell stack trace. ($ErrorActionPreference='Stop' turns cmdlet errors
# into terminating errors; the `exit N` calls inside Invoke-Main terminate the
# process directly and are intentionally NOT caught here.)
try {
  Invoke-Main
} catch {
  Write-Host ''
  Write-Host '[ERROR] ' -ForegroundColor Red -NoNewline
  Write-Host "Global install failed: $($_.Exception.Message)"
  if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
    Write-Host ("    at line {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
  }
  Write-Host '    Re-run with -Status to inspect current state, or open an issue with the message above.' -ForegroundColor DarkGray
  exit 1
}
