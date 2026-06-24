# =============================================================================
# install-tools.ps1 -- 1:1 port of scripts/install-tools.sh
# =============================================================================
# IMPORTANT: This file mirrors install-tools.sh. When changing behavior,
# update the bash file FIRST (it is the source of truth for macOS/Linux),
# then port the diff here. Do not let these two files diverge.
# =============================================================================
# DevOps AI Skill Pack -- Tool Installer (Windows)
# =============================================================================
# Installs required and recommended tools for Horus (IaC) and Zeus (GitOps)
# using winget / choco / scoop / pip / uv.
#
# Usage:
#   .\install-tools.ps1                 # Interactive: check + prompt install
#   .\install-tools.ps1 check           # Check tool availability only
#   .\install-tools.ps1 install         # Install all missing tools
#   .\install-tools.ps1 install zeus    # Install Zeus (GitOps) tools only
#   .\install-tools.ps1 install horus   # Install Horus (IaC) tools only
# =============================================================================

[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command,
  [Parameter(Position = 1)][string]$Filter = 'all'
)

# Force UTF-8 console output for box characters / non-ASCII tool names.
try {
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# --- Counters ---
$script:TotalOk      = 0
$script:TotalMissing = 0

# --- Platform detection ---
function Test-PlatformInfo {
  # Refresh PATH from the registry + per-user bin dirs first, so detection (and
  # the "already installed" check) sees tools added since this terminal opened.
  Update-SessionPath
  $script:Arch = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
  switch ($script:Arch) {
    9 { $script:Arch = 'x64' }
    12 { $script:Arch = 'arm64' }
    Default { $script:Arch = "$($script:Arch)" }
  }
  $script:OS         = 'Windows'
  $script:PkgManager = ''
  $script:Pip        = ''

  # Detect package manager (Windows preference order)
  if (Test-Cli 'winget') {
    $script:PkgManager = 'winget'
  } elseif (Test-Cli 'choco') {
    $script:PkgManager = 'choco'
  } elseif (Test-Cli 'scoop') {
    $script:PkgManager = 'scoop'
  } elseif (Test-Cli 'brew') {
    # On Windows this means user has brew via WSL or unusual setup -- accept it
    $script:PkgManager = 'brew'
  }

  # Python installer: prefer uv > pip3 > pip
  if (Test-Cli 'uv') {
    $script:Pip = 'uv'
  } elseif (Test-Cli 'pip3') {
    $script:Pip = 'pip3'
  } elseif (Test-Cli 'pip') {
    $script:Pip = 'pip'
  }

  $pkg = if ($script:PkgManager) { $script:PkgManager } else { 'none' }
  $py  = if ($script:Pip) { $script:Pip } else { 'none' }
  Write-Host 'Platform: ' -ForegroundColor Blue -NoNewline
  Write-Host "$($script:OS) ($($script:Arch))" -NoNewline
  Write-Host " | Package manager: $pkg | Python installer: $py`n"
}

function Test-Cli ([string]$name) {
  $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

# --- Tool registry ---
# Format: name|category|tier|brew_cmd|apt_cmd|pip_cmd|winget_cmd
# category: shared, zeus, horus
# tier:     required, recommended
$TOOLS = @(
  # Shared
  'node|shared|required|brew install node|apt-get install -y nodejs||winget install OpenJS.NodeJS.LTS'
  'git|shared|required|brew install git|apt-get install -y git||winget install Git.Git'
  'kubectl|shared|required|brew install kubectl|snap install kubectl --classic||winget install Kubernetes.kubectl'
  'jq|shared|required|brew install jq|apt-get install -y jq||winget install jqlang.jq'
  'yq|shared|recommended|brew install yq|snap install yq||winget install MikeFarah.yq'
  'python3|shared|recommended|brew install python3|apt-get install -y python3||winget install Python.Python.3.12'
  'curl|shared|recommended|brew install curl|apt-get install -y curl||winget install cURL.cURL'

  # Zeus -- Required
  'kustomize|zeus|required|brew install kustomize|snap install kustomize||winget install Kubernetes.kustomize'

  # Zeus -- Recommended
  'yamllint|zeus|recommended|||pip install yamllint|'
  'kubeconform|zeus|recommended|brew install kubeconform|||winget install YannHamon.kubeconform'
  'ingress2gateway|zeus|recommended|brew install ingress2gateway|||winget install Kubernetes.ingress2gateway'
  'kube-score|zeus|recommended|brew install kube-score|||'
  'kube-linter|zeus|recommended|brew install kube-linter|||winget install stackrox.kube-linter'
  'polaris|zeus|recommended|brew install FairwindsOps/tap/polaris|||scoop install polaris'
  'pluto|zeus|recommended|brew install FairwindsOps/tap/pluto|||scoop install pluto'
  'conftest|zeus|recommended|brew install conftest|||'
  'checkov|zeus|recommended|||pip install checkov|'
  'trivy|zeus|recommended|brew install trivy|||winget install AquaSecurity.Trivy'
  'gitleaks|zeus|recommended|brew install gitleaks|||winget install Gitleaks.Gitleaks'
  'd2|zeus|recommended|brew install d2|||scoop install d2'

  # Horus -- Required
  'terraform|horus|required|brew install terraform|||winget install Hashicorp.Terraform'
  'helm|horus|required|brew install helm|snap install helm --classic||winget install Helm.Helm'

  # Horus -- Recommended
  'tflint|horus|recommended|brew install tflint|||winget install TerraformLinters.tflint'
  'tfsec|horus|recommended|brew install tfsec|||'
  'pre-commit|horus|recommended|||pip install pre-commit|'
)

# --- Helpers ---
function Test-Tool ([string]$name) {
  if (Test-Cli $name) {
    $ver = ''
    try {
      $ver = (& $name --version 2>$null | Select-Object -First 1)
      if (-not $ver) { $ver = (& $name version 2>$null | Select-Object -First 1) }
    } catch { }
    if (-not $ver) { $ver = 'installed' }
    if ($ver.Length -gt 40) { $ver = $ver.Substring(0, 40) }
    Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
    Write-Host (' {0,-18} {1}' -f $name, $ver)
    $script:TotalOk++
    return $true
  } else {
    Write-Host '  [--] ' -ForegroundColor Red -NoNewline
    Write-Host (' {0,-18} ' -f $name) -NoNewline
    Write-Host 'not installed' -ForegroundColor Yellow
    $script:TotalMissing++
    return $false
  }
}

function Get-GoInstallPath ([string]$name) {
  switch ($name) {
    'ingress2gateway' { return 'github.com/kubernetes-sigs/ingress2gateway@latest' }
    'kube-score'      { return 'github.com/zegl/kube-score/cmd/kube-score@latest' }
    'kubeconform'     { return 'github.com/yannh/kubeconform/cmd/kubeconform@latest' }
    'conftest'        { return 'github.com/open-policy-agent/conftest@latest' }
    'tfsec'           { return 'github.com/aquasecurity/tfsec/cmd/tfsec@latest' }
    Default            { return '' }
  }
}

function Get-InstallCmd ([string]$entry) {
  $parts = $entry -split '\|', 7
  $name      = $parts[0]
  # category = $parts[1]; tier = $parts[2]
  $brewCmd   = $parts[3]
  # apt_cmd  = $parts[4]
  $pipCmd    = $parts[5]
  $wingetCmd = $parts[6]

  # Python tools first (cross-platform). Prefer an existing pip; otherwise emit
  # the uv command even when uv/pip are absent -- Install-Manager bootstraps uv
  # before the command runs.
  if ($pipCmd) {
    $pkg = $pipCmd -replace '^pip install ', ''
    if ($script:Pip -eq 'pip3' -or $script:Pip -eq 'pip') {
      return "$($script:Pip) install --user $pkg"
    }
    return "uv tool install $pkg"
  }

  # Platform package manager
  switch ($script:PkgManager) {
    'brew'   { if ($brewCmd)   { return $brewCmd } }
    'winget' { if ($wingetCmd) { return $wingetCmd } }
    'choco'  { return "choco install $name -y" }
    'scoop'  { return "scoop install $name" }
  }

  # `go install` fallback for Go-native tools without a Windows package. Go is
  # bootstrapped by Install-Manager when absent, so emit the command regardless
  # of whether `go` is currently on PATH.
  $goPath = Get-GoInstallPath $name
  if ($goPath) {
    return "go install $goPath"
  }

  return ''
}

function Get-InstallHint ([string]$entry) {
  $parts = $entry -split '\|', 7
  $name      = $parts[0]
  $brewCmd   = $parts[3]
  $pipCmd    = $parts[5]
  $wingetCmd = $parts[6]

  if ($wingetCmd) { return "$wingetCmd (needs winget)" }
  # On Windows, prefer the cross-platform Go / pip paths over Homebrew (macOS/Linux only).
  $goPath = Get-GoInstallPath $name
  if ($goPath) { return "go install $goPath (needs Go toolchain)" }
  if ($pipCmd) {
    $pkg = $pipCmd -replace '^pip install ', ''
    return "uv tool install $pkg (needs uv or pip)"
  }
  if ($brewCmd)   { return "$brewCmd (needs Homebrew, macOS/Linux only)" }
  return "see https://github.com/search?q=$name for install instructions"
}

# --- Installer bootstrap ----------------------------------------------------
$script:Bootstrapped = @{}

# Per-user bin dirs that tools land in but that their installers do NOT always
# add to PATH: `go install` -> ~\go\bin, `uv tool install` -> ~\.local\bin,
# scoop -> ~\scoop\shims (scoop DOES persist this itself). Persisting these to
# the User PATH is what lets a NEW terminal find the tools after install.
function Get-PerUserBinDirs {
  @(
    (Join-Path $env:USERPROFILE 'go\bin'),
    (Join-Path $env:USERPROFILE '.local\bin'),
    (Join-Path $env:USERPROFILE 'scoop\shims')
  )
}

# Refresh THIS session's PATH from the Machine + User registry values plus the
# per-user bin dirs above. Merges (never drops existing entries) and dedups.
# This is why `check` can detect freshly installed tools without a new terminal.
function Update-SessionPath {
  $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = New-Object System.Collections.Generic.List[string]
  foreach ($src in @($env:Path, $machine, $user, (Get-PerUserBinDirs -join ';'))) {
    if (-not $src) { continue }
    foreach ($p in ($src -split ';')) {
      $t = $p.Trim()
      if ($t -and -not ($parts -contains $t)) { $parts.Add($t) }
    }
  }
  $env:Path = ($parts -join ';')
}

# Persist a directory to the USER PATH (survives across terminals) if missing.
function Add-ToUserPath ([string]$dir) {
  if (-not $dir) { return }
  $cur = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @(); if ($cur) { $parts = @($cur -split ';' | Where-Object { $_ }) }
  if ($parts -notcontains $dir) {
    [System.Environment]::SetEnvironmentVariable('Path', (@($parts + $dir) -join ';'), 'User')
  }
}

# Persist the per-user tool bin dirs to the User PATH so a new terminal finds
# go-/uv-installed tools. Called once after a successful install batch.
function Save-PerUserBinPath {
  foreach ($d in (Get-PerUserBinDirs)) {
    if (Test-Path $d) { Add-ToUserPath $d }
  }
}

# Install-Manager: bootstrap a missing installer/toolchain on demand (scoop,
# choco, go, uv, pip) so tools that depend on it become installable without the
# user pre-installing it. $mgr is the leading token of an install command.
# Returns $true if the installer is available afterwards. winget is assumed
# present (it ships with Windows 10 1809+ / 11) and is never bootstrapped.
function Install-Manager ([string]$mgr) {
  if (Test-Cli $mgr) { return $true }
  if ($script:Bootstrapped.ContainsKey($mgr)) { return (Test-Cli $mgr) }
  $script:Bootstrapped[$mgr] = $true

  Write-Host '  [bootstrap] ' -ForegroundColor Cyan -NoNewline
  Write-Host "$mgr not found -- installing it ..."

  try {
    switch ($mgr) {
      'go' {
        Invoke-Expression 'winget install -e --id GoLang.Go --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null'
      }
      'scoop' {
        # Official per-user install (no admin). Requires RemoteSigned for the
        # current user; set it process-scoped so we never touch machine policy.
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
        Invoke-Expression (Invoke-RestMethod -Uri 'https://get.scoop.sh') 2>&1 | Out-Null
      }
      'choco' {
        if (-not (Test-IsAdmin)) {
          Write-Host '  [bootstrap] ' -ForegroundColor Cyan -NoNewline
          Write-Host 'choco needs an elevated shell -- skipping. Re-run PowerShell as Administrator to install choco-only tools.' -ForegroundColor Yellow
          return $false
        }
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')) 2>&1 | Out-Null
      }
      { $_ -in 'uv' } {
        Invoke-Expression 'irm https://astral.sh/uv/install.ps1 | iex' 2>&1 | Out-Null
      }
      { $_ -in 'pip', 'pip3', 'python' } {
        Invoke-Expression 'python -m ensurepip --upgrade 2>&1 | Out-Null'
      }
      Default { }
    }
  } catch { }

  Update-SessionPath
  return (Test-Cli $mgr)
}

function Test-IsAdmin {
  try {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Get-CategoryLabel ([string]$category) {
  switch ($category) {
    'shared' { return 'Shared Tools' }
    'zeus'   { return 'Zeus -- GitOps' }
    'horus'  { return 'Horus -- IaC' }
    Default   { return $category }
  }
}

# --- Commands ---
function Invoke-Check {
  param([string]$Filter = 'all')

  Write-Host 'DevOps Plugin -- Tool Status' -ForegroundColor White
  Write-Host '============================'

  $currentSection = ''
  foreach ($entry in $TOOLS) {
    $parts = $entry -split '\|', 7
    $name     = $parts[0]
    $category = $parts[1]
    $tier     = $parts[2]

    if ($Filter -ne 'all' -and $category -ne 'shared' -and $category -ne $Filter) { continue }

    $section = "$category ($tier)"
    if ($section -ne $currentSection) {
      $currentSection = $section
      $label = Get-CategoryLabel $category
      Write-Host ''
      Write-Host "$label ($tier)" -ForegroundColor White
      Write-Host ('-' * 45)
    }

    if (-not (Test-Tool $name)) {
      $cmd = Get-InstallCmd $entry
      if (-not $cmd) { $cmd = Get-InstallHint $entry }
      Write-Host '         recommendation: ' -NoNewline
      Write-Host $cmd -ForegroundColor Yellow
    }
  }

  Write-Host ''
  Write-Host 'Summary: ' -NoNewline
  Write-Host "$($script:TotalOk) installed" -ForegroundColor Green -NoNewline
  Write-Host ', ' -NoNewline
  Write-Host "$($script:TotalMissing) missing" -ForegroundColor Red

  if ($script:TotalMissing -gt 0) {
    Write-Host ''
    Write-Host 'To install missing tools:'
    Write-Host '  .\install-tools.ps1 install        # all' -ForegroundColor White
    Write-Host '  .\install-tools.ps1 install zeus   # GitOps only' -ForegroundColor White
    Write-Host '  .\install-tools.ps1 install horus  # IaC only' -ForegroundColor White
  }
}

function Invoke-Install {
  param([string]$Filter = 'all')

  Write-Host 'DevOps Plugin -- Installing Tools' -ForegroundColor White
  Write-Host '================================='

  # Pre-flight checks
  if (-not $script:PkgManager -and -not $script:Pip) {
    Write-Host 'No package manager found.' -ForegroundColor Red
    Write-Host 'Install winget:     https://aka.ms/getwinget'
    Write-Host 'Install Chocolatey: https://chocolatey.org/install'
    Write-Host 'Install Scoop:      https://scoop.sh'
    Write-Host 'Install uv:         https://docs.astral.sh/uv/'
    Write-Host 'Install pip:        python -m ensurepip --upgrade'
    exit 1
  }

  if (-not $script:PkgManager) {
    Write-Host 'Warning: No system package manager (winget/choco/scoop) found.' -ForegroundColor Yellow
    Write-Host 'Only Python-based tools (via uv/pip) will be installed.'
    Write-Host 'Install winget: https://aka.ms/getwinget'
    Write-Host ''
  }

  if (-not $script:Pip) {
    Write-Host 'Note: No Python installer (uv/pip) found yet -- uv will be bootstrapped automatically' -ForegroundColor Cyan
    Write-Host '      when a Python-based tool needs it (per-user, no admin).'
    Write-Host ''
  }

  $currentSection = ''
  $installed = 0
  $skipped   = 0
  $failed    = 0

  foreach ($entry in $TOOLS) {
    $parts = $entry -split '\|', 7
    $name     = $parts[0]
    $category = $parts[1]
    $tier     = $parts[2]

    if ($Filter -ne 'all' -and $category -ne 'shared' -and $category -ne $Filter) { continue }

    $section = "$category ($tier)"
    if ($section -ne $currentSection) {
      $currentSection = $section
      $label = Get-CategoryLabel $category
      Write-Host ''
      Write-Host "$label ($tier)" -ForegroundColor White
    }

    if (Test-Cli $name) {
      Write-Host '  [OK] ' -ForegroundColor Green -NoNewline
      Write-Host " $name (already installed)"
      $skipped++
      continue
    }

    $cmd = Get-InstallCmd $entry

    if (-not $cmd) {
      $hint = Get-InstallHint $entry
      Write-Host '  [SKIP] ' -ForegroundColor Yellow -NoNewline
      Write-Host " $name -- no installer available"
      Write-Host "          hint: $hint"
      $failed++
      continue
    }

    # Bootstrap the installer this command needs (go/scoop/choco/uv/pip) if missing.
    $mgr = ($cmd -split '\s+')[0]
    if (-not (Install-Manager $mgr)) {
      Write-Host '  [SKIP] ' -ForegroundColor Yellow -NoNewline
      Write-Host " $name -- could not bootstrap '$mgr'"
      Write-Host "          hint: $(Get-InstallHint $entry)"
      $failed++
      continue
    }

    Write-Host "  Installing " -NoNewline
    Write-Host $name -ForegroundColor White -NoNewline
    Write-Host " via: $cmd ... " -NoNewline

    $success = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      # Pre-reset to a non-zero sentinel so a stale value from a prior native
      # command in this session can't be mistaken for success.
      $global:LASTEXITCODE = 1
      try {
        Invoke-Expression "$cmd 2>&1 | Out-Null"
        if ($LASTEXITCODE -eq 0) {
          $success = $true
          break
        }
      } catch { }
      if ($attempt -lt 3) {
        Write-Host "retry $($attempt + 1)/3 ... " -NoNewline
        Start-Sleep -Seconds 1
      }
    }

    if ($success) {
      Write-Host 'OK' -ForegroundColor Green
      $installed++
    } else {
      Write-Host 'FAILED' -ForegroundColor Red -NoNewline
      Write-Host ' (3 attempts)'
      $failed++
    }
  }

  Write-Host ''
  Write-Host 'Done: ' -NoNewline
  Write-Host "$installed installed" -ForegroundColor Green -NoNewline
  Write-Host ", $skipped already present" -NoNewline
  if ($failed -gt 0) {
    Write-Host ', ' -NoNewline
    Write-Host "$failed failed" -ForegroundColor Red -NoNewline
  }
  Write-Host ''

  if ($installed -gt 0) {
    # Persist ~\go\bin and ~\.local\bin to the User PATH so a new terminal finds
    # go-/uv-installed tools (their installers don't add these dirs themselves).
    Save-PerUserBinPath
    Write-Host ''
    Write-Host '  +--------------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '  |  IMPORTANT: open a NEW terminal before verifying.            |' -ForegroundColor Yellow
    Write-Host '  |  Windows updates PATH for new processes only -- tools just   |' -ForegroundColor Yellow
    Write-Host '  |  installed are NOT callable in this session yet. go\bin and  |' -ForegroundColor Yellow
    Write-Host '  |  .local\bin were added to your User PATH for next time.      |' -ForegroundColor Yellow
    Write-Host '  +--------------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Close this window, open a fresh PowerShell, then run:'
  } else {
    Write-Host ''
    Write-Host 'Run ' -NoNewline
  }
  Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install-tools.ps1 check' -ForegroundColor White -NoNewline
  Write-Host ' to verify.'
}

function Show-ToolsHelp {
  Write-Host ''
  Write-Host 'DevOps AI Skill Pack -- Tool Installer (Windows)' -ForegroundColor White
  Write-Host '================================================'
  Write-Host ''
  Write-Host 'Usage:' -ForegroundColor White
  Write-Host '  powershell -ExecutionPolicy Bypass -File scripts\install-tools.ps1 [command] [agent]'
  Write-Host ''
  Write-Host 'Commands:' -ForegroundColor White
  Write-Host '  (none)     Interactive: check, then offer to install missing tools'
  Write-Host '  check      Show tool status only (no admin needed; never installs)'
  Write-Host '  install    Install all missing tools'
  Write-Host '  help       Show this help'
  Write-Host ''
  Write-Host 'Agent filter (optional 2nd arg):' -ForegroundColor White
  Write-Host '  all        Shared + Zeus + Horus tools (default)'
  Write-Host '  zeus       Shared + Zeus (GitOps) tools'
  Write-Host '  horus      Shared + Horus (IaC) tools'
  Write-Host ''
  Write-Host 'Examples:' -ForegroundColor White
  Write-Host '  ...install-tools.ps1 check'
  Write-Host '  ...install-tools.ps1 install zeus'
  Write-Host ''
  Write-Host 'Auto-bootstrap:' -ForegroundColor White
  Write-Host '  winget is preferred. When a tool needs Go / scoop / uv / pip and it is'
  Write-Host '  missing, the installer bootstraps it automatically (per-user, no admin;'
  Write-Host '  choco-only tools need an elevated shell). go/uv-installed tools land in'
  Write-Host '  %USERPROFILE%\go\bin and %USERPROFILE%\.local\bin -- these are added to'
  Write-Host '  your User PATH so a NEW terminal can find them.'
  Write-Host ''
  Write-Host 'After install: open a fresh terminal, then run `...install-tools.ps1 check`.' -ForegroundColor Yellow
  Write-Host ''
}

function Invoke-Interactive {
  param([string]$Filter = 'all')

  Invoke-Check -Filter $Filter

  if ($script:TotalMissing -gt 0) {
    Write-Host ''
    $answer = Read-Host 'Install missing tools now? [y/N]'
    if ($answer -match '^[Yy]') {
      $script:TotalOk = 0
      $script:TotalMissing = 0
      Invoke-Install -Filter $Filter
    }
  }
}

# --- Main ---
# Top-level guard: any unexpected terminating error surfaces as a clean message +
# non-zero exit rather than a raw stack trace. Per-tool install failures are
# already handled (and retried) inside Invoke-Install, so they do not reach here.
try {
  Test-PlatformInfo

  switch ($Command) {
    'check'   { Invoke-Check       -Filter $Filter }
    'install' { Invoke-Install     -Filter $Filter }
    { $_ -in 'help', '-h', '--help', '/?', '-help' } { Show-ToolsHelp }
    Default    {
      if ($Command) {
        # Treat single positional arg as filter for interactive mode
        Invoke-Interactive -Filter $Command
      } else {
        Invoke-Interactive -Filter $Filter
      }
    }
  }
} catch {
  Write-Host ''
  Write-Host '[ERROR] ' -ForegroundColor Red -NoNewline
  Write-Host "Tool installer failed: $($_.Exception.Message)"
  if ($_.InvocationInfo -and $_.InvocationInfo.ScriptLineNumber) {
    Write-Host ("    at line {0}" -f $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkGray
  }
  exit 1
}
