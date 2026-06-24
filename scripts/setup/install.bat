@echo off
REM ============================================================================
REM DevOps AI Skill Pack -- Windows One-Click Launcher
REM ============================================================================
REM Double-click from File Explorer or run from cmd / PowerShell.
REM Resolves PowerShell host (prefers pwsh.exe, falls back to powershell.exe),
REM then dispatches to scripts\install-global.ps1 / install-tools.ps1.
REM ============================================================================

setlocal

REM Prefer pwsh.exe (PowerShell 7+) if present, else fall back to powershell.exe (5.1).
where /q pwsh.exe
if %ERRORLEVEL% EQU 0 (
  set "PS=pwsh.exe"
) else (
  set "PS=powershell.exe"
)

REM Fail fast if no PowerShell host is available at all.
where /q %PS%
if errorlevel 1 (
  echo.
  echo [ERROR] PowerShell not found on PATH ^(looked for pwsh.exe / powershell.exe^).
  echo         Install PowerShell 7+ from https://aka.ms/powershell, or ensure
  echo         Windows PowerShell 5.1 is available, then re-run this launcher.
  goto end
)

REM Verify the installer scripts exist next to this launcher (full clone check).
set "GLOBAL_PS=%~dp0..\install-global.ps1"
set "TOOLS_PS=%~dp0..\install-tools.ps1"
if not exist "%GLOBAL_PS%" (
  echo.
  echo [ERROR] Cannot find install-global.ps1 at "%GLOBAL_PS%".
  echo         Run this from a complete clone of the devops-ai-skill repo.
  goto end
)
if not exist "%TOOLS_PS%" (
  echo.
  echo [ERROR] Cannot find install-tools.ps1 at "%TOOLS_PS%".
  echo         Run this from a complete clone of the devops-ai-skill repo.
  goto end
)

echo.
echo ===============================================
echo  DevOps AI Skill Pack -- Windows Install
echo ===============================================
echo.
echo  [1] Install skills (recommended) -- agents, skills, pipelines
echo  [2] Install tools                -- terraform, helm, kustomize, etc.
echo  [3] Both                         -- skills, then tools
echo  [S] Show install status
echo  [U] Uninstall (remove all global installs)
echo  [Q] Quit
echo.
set /p CHOICE=Choose:

if /i "%CHOICE%"=="1" goto skills
if /i "%CHOICE%"=="2" goto tools
if /i "%CHOICE%"=="3" goto both
if /i "%CHOICE%"=="S" goto status
if /i "%CHOICE%"=="U" goto uninstall
if /i "%CHOICE%"=="Q" goto end

echo Invalid choice: %CHOICE%
goto end

:skills
%PS% -ExecutionPolicy Bypass -NoProfile -File "%GLOBAL_PS%"
if errorlevel 1 (
  echo.
  echo [ERROR] Skill install failed. See the message above.
)
goto end

:tools
%PS% -ExecutionPolicy Bypass -NoProfile -File "%TOOLS_PS%" install
if errorlevel 1 (
  echo.
  echo [ERROR] Tool install failed. See the message above.
)
goto end

:both
%PS% -ExecutionPolicy Bypass -NoProfile -File "%GLOBAL_PS%"
if errorlevel 1 (
  echo.
  echo [ERROR] Skill install failed -- skipping tool install.
  goto end
)
%PS% -ExecutionPolicy Bypass -NoProfile -File "%TOOLS_PS%" install
if errorlevel 1 (
  echo.
  echo [ERROR] Tool install failed. See the message above.
)
goto end

:status
%PS% -ExecutionPolicy Bypass -NoProfile -File "%GLOBAL_PS%" -Status
goto end

:uninstall
%PS% -ExecutionPolicy Bypass -NoProfile -File "%GLOBAL_PS%" -Uninstall
goto end

:end
echo.
pause
endlocal
