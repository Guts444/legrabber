# Changelog

## v1.0.2 - 2026-10-10

- Batch mode: `-Batch <file>` takes one link or search phrase per line, or
  `-Batch -` from stdin. Menus are off, every item is attempted, results are
  reported per item, and the run exits nonzero if any item failed.
- `-Archive` remembers finished downloads in `.legrabber-archive.txt` beside
  the script and skips them on later runs. Archived items are detected before
  any network work, so a re-run reports `Already grabbed` and exits 0 rather
  than looking like a download that produced nothing.
- `-Cookies <file>` reads a Netscape-format cookies.txt, for browser profiles
  that hold their cookie database open (Chrome while it runs) and for sessions
  exported from another machine.
- `-SubLangs` chooses subtitle languages instead of the fixed English set.
- `-Tags`, `-Chapters` and `-Thumb` embed metadata, chapter markers and cover
  art into video downloads.
- Retry and throttling options: `-Retries`, `-FragmentRetries`, `-LimitRate`,
  `-Sleep`, `-SleepRequests`, `-SocketTimeout` and `-KeepMtime`.
- Downloads default to a local timestamp (`--no-mtime`); `-KeepMtime` restores
  the source's own timestamp.
- Documentation uses real, copy-pasteable examples again, and the permitted-use
  section is down to the one line that matters.
- 64 regression checks per engine, up from 52.

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
