@echo off
setlocal

rem Rebuilds dist\legrabber.zip. Dependencies and saved media are not shipped.
rem Pass -Yes to skip the final pause when building from a terminal or script.
set "LEGRABBER_DIR=%~dp0."
set "PSEXE=pwsh"
where pwsh >nul 2>nul || set "PSEXE=powershell"

"%PSEXE%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $d = $env:LEGRABBER_DIR; $f = @('legrabber.ps1','legrabber.cmd','install.cmd','README.md') | ForEach-Object { Join-Path $d $_ }; $dist = Join-Path $d 'dist'; New-Item -ItemType Directory -Force -Path $dist | Out-Null; $out = Join-Path $dist 'legrabber.zip'; $tmp = Join-Path $dist ('legrabber-' + [guid]::NewGuid().ToString('N') + '.zip'); try { Compress-Archive -LiteralPath $f -DestinationPath $tmp; Move-Item -LiteralPath $tmp -Destination $out -Force; $kb = [math]::Round((Get-Item -LiteralPath $out).Length / 1KB); Write-Host ('Built ' + $out + ' (' + $kb + ' KB)') } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }"
set "RC=%ERRORLEVEL%"

echo.
if /i not "%~1"=="-Yes" pause
exit /b %RC%
