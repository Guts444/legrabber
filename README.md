# legrabber

A small Windows command-line downloader: paste a link or search YouTube,
choose video or audio, and save the file. legrabber puts interactive menus,
playlist folders and dependency setup around [yt-dlp](https://github.com/yt-dlp/yt-dlp).
It uses [ffmpeg](https://ffmpeg.org/) for merging, conversion and tagging.

[Download the latest release](https://github.com/Guts444/legrabber/releases/latest)
| [Changelog](https://github.com/Guts444/legrabber/blob/main/CHANGELOG.md)
| [Report an issue](https://github.com/Guts444/legrabber/issues)

- **X / Twitter** — best quality available
- **Instagram Reels** — best quality available
- **YouTube** — asks which resolution you want, or takes audio only
- **Spotify tracks** — reads the song and artist, then lets you choose a YouTube match
- **Other sites** — handled by yt-dlp when its extractor supports the URL

## Install

1. Download **`legrabber-v1.0.2.zip`** from the
   [latest release](https://github.com/Guts444/legrabber/releases/latest).
   The release ZIP contains everything needed to start; GitHub's automatic
   source archives are intended for development.
2. Extract the ZIP somewhere you can write to — your user folder, Desktop,
   or `C:\Tools` are all fine. **Not** `Program Files`.
3. Double-click **`install.cmd`**. It adds the folder to your user PATH and
   fetches yt-dlp. No admin rights needed.
4. Open a **new** terminal and type `legrabber`.

You can also double-click `legrabber.cmd` directly without adding it to PATH.
Keep the extracted folder in place: it holds the program, dependencies and
default downloads. Windows may flag downloaded scripts; review the source
before allowing them to run.

Targets Windows 10/11 x64 and works with the included Windows PowerShell 5.1;
PowerShell 7 is used automatically if installed. ffmpeg is optional and offered on first run.
Without it, video must already include audio in one file, so available
resolutions depend on the source. Original audio can be saved without tags;
audio conversion and embedded subtitles require ffmpeg.

First dependency downloads and managed yt-dlp updates are checked against the
publisher's SHA-256 checksums before installation. yt-dlp resolves a specific
release so the executable and checksum list come from the same version; the
ffmpeg archive is checked against its published checksum too.

To upgrade legrabber, close it and replace `legrabber.ps1`, `legrabber.cmd`,
`install.cmd`, `README.md` and `LICENSE` in your existing folder with the new release's
files. Keep `bin\` and `downloads\`. `legrabber -Update` updates **yt-dlp**,
not legrabber itself.

## Quick examples

```powershell
legrabber                                                  # stay open for links and searches
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw"    # choose video quality or audio
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw" -Audio
legrabber "https://x.com/user/status/2108405185542270976"  # best quality, no menu
legrabber "your search phrase" -Audio -Yes -Pick 1         # first YouTube match, audio only
legrabber -Batch links.txt -Archive                        # every link in the file, skipping repeats
```

Addresses only work when they point at something you are allowed to download.

## Use

Type `legrabber` — it stays open and takes links or search phrases:

```
  Paste a video address or search YouTube (q to quit): https://x.com/user/status/2108405185542270976
  ...
  Paste a video address or search YouTube (q to quit): q
```

Or double-click `legrabber.cmd`, or pass the link straight in. Quote URLs,
especially those containing `&`, so the shell passes the complete address:

```powershell
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PL123"
```

### Search YouTube

Enter a title, artist, or other search phrase instead of a link. legrabber
shows up to ten YouTube results in search order, with titles, channels and
durations when available. Choose a number, then use the usual video/audio
menu. `q` cancels the search and returns to the main prompt.

You can also search from the command line:

```powershell
legrabber "50 cent many men"
legrabber "50 cent many men" -Audio
```

Explicit links and bare domains still download directly. Use `-Search` to
force search if your phrase looks like a domain, such as `Mr.Brightside`:

```powershell
legrabber "Mr.Brightside" -Search
```

`-Pick 2` selects result 2 without the results prompt. With `-Yes`, a search
requires `-Pick` so it never silently downloads an unintended first match:

```powershell
legrabber "50 cent many men" -Audio -Yes -Pick 1
```

Search reads result metadata only; it downloads only the selected video.
`-List` lists formats for the selected result, and normal output/conversion
options work as they do with a pasted link. No API key or extra dependency.

### Spotify track links

Paste a full Spotify track link just like any other address:

```powershell
legrabber "https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf"
```

legrabber reads the public song title and artists, searches YouTube, and shows
up to ten matches. Choose the version you want, then use the normal video/audio
menu. The file and its tags come from the chosen YouTube video, and it lands
in `downloads\YouTube\` by default. Spotify audio is not downloaded.

No Spotify account or API key is needed. Full track links, localized
`open.spotify.com/intl-.../track/` links, embed track links and
`spotify:track:<id>` desktop URIs work too. Albums, playlists and shortened
share links are not supported; use a full track link.
If Spotify cannot provide the metadata, search the song title and artist instead.

Normal options carry through to the selected YouTube result. For example,
`-Audio` skips the format menu, and `-List` only lists the selected video's
formats. Unattended use requires an explicit match index:

```powershell
legrabber "https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf" -Audio -Yes -Pick 2
```

### YouTube asks what you want first

```
  Example recording
  Example creator  -  0:19

  Video or audio?  1 = video, 2 = audio  (q to quit): 2

    1) AAC ~130 kbps             302 KB
    2) Opus ~107 kbps          249.4 KB
    3) MP3 (converted)               ?
    4) M4A (converted)               ?
```

You only see the one list you asked for, so a music link never makes you read
past a wall of video resolutions. `b` takes the best of whichever you picked.
Original audio keeps the source codec without re-encoding. With ffmpeg, it is
extracted or remuxed losslessly and tagged; the container can change, for
example from WebM to Opus. Without ffmpeg, a separate audio stream is saved
as served without tags. Cover art is embedded for supported converted formats
(MP3, M4A, FLAC, Opus); original audio and WAV omit it.

### Playlists

Paste a playlist link — YouTube Music ones work the same — and the questions
are asked once, then every item downloads in order, with a bar for the current
item and a bar for your place in the playlist:

```
  Playlist: My recordings                     item 7 of 62
  legrabber  08 - Example recording.m4a   -   2.4MiB/s   ETA 00:03
```

They land in `.\downloads\YouTube\<playlist name>\`, numbered in playlist
order, including when using `-Yes`, `-Audio`, or `-Quality`. With `-Out`, the
playlist subfolder is created inside that directory. For a
`watch?v=...&list=...` link the single video wins unless you pass `-Playlist`.

By default, files land in `downloads\<Platform>\` beside the script, regardless
of your terminal's current directory. Single downloads with `-Out` go directly
into the chosen directory.

Passing a URL or search phrase as an argument does that one download and exits. The exit code
is 0 on success and nonzero on failure, including a playlist with failed
items. The launcher never pauses when given arguments.

`-Yes` skips menus and optional ffmpeg setup; it selects the best available
video unless you pass `-Audio` or `-Quality`. It still fetches yt-dlp if needed.

### Batch runs

Point `-Batch` at a text file with one link or search phrase per line. Blank
lines and `#` comments are skipped, so the file can be annotated:

```
# music
https://www.youtube.com/watch?v=jNQXAC9IVRw
https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf

# video
https://x.com/user/status/2108405185542270976
```

```powershell
legrabber -Batch links.txt -Archive -Out D:\Media
```

Menus are off during a batch run, so it never stops to ask. A batch containing
search phrases needs `-Pick 1-10`, because there is nothing to prompt with.
`-Batch -` reads the list from stdin instead of a file:

```powershell
Get-Content links.txt | legrabber -Batch - -Audio
```

Every item is attempted even when one fails, the finished files are listed as
they arrive, and the summary reports how many landed and how many did not. The
run exits nonzero if any item failed.

### Skipping what you already have

`-Archive` records every finished download in `.legrabber-archive.txt` beside
the script and skips anything already in it:

```powershell
legrabber -Batch links.txt -Archive
```

That is what makes re-running a batch or a channel cheap: the second run only
touches what is new. Skipped items count as success and are reported as
`Already grabbed`, so an archive-only run exits 0.

### Cookies and sites that want a login

`-Browser` uses your own browser session for content your account can reach.
Chrome keeps its cookie database locked while it runs, which makes
`-Browser chrome` fail on some systems; export cookies instead and use
`-Cookies`:

```powershell
legrabber "https://www.instagram.com/reel/Cx1y2z3A/" -Browser chrome
legrabber "https://www.instagram.com/reel/Cx1y2z3A/" -Cookies .\cookies.txt
```

A `cookies.txt` in Netscape format (the export format every cookie extension
uses) also works when the session lives on another machine. Account access is
not the same thing as permission to download.

### Subtitles, chapters and metadata

```powershell
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw" -Subs -SubLangs "pt.*,en.*"
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw" -Quality 1080 -Tags -Chapters -Thumb
```

`-Subs` downloads and embeds subtitles; `-SubLangs` takes a yt-dlp language
selector (`en.*,en` is the default, `all` takes everything the source offers).
`-Tags`, `-Chapters` and `-Thumb` embed metadata, chapter markers and cover art
into the video and all need ffmpeg. Converted audio already carries tags and
cover art, so these three apply to video downloads.

### When a site fights back

Retries, throttling and timeouts are exposed because the defaults are not
always the polite thing to do:

```powershell
legrabber -Batch links.txt -Retries 25 -Sleep 5 -LimitRate 2M
legrabber "https://www.youtube.com/watch?v=jNQXAC9IVRw" -SleepRequests 2 -SocketTimeout 45
```

`-Sleep` waits before each download and `-SleepRequests` between playlist
items; both are the cure for bot checks and 429s. `-LimitRate "2M"` caps
bandwidth so a big batch does not saturate the line. `-KeepMtime`
keeps the source's own file timestamp instead of the default local one.

## Options

| Option | What it does |
| --- | --- |
| `-Search` | Force YouTube search for the supplied phrase, even if it looks like a domain |
| `-Pick 2` | Select result 2 (1-10); applies to searches/Spotify matches and is required with `-Yes` |
| `-Quality 1080` | Skip the menu. `2160`/`1440`/`1080`/`720`/`480`/`360`/`best`, or a raw yt-dlp selector |
| `-Audio` | Audio only; `-Quality` applies to video and is ignored here |
| `-AudioFormat mp3` | `original` (default, no re-encode), `mp3`, `m4a`, `wav`, `flac`, `opus` |
| `-Out <path>` | Save somewhere instead of `.\downloads` |
| `-Batch <file>` | One link or search phrase per line; `-` reads stdin |
| `-Archive` | Skip anything already downloaded; bare flag keeps its file beside the script |
| `-Browser chrome` | Use your browser's cookies for posts your account can access |
| `-Cookies <file>` | Use a Netscape-format cookies.txt instead of a live browser profile |
| `-Subs` | Download and embed subtitles; requires ffmpeg |
| `-SubLangs "pt.*,en.*"` | Subtitle language selector; default `en.*,en` |
| `-Tags` | Embed metadata into the video; requires ffmpeg |
| `-Chapters` | Embed chapter markers; requires ffmpeg |
| `-Thumb` | Embed cover art into the video; requires ffmpeg |
| `-Retries 25` | Retry a failing download this many times (default 10) |
| `-FragmentRetries 5` | Retry a failing fragment this many times (default 3) |
| `-LimitRate "2M"` | Cap the download rate; unset means unlimited |
| `-Sleep 5` | Wait this many seconds before each download |
| `-SleepRequests 2` | Wait this many seconds between playlist items |
| `-SocketTimeout 45` | Give up on a stalled connection after this many seconds (default 20) |
| `-KeepMtime` | Keep the source timestamp instead of the download time |
| `-List` | Show available formats and exit, on any supported site |
| `-Playlist` | YouTube: take the whole playlist from a `watch?v=…&list=…` link |
| `-Yes` | Never prompt |
| `-Client <name>` | YouTube only: force a player client |
| `-Update` | Update the bundled yt-dlp |
| `-Install` | Re-run setup (PATH + dependencies) |
| `-Uninstall` | Take this folder off your PATH (deletes nothing) |

## When it fails

**A playlist item fails.** yt-dlp reports each error and continues with the
remaining items. Files already saved remain available, but the run exits with
a nonzero code if any item fails. Errors can involve unavailable items, login
requirements, network failures, or post-processing; check the printed message.

**A site asks for login.** `-Browser` and `-Cookies` give yt-dlp your own
session, which is what private and age-gated posts need:

```powershell
legrabber "https://x.com/user/status/2108405185542270976" -Browser firefox
```

If a browser source fails, export cookies to a file and use `-Cookies`.

**The source denies access or restricts downloads.** legrabber drives yt-dlp
extractors; if the source serves the media to yt-dlp, it downloads. If it does
not — DRM streams, paid tiers, deleted items — the extractor fails and the
error is printed. Sites that require new handling need a yt-dlp update.

`-Update` is worth trying whenever a site starts failing; yt-dlp extractors
change as sites change.

## Development and packaging

Clone the repository, then run the regression suite on Windows:

```powershell
git clone https://github.com/Guts444/legrabber.git
cd legrabber
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\regression.ps1
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\regression.ps1
.\pack.cmd -Yes
```

PowerShell 7 is needed only for the second test command. The suite runs
64 checks per engine without network requests, media downloads or ffmpeg.
See [tests/README.md](https://github.com/Guts444/legrabber/blob/main/tests/README.md)
for what it covers. GitHub Actions runs
the same checks on Windows PowerShell 5.1 and PowerShell 7.

`pack.cmd` rebuilds `dist\legrabber.zip` — that's the file to hand out. It's
small because yt-dlp and ffmpeg are fetched on the recipient's machine rather
than shipped. The zip contains only the script, launcher, setup launcher,
README and MIT license; it excludes dependencies and downloaded media.

Whoever receives it unzips it, runs `install.cmd`, opens a new terminal and
types `legrabber`. No admin rights are needed. Setup adds this directory to
the user PATH in the Windows registry; downloaded dependencies stay in `bin\`.

For a build without the final pause, use `pack.cmd -Yes`. The existing zip is
replaced only after the new archive builds successfully. `install.cmd -Yes`
runs setup without prompts or a final pause, fetching yt-dlp but skipping
optional ffmpeg if absent. `legrabber -Install -Yes` does the same setup.

## Removing it

```powershell
legrabber -Uninstall
```

That takes the folder back off your PATH and deletes nothing. Then delete the
folder itself — `downloads\` holds your videos, so move them out first if you
want to keep them. (`install.cmd` is safe to run again any time; it won't add
the folder twice.)

## Files

```
legrabber.ps1    the script
legrabber.cmd    launcher (double-click or call from any shell)
install.cmd      one-time setup: PATH + dependencies
LICENSE          MIT license for legrabber
pack.cmd         rebuild dist\legrabber.zip for sharing (developer checkout)
bin\             yt-dlp.exe and ffmpeg\, fetched on first run
downloads\       your videos
.legrabber-archive.txt   created by -Archive; safe to delete to forget everything
```

## Note

Quality picks prefer H.264/MP4 for broad player and editor compatibility where
those streams are available. Higher resolutions may fall back to VP9/AV1 in a
`.webm` container.

## License

legrabber is licensed under the [MIT License](https://github.com/Guts444/legrabber/blob/main/LICENSE).
Download only what you have the right to download. That license covers
legrabber's code and documentation; it does not grant rights to downloaded
content. yt-dlp, ffmpeg and other third-party components retain their own
licenses.

Service and tool names identify compatibility and dependencies only.
legrabber is an independent project with no affiliation or endorsement from
the services mentioned here.
