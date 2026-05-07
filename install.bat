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
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1"
goto end

:tools
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-tools.ps1" install
goto end

:both
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1"
if errorlevel 1 (
  echo.
  echo Skill install failed -- skipping tool install.
  goto end
)
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-tools.ps1" install
goto end

:status
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1" -Status
goto end

:uninstall
%PS% -ExecutionPolicy Bypass -NoProfile -File "%~dp0scripts\install-global.ps1" -Uninstall
goto end

:end
echo.
pause
endlocal
