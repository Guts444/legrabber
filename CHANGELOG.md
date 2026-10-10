# Changelog

## v1.0.1 - 2026-10-10

- License legrabber's code and documentation under MIT.
- Include the license in the release ZIP.
- Replace real media links, song titles and creator names in the README
  with neutral placeholders.
- Clarify permitted use, independent service references and the distinction
  between the software license and rights to downloaded content.

## v1.0.0 - 2026-10-10

First public release.

- Download video and audio through yt-dlp with interactive format selection.
- Search YouTube and choose from up to ten numbered results.
- Resolve Spotify track titles and artists to selectable YouTube matches.
- Save YouTube playlists in named, numbered folders.
- Keep original audio without re-encoding, or convert with ffmpeg.
- Install dependencies with SHA-256 verification and add the program to the
  current user's PATH without administrator rights.
- Support Windows PowerShell 5.1 and PowerShell 7, including native error
  handling, clear missing-ffmpeg diagnostics and unattended exit codes.
- Include 52 regression checks per PowerShell engine.

Spotify support uses public track metadata; the chosen media comes from
YouTube. Albums, Spotify playlists and shortened Spotify links are not
supported. Site availability and login requirements depend on yt-dlp and
the source site.
