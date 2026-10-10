# Regression checks

Run from the project folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\regression.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\regression.ps1
```

The suite loads function declarations from the script AST without running the
interactive entry point. It uses a native `.cmd` fixture to exercise real stdout,
stderr, and exit-code behavior on each PowerShell engine. Scoped mocks inspect
command construction for format listing, playlists, and audio processing.

It makes no network requests, downloads no media, and needs no ffmpeg. Each run
uses its own temporary directory and removes it afterward. Live site acceptance
still needs separate testing because these checks cannot detect extractor changes
or remote login restrictions.
