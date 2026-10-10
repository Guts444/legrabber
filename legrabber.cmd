@echo off
setlocal

rem Prefer PowerShell 7, fall back to the Windows PowerShell that ships with Windows.
set "PSEXE=pwsh"
where pwsh >nul 2>nul || set "PSEXE=powershell"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0legrabber.ps1" %*
set "RC=%ERRORLEVEL%"

rem Keep startup errors visible when double-clicked; URL/option calls never pause.
if not "%RC%"=="0" if "%~1"=="" pause

exit /b %RC%
