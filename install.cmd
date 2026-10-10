@echo off
setlocal

echo.
echo   legrabber setup
echo   ---------------

rem Prefer PowerShell 7, fall back to the Windows PowerShell that ships with Windows.
set "PSEXE=pwsh"
where pwsh >nul 2>nul || set "PSEXE=powershell"

set "SETUPARGS="
if /i "%~1"=="-Yes" set "SETUPARGS=-Yes"
"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0legrabber.ps1" -Install %SETUPARGS%
set "RC=%ERRORLEVEL%"

echo.
if /i not "%~1"=="-Yes" pause
exit /b %RC%
