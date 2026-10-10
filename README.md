# legrabber

A small Windows command-line downloader: paste a link or search YouTube,
choose video or audio, and save the file. legrabber puts interactive menus,
playlist folders and dependency setup around [yt-dlp](https://github.com/yt-dlp/yt-dlp).
It uses [ffmpeg](https://ffmpeg.org/) for merging, conversion and tagging.

[Download the latest release](https://github.com/Guts444/legrabber/releases/latest)
\u00b7 [Changelog](https://github.com/Guts444/legrabber/blob/main/CHANGELOG.md)
\u00b7 [Report an issue](https://github.com/Guts444/legrabber/issues)

- **X / Twitter** — best quality available
- **Instagram Reels** — best quality available
- **YouTube** — asks which resolution you want, or takes audio only
- **Spotify tracks** — reads the song and artist, then lets you choose a YouTube match
- **Other sites** — handled by yt-dlp when its extractor supports the URL

## Install

1. Download **`legrabber-v1.0.0.zip`** from the
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
`install.cmd` and `README.md` in your existing folder with the new release's
files. Keep `bin\` and `downloads\`. `legrabber -Update` updates **yt-dlp**,
not legrabber itself.

## Quick examples

```powershell
legrabber                                      # stay open for links and searches
legrabber "artist song title"                   # choose from up to 10 YouTube results
legrabber "https://youtu.be/dQw4w9WgXcQ"         # choose video quality or audio
legrabber "https://youtu.be/dQw4w9WgXcQ" -Audio  # original audio, no re-encoding
legrabber "artist song title" -Audio -Yes -Pick 1
```

## Use

Type `legrabber` — it stays open and takes links or search phrases:

```
  Paste a video address or search YouTube (q to quit): https://x.com/user/status/1234567890
  ...
  Paste a video address or search YouTube (q to quit): q
```

Or double-click `legrabber.cmd`, or pass the link straight in. Quote URLs,
especially those containing `&`, so the shell passes the complete address:

```powershell
legrabber "https://youtu.be/dQw4w9WgXcQ"
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

No Spotify account or API key is needed. Localized `open.spotify.com/intl-.../track/`
links, embed track links and `spotify:track:<id>` desktop URIs work too. Albums,
playlists and shortened share links are not supported; use a full track link.
If Spotify cannot provide the metadata, search the song title and artist instead.

Normal options carry through to the selected YouTube result. For example,
`-Audio` skips the format menu, and `-List` only lists the selected video's
formats. Unattended use requires an explicit match index:

```powershell
legrabber "https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf" -Audio -Yes -Pick 2
```

### YouTube asks what you want first

```
  Me at the zoo
  jawed  -  0:19

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
  Playlist: Uploads from Blender Studio        item 7 of 62
  legrabber  08 - Painterly Shadows.m4a   -   2.4MiB/s   ETA 00:03
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

## Options

| Option | What it does |
| --- | --- |
| `-Search` | Force YouTube search for the supplied phrase, even if it looks like a domain |
| `-Pick 2` | Select result 2 (1-10); applies to searches/Spotify matches and is required with `-Yes` |
| `-Quality 1080` | Skip the menu. `2160`/`1440`/`1080`/`720`/`480`/`360`/`best`, or a raw yt-dlp selector |
| `-Audio` | Audio only; `-Quality` applies to video and is ignored here |
| `-AudioFormat mp3` | `original` (default, no re-encode), `mp3`, `m4a`, `wav`, `flac`, `opus` |
| `-Out <path>` | Save somewhere instead of `.\downloads` |
| `-Browser chrome` | Use your browser's cookies for posts your account can access |
| `-List` | Show available formats and exit, on any supported site |
| `-Subs` | Download and embed English subtitles; requires ffmpeg |
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
`-Browser chrome` may help when your browser account can access the item.

**A site asks for login.** Browser cookies can help for posts your account can
access. Close the browser if yt-dlp cannot read its cookie database, then run:

```powershell
legrabber "https://example.com/video" -Browser chrome
```

**`HTTP Error 403: Forbidden` on YouTube.** The script retries once because a
refreshed media token may help. If it still fails, try `-Update`, a different
format, or browser cookies. These do not guarantee access to every video.

A different `-Client` exposes different formats and can cause "Requested
format is not available". Use it only when you know which client you need.

For YouTube's "Sign in to confirm you're not a bot" message, cookies from a
signed-in browser may help; YouTube can still restrict the request.

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
52 checks per engine without network requests, media downloads or ffmpeg.
See [tests/README.md](https://github.com/Guts444/legrabber/blob/main/tests/README.md)
for what it covers. GitHub Actions runs
the same checks on Windows PowerShell 5.1 and PowerShell 7.

`pack.cmd` rebuilds `dist\legrabber.zip` — that's the file to hand out. It's
small because yt-dlp and ffmpeg are fetched on the recipient's machine rather
than shipped. The zip contains only the script, launcher, setup launcher,
and README; it excludes dependencies and downloaded media.

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
pack.cmd         rebuild dist\legrabber.zip for sharing (developer checkout)
bin\             yt-dlp.exe and ffmpeg\, fetched on first run
downloads\       your videos
```

## Note

Quality picks prefer H.264/MP4 for broad player and editor compatibility where
those streams are available. Higher resolutions may fall back to VP9/AV1 in a
`.webm` container. Respect copyright and each site's terms when downloading.
