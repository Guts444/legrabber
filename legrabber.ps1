#Requires -Version 5.1
<#
    legrabber - paste a video URL or search YouTube, get the file.

      X / Twitter ........ best quality available
      Instagram Reels .... best quality available
      YouTube ............ interactive picker (video quality / audio-only)
      anything else ...... whatever yt-dlp supports, best quality

    Run it with no arguments and it stays open, taking one link after another.
    Pass a URL on the command line and it downloads that one file and exits.

    Backend is yt-dlp (auto-fetched into .\bin on first run). ffmpeg is needed
    for merging high-res video with audio and for any audio conversion; if it
    is missing you will be offered a one-time download.

    Examples
      legrabber                                        # prompts, stays open
      legrabber https://x.com/user/status/123
      legrabber https://youtu.be/dQw4w9WgXcQ           # shows the quality menu
      legrabber <url> -Quality 1080 -Yes               # no menu
      legrabber <url> -Audio -AudioFormat mp3          # rip the audio
      legrabber <url> -List                            # show formats, no download
      legrabber <ig-url> -Browser chrome               # private reels need login
      legrabber -Update                                # update yt-dlp
#>
[CmdletBinding()]
param(
    # The video address or YouTube search phrase. Omit for the stay-open prompt.
    [Parameter(Position = 0)]
    [string]$Url,

    # Force YouTube search, even when the phrase looks like a web address.
    [switch]$Search,

    # Pick this search result without prompting (1-10). Required for -Yes search.
    [ValidateRange(1, 10)]
    [int]$Pick,

    # Where to save. Defaults to .\downloads\<Platform> next to this script.
    [Alias('Output')]
    [string]$Out,

    # Skip the menu: 2160 / 1440 / 1080 / 720 / 480 / 360 / best, or a raw
    # yt-dlp format selector such as "bv*[height<=1000]+ba".
    [string]$Quality,

    # Grab audio only.
    [switch]$Audio,

    # Applies when grabbing audio. 'original' keeps the file as served (no
    # re-encode); anything else converts via ffmpeg.
    [ValidateSet('original', 'mp3', 'm4a', 'wav', 'flac', 'opus')]
    [string]$AudioFormat = 'original',

    # Read cookies from this browser. Needed for private/login-walled posts.
    [ValidateSet('chrome', 'firefox', 'edge', 'brave', 'chromium', 'opera', 'vivaldi', 'whale', 'safari')]
    [string]$Browser,

    # YouTube only, last resort: force a player client (tv_simply, web_safari,
    # mweb, ...) when the default one keeps getting refused.
    [string]$Client,

    # YouTube: download the whole playlist instead of the single video.
    [switch]$Playlist,

    # Embed / download subtitles.
    [Alias('Subtitles')]
    [switch]$Subs,

    # Show the available formats and exit.
    [switch]$List,

    # Never prompt - use the defaults for anything not specified.
    [switch]$Yes,

    # Update the bundled yt-dlp.
    [switch]$Update,

    # Add this folder to your user PATH so 'legrabber' works anywhere, then
    # fetch what's missing.
    [switch]$Install,

    # Undo -Install: drop this folder from your user PATH. Deletes nothing.
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
# Decode native UTF-8 output consistently, including accented saved filenames
# on stock Windows PowerShell (whose redirected-output default is otherwise ANSI).
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

$Script:Root        = $PSScriptRoot
$Script:Bin         = Join-Path $Script:Root 'bin'
$Script:YtDlp       = $null
$Script:Ff          = $null
$Script:DownloadOk  = $false
$Script:SavedPaths  = @()
$Script:ItemIndex   = 0
$Script:ItemTotal   = 0
$Script:PlaylistActivity = 'Playlist'
$Script:LastOutDir  = $null

# PS 5.1 defaults to TLS 1.0, which GitHub won't talk to.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}

# Keep yt-dlp's progress chatter on stderr from being promoted to a fatal error.
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# ---------------------------------------------------------------- presentation

function Say     { param([string]$Text, [string]$Color = 'Gray') Write-Host "  $Text" -ForegroundColor $Color }
function SayHead { param([string]$Text) Write-Host ''; Write-Host "  $Text" -ForegroundColor Cyan }
function SayWarn { param([string]$Text) Write-Host "  $Text" -ForegroundColor Yellow }
function SayErr  { param([string]$Text) Write-Host "  $Text" -ForegroundColor Red }
function SayGood { param([string]$Text) Write-Host "  $Text" -ForegroundColor Green }

function SayRule {
    Write-Host ('  ' + ('-' * 66)) -ForegroundColor DarkGray
}

function Format-Size {
    param($Bytes)
    if ($null -eq $Bytes -or $Bytes -le 0) { return '   ?' }
    $b = [double]$Bytes
    if ($b -ge 1GB) { return ('{0,6:0.##} GB' -f ($b / 1GB)) }
    if ($b -ge 1MB) { return ('{0,6:0.#} MB' -f ($b / 1MB)) }
    return ('{0,6:0.#} KB' -f ($b / 1KB))
}

function Confirm-Action {
    param([string]$Question)
    $a = (Read-Host "  $Question [y/N]").Trim().ToLower()
    return ($a -eq 'y' -or $a -eq 'yes')
}

# ------------------------------------------------------------------ toolchain

function Save-Url {
    param([string]$Uri, [string]$Destination)

    # curl.exe ships with Windows 10 1803+ and shows a proper progress bar.
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail --connect-timeout 30 --max-time 900 --retry 2 --retry-delay 2 --progress-bar -o $Destination $Uri
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Uri" }
        return
    }

    # Invoke-WebRequest's own progress bar makes PS 5.1 crawl.
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $req = @{ Uri = $Uri; OutFile = $Destination }
        if ($PSVersionTable.PSVersion.Major -lt 6) { $req.UseBasicParsing = $true }
        Invoke-WebRequest @req
    }
    finally { $ProgressPreference = $old }
}

function Assert-DownloadHash {
    param([string]$Path, [string]$Expected)
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$') { throw 'The publisher did not provide a valid SHA-256 checksum.' }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected) {
        throw 'Downloaded file failed SHA-256 verification. Nothing was installed; retry later.'
    }
}

function Save-YtDlp {
    param([string]$Destination)
    # Resolve one release first so the executable and checksum cannot come
    # from different versions when "latest" moves during a download.
    $req = @{ Uri = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest';
              Headers = @{ 'User-Agent' = 'legrabber' }; TimeoutSec = 30 }
    $release = Invoke-RestMethod @req
    $assetName = 'yt-dlp.exe'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { $assetName = 'yt-dlp_arm64.exe' }
    elseif (-not [Environment]::Is64BitOperatingSystem) { $assetName = 'yt-dlp_x86.exe' }
    $asset = @($release.assets | Where-Object { $_.name -eq $assetName }) | Select-Object -First 1
    $sums = @($release.assets | Where-Object { $_.name -eq 'SHA2-256SUMS' }) | Select-Object -First 1
    if (-not $asset -or -not $sums) { throw 'The yt-dlp release is missing its executable or checksum list.' }
    $tmp = $Destination + '.' + [guid]::NewGuid().ToString('N') + '.part'
    $sumFile = $tmp + '.sha256'
    try {
        Say "Fetching yt-dlp $($release.tag_name)..." DarkGray
        Save-Url -Uri $sums.browser_download_url -Destination $sumFile
        $expected = $null
        foreach ($line in (Get-Content -LiteralPath $sumFile)) {
            if ($line -match ('^([a-fA-F0-9]{64})\s+\*?' + [regex]::Escape($assetName) + '$')) { $expected = $Matches[1]; break }
        }
        if (-not $expected) { throw 'yt-dlp checksum was not in the publisher checksum list.' }
        Save-Url -Uri $asset.browser_download_url -Destination $tmp
        Assert-DownloadHash -Path $tmp -Expected $expected
        Move-Item -LiteralPath $tmp -Destination $Destination -Force
    }
    finally {
        foreach ($path in @($tmp, $sumFile)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-YtDlp {
    if ($Script:YtDlp) { return $Script:YtDlp }

    $local = Join-Path $Script:Bin 'yt-dlp.exe'
    if (Test-Path $local) { $Script:YtDlp = $local; return $local }

    # Use a system-wide install if there is one; otherwise fetch our own copy.
    $cmd = Get-Command 'yt-dlp' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $Script:YtDlp = $cmd.Source; return $cmd.Source }

    SayWarn 'yt-dlp not found - downloading it into .\bin (one time, ~17 MB)'
    New-Item -ItemType Directory -Force -Path $Script:Bin | Out-Null

    Save-YtDlp -Destination $local

    SayGood "saved $local"
    $Script:YtDlp = $local
    return $local
}

function Get-Ff {
    if ($Script:Ff) { return $Script:Ff }

    # Our own portable copy wins - it's the one that travels with the folder.
    $local = Join-Path $Script:Bin 'ffmpeg\ffmpeg.exe'
    if (Test-Path $local) { $Script:Ff = $local; return $local }

    $cmd = Get-Command 'ffmpeg' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $Script:Ff = $cmd.Source }
    return $Script:Ff
}

# Unpacks the gyan.dev build (one top-level folder containing bin\) into
# .\bin\ffmpeg. Split out so it can be exercised with any zip.
function Expand-Ffmpeg {
    param([string]$ZipPath)

    $tmp = Join-Path $Script:Bin ('_ffmpeg_' + [guid]::NewGuid().ToString('N'))
    $binPrefix = [IO.Path]::GetFullPath($Script:Bin).TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath($tmp).StartsWith($binPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ffmpeg temporary extraction path is outside the dependency folder.'
    }
    try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $tmp -Force

    $exe = Get-ChildItem -Path $tmp -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if (-not $exe) { throw 'ffmpeg.exe was not in that archive.' }

    $dest = Join-Path $Script:Bin 'ffmpeg'
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $exe.Directory.FullName '*') -Destination $dest -Force
    $Script:Ff = Join-Path $dest 'ffmpeg.exe'
    return $Script:Ff
    }
    finally {
        # This is a freshly generated child of Bin, never a user output folder.
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    }
}

function Initialize-Ffmpeg {
    $ff = Get-Ff
    if ($ff) { return $true }

    Say ''
    SayWarn 'ffmpeg not found.'
    Say 'Without it: video must already contain audio; available resolutions vary.' DarkGray
    Say 'Separate original audio streams can be saved without tags or cover art.' DarkGray
    Say 'Merging, audio conversion and subtitle embedding need ffmpeg.' DarkGray

    if ($Yes) { return $false }
    if (-not (Confirm-Action 'Download ffmpeg into .\bin now? (~110 MB, one time)')) {
        Say 'Skipping - you can add it later with:  legrabber -Install' DarkGray
        return $false
    }

    New-Item -ItemType Directory -Force -Path $Script:Bin | Out-Null
    $zip = Join-Path $Script:Bin ('ffmpeg-' + [guid]::NewGuid().ToString('N') + '.zip')
    $sumFile = $zip + '.sha256'
    try {
        Say 'Fetching ffmpeg...' DarkGray
        $uri = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
        Save-Url -Uri ($uri + '.sha256') -Destination $sumFile
        $expected = [regex]::Match((Get-Content -LiteralPath $sumFile -Raw), '(?i)\b[a-f0-9]{64}\b').Value
        Save-Url -Uri $uri -Destination $zip
        Assert-DownloadHash -Path $zip -Expected $expected
        Say 'Unpacking...' DarkGray
        Expand-Ffmpeg -ZipPath $zip | Out-Null
        SayGood "ffmpeg ready: $Script:Ff"
        return $true
    }
    catch {
        SayErr "Could not set up ffmpeg: $($_.Exception.Message)"
        Say 'Get it manually with:  winget install Gyan.FFmpeg' DarkGray
        return $false
    }
    finally {
        foreach ($path in @($zip, $sumFile)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Get-BaseArgs {
    $a = @('--ignore-config', '--no-warnings', '--newline', '--encoding', 'utf-8')
    if ($Browser) { $a += @('--cookies-from-browser', $Browser) }
    if ($Client)  { $a += @('--extractor-args', "youtube:player_client=$Client") }
    $ff = Get-Ff
    if ($ff) { $a += @('--ffmpeg-location', (Split-Path -Parent $ff)) }
    return $a
}

# ------------------------------------------------------------------- plumbing

# Writes the registry value directly so a PATH of type REG_EXPAND_SZ keeps its
# %USERPROFILE%-style entries - SetEnvironmentVariable/setx would flatten them.
function Add-ToUserPath {
    param([string]$Directory)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) { return 'failed' }

    try {
        $raw  = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($key.GetValueNames() -contains 'Path') { $kind = $key.GetValueKind('Path') }

        $parts = @($raw -split ';' | Where-Object { $_ })
        if ($parts -contains $Directory) { return 'present' }

        $key.SetValue('Path', ((@($parts) + $Directory) -join ';'), $kind)
        Send-SettingChange
        return 'added'
    }
    finally { $key.Close() }
}

function Remove-FromUserPath {
    param([string]$Directory)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    if (-not $key) { return 'failed' }

    try {
        $raw  = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
        if ($key.GetValueNames() -contains 'Path') { $kind = $key.GetValueKind('Path') }

        $parts = @($raw -split ';' | Where-Object { $_ })
        if ($parts -notcontains $Directory) { return 'absent' }

        $key.SetValue('Path', ((@($parts | Where-Object { $_ -ne $Directory })) -join ';'), $kind)
        Send-SettingChange
        return 'removed'
    }
    finally { $key.Close() }
}

# Tell running shells that the environment changed, so a newly opened terminal
# sees the new PATH without a reboot.
function Send-SettingChange {
    try {
        if (-not ('Legrabber.Native' -as [type])) {
            Add-Type -Namespace Legrabber -Name Native -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        }
        $HWND_BROADCAST   = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $result = [UIntPtr]::Zero
        [void][Legrabber.Native]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    }
    catch {
        # Non-fatal: the registry change still applies to the next logon.
    }
}

function Invoke-Install {
    SayHead "Setting up legrabber in $Script:Root"

    $result = Add-ToUserPath -Directory $Script:Root
    switch ($result) {
        'added'   {
            SayGood 'Added this folder to your user PATH.'
            Say 'Open a NEW terminal for it to take effect.' Yellow
        }
        'present' { SayGood 'Already on your PATH.' }
        default   { SayWarn 'Could not update PATH - you can still run legrabber.cmd from this folder.' }
    }

    Get-YtDlp | Out-Null
    Initialize-Ffmpeg | Out-Null

    SayHead 'Ready.'
    Say 'Type  legrabber  in any new terminal, or double-click legrabber.cmd.' White
    Write-Host '  Videos land in  ' -NoNewline
    Write-Host (Join-Path $Script:Root 'downloads') -ForegroundColor White
}

function Invoke-Uninstall {
    SayHead 'Removing legrabber from your PATH'
    switch (Remove-FromUserPath -Directory $Script:Root) {
        'removed' { SayGood 'Removed. Open a new terminal for it to take effect.' }
        'absent'  { Say 'This folder was not on your PATH.' }
        default   { SayWarn 'Could not update PATH - remove the entry by hand.' }
    }
    Say ''
    Say 'Nothing was deleted. To finish, remove this folder:' DarkGray
    Write-Host "  $Script:Root" -ForegroundColor White
    Say '(bin\ holds the downloaded yt-dlp and ffmpeg, downloads\ your videos.)' DarkGray
}

function Invoke-YtDlpUpdate {
    $exe = Get-YtDlp
    if ($exe -ne (Join-Path $Script:Bin 'yt-dlp.exe')) {
        SayWarn "Using the system yt-dlp at $exe - update it with your package manager."
        return
    }
    SayHead 'Updating yt-dlp'
    Save-YtDlp -Destination $exe
    SayGood 'yt-dlp updated and its SHA-256 verified.'
}

# ----------------------------------------------------------------- url parsing

function Get-Platform {
    param([string]$CleanUrl)
    $uri = $null
    if (-not [Uri]::TryCreate($CleanUrl, [UriKind]::Absolute, [ref]$uri)) { return 'generic' }
    $host_ = $uri.Host.ToLower()
    if ($host_ -match '(^|\.)(x\.com|twitter\.com|vxtwitter\.com|fxtwitter\.com)$') { return 'x' }
    if ($host_ -match '(^|\.)(instagram\.com|instagr\.am|ddinstagram\.com)$')     { return 'instagram' }
    if ($host_ -match '(^|\.)(youtube\.com|youtu\.be|youtube-nocookie\.com)$')   { return 'youtube' }
    return 'generic'
}

function Repair-Url {
    param([string]$Raw, [switch]$KeepPlaylist)

    $u = $Raw.Trim().Trim('"').Trim("'")
    if ($u -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $u = "https://$u" }

    $uri = $null
    if (-not [Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('https', 'http') -or -not $uri.Host -or
        $u -match '[\x00-\x20]' -or $uri.UserInfo) { return $null }

    # A /playlist link is meaningless without its list= parameter.
    $playlistPath = ($uri.AbsolutePath -match '/playlist')
    $platform = Get-Platform $u

    $drop = @('si', 'feature', 's', 't', 'pp', 'ab_channel',
              'utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content',
              'fbclid', 'igsh', 'igshid', 'ref', 'ref_src', 'ref_url')

    $keep = @()
    foreach ($pair in ($uri.Query.TrimStart('?') -split '&')) {
        if (-not $pair) { continue }
        $k = ($pair -split '=', 2)[0].ToLower()

        # 'list' and 'index' are the playlist. Keep them for a playlist link or
        # when the caller asked for one; otherwise a copied watch link resolves
        # to the single video rather than the mix it came from.
        if ($platform -eq 'youtube' -and ($k -eq 'list' -or $k -eq 'index')) {
            if (-not ($playlistPath -or $KeepPlaylist)) { continue }
        }
        elseif (($platform -ne 'generic' -and $drop -contains $k) -or $k -like 'utm_*') { continue }

        $keep += $pair
    }

    $q = ''
    if ($keep.Count) { $q = '?' + ($keep -join '&') }
    return '{0}://{1}{2}{3}' -f $uri.Scheme, $uri.Authority, $uri.AbsolutePath, $q
}

function Test-PlaylistUrl {
    param([string]$CleanUrl)

    $uri = $null
    if (-not [Uri]::TryCreate($CleanUrl, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.AbsolutePath -match '/playlist') { return $true }
    if ($uri.Query -match '[?&](list|playlist)=') { return $true }
    return $false
}

# Playlist titles become folder names.
function Get-SafeName {
    param([string]$Name, [int]$Max = 80)
    if (-not $Name) { return 'playlist' }
    $safe = [string]$Name -replace '[\x00-\x1f\\/:*?"<>|]', '-'
    $safe = ($safe -replace '\s+', ' ').Trim().TrimEnd('.')
    if ($safe.Length -gt $Max) { $safe = $safe.Substring(0, $Max).Trim().TrimEnd('.') }
    if (-not $safe) { return 'playlist' }
    if ($safe -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { $safe = '_' + $safe }
    return $safe
}

# ------------------------------------------------------------ format inspecting

function Get-VCodecName {
    param($Codec)
    $c = [string]$Codec
    if ($c -like 'avc1*')                     { return 'H.264' }
    if ($c -like 'av01*')                     { return 'AV1' }
    if ($c -like 'vp9*' -or $c -like 'vp09*') { return 'VP9' }
    if ($c -like 'hev1*' -or $c -like 'hvc1*') { return 'HEVC' }
    return $c.ToUpper()
}

function Get-ACodecName {
    param($Codec)
    $c = [string]$Codec
    if ($c -like 'mp4a*' -or $c -like 'aac*') { return 'AAC' }
    if ($c -like 'opus*')                     { return 'Opus' }
    if ($c -like 'vorbis*')                   { return 'Vorbis' }
    if ($c -like 'ec-3*')                     { return 'E-AC-3' }
    if ($c -like 'ac-3*')                     { return 'AC-3' }
    return $c.ToUpper()
}

# Lower is better. MP4/H.264 wins because it plays everywhere; the higher-res
# AV1/VP9 streams only show up where no H.264 variant exists.
function Get-VideoRank {
    param($F)
    $ext = [string]$F.ext
    $c   = [string]$F.vcodec
    if ($ext -eq 'mp4'  -and $c -like 'avc1*')                        { return 0 }
    if ($ext -eq 'mp4'  -and $c -like 'av01*')                        { return 1 }
    if ($ext -eq 'mp4'  -and ($c -like 'vp9*' -or $c -like 'vp09*'))  { return 2 }
    if ($ext -eq 'mp4')                                               { return 3 }
    if ($ext -eq 'webm' -and ($c -like 'vp9*' -or $c -like 'vp09*'))  { return 4 }
    if ($ext -eq 'webm')                                              { return 5 }
    return 6
}

function Get-AudioRank {
    param($F)
    $c = [string]$F.acodec
    if ($c -like 'mp4a*' -or $c -like 'aac*') { return 0 }
    if ($c -like 'opus*')                     { return 1 }
    return 2
}

function Get-ApproxSize {
    param($F, [double]$Duration = 0)
    if ($F.filesize)        { return [long]$F.filesize }
    if ($F.filesize_approx) { return [long]$F.filesize_approx }
    # YouTube's DASH streams usually carry no size at all - estimate from bitrate.
    if ($Duration -gt 0) {
        $kbps = 0
        if ($F.tbr)     { $kbps = [double]$F.tbr }
        elseif ($F.abr) { $kbps = [double]$F.abr }
        if ($kbps -gt 0) { return [long]($kbps * 1000 / 8 * $Duration) }
    }
    return $null
}

function Get-TopAudioFormat {
    param($Info)
    $aud = @($Info.formats | Where-Object {
        $_.acodec -and $_.acodec -ne 'none' -and (-not $_.vcodec -or $_.vcodec -eq 'none')
    })
    if (-not $aud) { return $null }
    return $aud |
        Sort-Object @{ E = { Get-AudioRank $_ } },
                    @{ E = { if ($_.abr) { [double]$_.abr } else { 0 } }; Descending = $true } |
        Select-Object -First 1
}

# One row per (resolution, framerate); the best codec at that resolution wins.
function Get-VideoChoices {
    param($Info, [double]$Duration = 0)

    $vids = @($Info.formats | Where-Object {
        $_.vcodec -and $_.vcodec -ne 'none' -and $_.height
    })
    if (-not $vids) { return @() }

    $rows = foreach ($f in $vids) {
        $fps = 0
        if ($f.fps) { $fps = [int][double]$f.fps }
        $tbr = 0
        if ($f.tbr) { $tbr = [double]$f.tbr }
        [pscustomobject]@{
            Format = $f
            Height = [int]$f.height
            Fps    = $fps
            Rank   = Get-VideoRank $f
            Tbr    = $tbr
            Size   = Get-ApproxSize $f $Duration
        }
    }

    $picked = @()
    foreach ($grp in ($rows | Group-Object { '{0}|{1}' -f $_.Height, $_.Fps })) {
        $picked += ($grp.Group |
            Sort-Object Rank, @{ E = 'Tbr'; Descending = $true } |
            Select-Object -First 1)
    }

    $picked = @($picked |
        Sort-Object @{ E = 'Height'; Descending = $true }, @{ E = 'Fps'; Descending = $true })

    # The merged result carries the audio track too, so report both.
    $top = Get-TopAudioFormat $Info
    if ($top) {
        $asize = Get-ApproxSize $top $Duration
        if ($asize) {
            foreach ($row in $picked) {
                if ($row.Size -and (-not $row.Format.acodec -or $row.Format.acodec -eq 'none')) { $row.Size = $row.Size + $asize }
            }
        }
    }

    return $picked
}

# One row per audio codec (best bitrate of each), plus the conversion targets.
function Get-AudioChoices {
    param($Info, [double]$Duration = 0)

    $aud = @($Info.formats | Where-Object {
        $_.acodec -and $_.acodec -ne 'none' -and (-not $_.vcodec -or $_.vcodec -eq 'none')
    })
    if (-not $aud) { return @() }

    $rows = foreach ($f in $aud) {
        $br = 0
        if ($f.abr)     { $br = [double]$f.abr }
        elseif ($f.tbr) { $br = [double]$f.tbr }
        [pscustomobject]@{
            Format = $f
            Name   = Get-ACodecName $f.acodec
            Rank   = Get-AudioRank $f
            Kbps   = [int]$br
            Size   = Get-ApproxSize $f $Duration
        }
    }

    $picked = @()
    foreach ($grp in ($rows | Group-Object Name)) {
        $picked += ($grp.Group |
            Sort-Object Rank, @{ E = 'Kbps'; Descending = $true } |
            Select-Object -First 1)
    }
    $picked = @($picked | Sort-Object Rank, @{ E = 'Kbps'; Descending = $true })

    # Append the "convert it for me" options.
    foreach ($target in @('mp3', 'm4a')) {
        $picked += [pscustomobject]@{
            Format  = $null
            Name    = $target.ToUpper() + ' (converted)'
            Rank    = 90
            Kbps    = 0
            Size    = $null
            Convert = $target
        }
    }
    return $picked
}

# ---------------------------------------------------------------- the pickers

function Show-Header {
    param($Info, $PlaylistTitle, $PlaylistCount)

    SayRule
    if ($PlaylistTitle) {
        Say "Playlist: $PlaylistTitle" White
        $sub = @()
        if ($PlaylistCount) { $sub += "$PlaylistCount items" }
        if ($Info.title)    { $sub += "first up: $($Info.title)" }
        if ($sub.Count) { Say ($sub -join '  -  ') DarkGray }
    }
    else {
        if ($Info.title) { Say $Info.title White }
        $meta = @()
        if ($Info.uploader) { $meta += $Info.uploader }
        if ($Info.duration) {
            $d = [TimeSpan]::FromSeconds([double]$Info.duration)
            if ($d.TotalHours -ge 1) { $meta += ('{0:h\:mm\:ss}' -f $d) } else { $meta += ('{0:m\:ss}' -f $d) }
        }
        if ($meta.Count) { Say ($meta -join '  -  ') DarkGray }
    }
    SayRule
}

function Show-VideoTable {
    param($Choices)
    Say 'VIDEO' DarkCyan
    $i = 0
    foreach ($c in $Choices) {
        $i++
        $res  = '{0}p' -f $c.Height
        if ($c.Fps -ge 50) { $res += $c.Fps }
        $tech = '{0} / {1}' -f (Get-VCodecName $c.Format.vcodec), $c.Format.ext.ToUpper()
        Say ('{0,3}) {1,-10} {2,-16} {3}' -f $i, $res, $tech, (Format-Size $c.Size))
    }
    Say ''
}

function Show-AudioTable {
    param($Choices)
    Say 'AUDIO' DarkCyan
    $i = 0
    foreach ($c in $Choices) {
        $i++
        $tech = $c.Name
        if ($c.Kbps -gt 0) { $tech += ' ~{0} kbps' -f $c.Kbps }
        Say ('{0,3}) {1,-28} {2}' -f $i, $tech, (Format-Size $c.Size))
    }
    Say ''
}

# "1 for video or 2 for audio" - asked before anything else, so a music link
# never makes you read past a wall of video resolutions.
function Read-Kind {
    while ($true) {
        $a = (Read-Host '  Video or audio?  1 = video, 2 = audio  (q to quit)').Trim().ToLower()
        if ($a -eq 'q' -or $a -eq 'quit') { return $null }
        if ($a -eq '1' -or $a -eq 'v' -or $a -eq 'video') { return 'video' }
        if ($a -eq '2' -or $a -eq 'a' -or $a -eq 'audio') { return 'audio' }
        SayWarn 'Type 1 for video or 2 for audio.'
    }
}

# 1-based row number, 0 for "best", -1 to cancel.
function Read-Index {
    param([int]$Count)

    if ($Count -le 0) { return -1 }
    $prompt = "  Pick 1-$Count (b for best, q to quit)"

    while ($true) {
        $a = (Read-Host $prompt).Trim().ToLower()
        if ($a -eq 'q' -or $a -eq 'quit') { return -1 }
        if ($a -eq 'b') { return 0 }
        if ($a -match '^\d+$') {
            $n = 0
            if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Count) { return $n }
        }
        SayWarn "Not an option - enter 1-$Count."
    }
}

function Get-Info {
    param([string]$CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist, [switch]$SearchResults)

    # For a playlist, one call gets the playlist *and* the full formats of its
    # first item - which is what the quality menu is built from. -J is
    # --dump-single-json, so this stays a single object either way.
    $flags = @('-J', '--no-playlist', $CleanUrl)
    if ($Playlist) { $flags = @('-J', '--yes-playlist', '--playlist-items', '1', $CleanUrl) }
    if ($FlatPlaylist) { $flags = @('-J', '--flat-playlist', '--yes-playlist', '--playlist-items', '1:10', $CleanUrl) }
    if ($SearchResults) { $flags = @('-J', '--flat-playlist', '--yes-playlist', '--skip-download', ('ytsearch10:' + $CleanUrl)) }

    $raw = @()
    $errLines = @()
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Get-YtDlp) @($BaseArgs + $flags) 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $errLines += $_.Exception.Message }
            elseif ([string]$_ -match '^(ERROR|WARNING):') { $errLines += [string]$_ }
            else { $raw += [string]$_ }
        }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $oldEap }
    if ($code -ne 0 -or -not $raw) {
        if ($SearchResults) { SayErr 'Could not search YouTube.' }
        else { SayErr 'Could not read the video info.' }
        foreach ($line in $errLines) { SayWarn $line }
        if ($SearchResults) { SayWarn 'Check your connection, or try -Update if search keeps failing.' }
        else { Show-FailureHint -Platform (Get-Platform $CleanUrl) -ErrText ($errLines -join "`n") }
        return $null
    }
    try { return (($raw -join "`n") | ConvertFrom-Json) }
    catch { SayErr 'yt-dlp returned unreadable video info. Try -Update.'; return $null }
}

# ----------------------------------------------------------------- downloading

function Show-FailureHint {
    param([string]$Platform, [string]$ErrText)

    if ($ErrText -match '(ffmpeg|ffprobe).*(not found|not installed|could not be found|unavailable)') {
        SayWarn 'This operation needs ffmpeg. Add it with:  legrabber -Install'
        return
    }
    if ($ErrText -match 'Unsupported URL|Invalid URL|Unable to download webpage|Name or service not known|Failed to resolve|nodename nor servname') {
        SayWarn 'Check the address and your connection. If the site changed, try -Update.'
        return
    }
    if ($ErrText -match 'Postprocessing|thumbnail embedding') {
        SayWarn 'Media may have downloaded, but final processing failed. Check the output folder.'
        return
    }
    if ($ErrText -match '403|Forbidden') {
        if ($Platform -eq 'youtube') {
            SayWarn 'The media URL was refused (HTTP 403). On YouTube that is almost always a'
            SayWarn 'stale token, and it clears on its own - run the same link again.'
            SayWarn 'If it keeps happening:  -Browser chrome   (or -Update first).'
        }
        else {
            SayWarn 'The server refused the download (HTTP 403).'
            SayWarn 'If this post is private or behind a login, retry with:  -Browser chrome'
        }
        return
    }
    if ($ErrText -match 'Sign in to confirm|not a bot|Please sign in|--cookies') {
        SayWarn 'YouTube wants you signed in for this one (age-gated, or it thinks you are a bot).'
        SayWarn 'Retry with:  -Browser chrome'
        return
    }
    if ($ErrText -match 'Requested format is not available') {
        SayWarn 'That exact stream is not offered for every item here.'
        SayWarn 'Try a different row, or -Quality with a lower resolution.'
        if (-not (Get-Ff)) { SayWarn 'Without ffmpeg only streams already containing the required audio/video can be saved.' }
        return
    }
    if ($Platform -eq 'youtube') {
        SayWarn 'If this keeps failing, try -Browser chrome, or -Update.'
        return
    }
    if ($Browser) {
        SayWarn "Cookies were read from $Browser - if that failed, close the browser and retry."
        return
    }
    SayWarn 'Login-walled posts (private reels, age-restricted tweets) need cookies.'
    SayWarn 'Retry with:  -Browser chrome   (or firefox / edge)'
}

function Invoke-Download {
    # NB: not -Args, which would collide with PowerShell's automatic $Args
    # variable and splat an empty list.
    param([string[]]$ArgumentList, [string]$Platform)

    $Script:DownloadOk = $false
    $Script:SavedPaths = @()
    $Script:ItemIndex = 0
    $Script:ItemTotal = 0

    for ($attempt = 1; $attempt -le 2; $attempt++) {

        # yt-dlp's output is piped rather than left to the console so we can
        # drive Write-Progress: a native \r bar doesn't survive PowerShell's
        # stdout handling, and this renders the same on 5.1 and 7.
        $errText = ''
        $name = ''
        $oldEap = $ErrorActionPreference

        try {
            # 5.1 turns native stderr into ErrorRecord objects. With Stop, even
            # redirected stderr aborts the pipeline before LASTEXITCODE is read.
            $ErrorActionPreference = 'Continue'
            & (Get-YtDlp) @ArgumentList 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errText += $_.Exception.Message + "`n"
                    return
                }
                $line = [string]$_
                if ($line -match '^(ERROR|WARNING):') { $errText += $line + "`n"; return }

                if ($line -like 'LEGRABBER_OUT:*') {
                    $Script:SavedPaths += $line.Substring(14)
                    return
                }
                # Playlist position: drives the outer bar, one bar per item below.
                if ($line -match '^\[download\] Downloading (?:item|video) (\d+) of (\d+)') {
                    $Script:ItemIndex = [int]$Matches[1]
                    $Script:ItemTotal = [int]$Matches[2]
                    $name = ''
                    if ($Script:ItemTotal -gt 0) {
                        Write-Progress -Id 1 -Activity $Script:PlaylistActivity `
                            -Status "item $($Script:ItemIndex) of $($Script:ItemTotal)" `
                            -PercentComplete ((($Script:ItemIndex - 1) / [double]$Script:ItemTotal) * 100)
                    }
                    return
                }
                if ($line -match '^\[download\] Destination: (.+)$') {
                    $name = Split-Path -Leaf $Matches[1]
                    return
                }
                if ($line -match '^\[download\]\s+([\d.]+)% of\s+~?\s*(\S+)') {
                    $pct  = [double]$Matches[1]
                    $tail = $Matches[2]
                    if ($line -match '\s+at\s+(.+?)\s+ETA\s+(\S+)') {
                        $tail = "$($Matches[1])   ETA $($Matches[2])"
                    }
                    if ($pct -lt 100) {
                        $status = $tail
                        if ($name) { $status = "$name   -   $tail" }
                        Write-Progress -Id 0 -Activity 'legrabber' -Status $status -PercentComplete $pct
                    }
                    elseif ($Script:ItemTotal -gt 0) {
                        # This item is finished - clear its bar and step the outer one.
                        Write-Progress -Id 0 -Activity 'legrabber' -Completed
                        Write-Progress -Id 1 -Activity $Script:PlaylistActivity `
                            -Status "item $($Script:ItemIndex) of $($Script:ItemTotal)  -  done" `
                            -PercentComplete (($Script:ItemIndex / [double]$Script:ItemTotal) * 100)
                    }
                    return
                }
                if ($line -match '^\[(Merger|ExtractAudio|Metadata|EmbedThumbnail|FixupM3u8)\]') {
                    Write-Progress -Id 0 -Activity 'legrabber' -Completed
                    Write-Host "  $line" -ForegroundColor DarkGray
                    return
                }
                # Extractor chatter ("[youtube] abc: Downloading webpage") and
                # the merge's cleanup pass are noise, not information.
                if ($line -match '^\[[A-Za-z_:-]+\]\s+\S+:\s+(Downloading|Extracting|Fetching|Checking|Looking|Resolving)') { return }
                if ($line -match '^Deleting original file') { return }

                if ($line.Trim()) { Write-Host "  $line" -ForegroundColor DarkGray }
            }
            $code = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldEap
            Write-Progress -Id 0 -Activity 'legrabber' -Completed
            Write-Progress -Id 1 -Activity $Script:PlaylistActivity -Completed
        }

        $Script:SavedPaths = @($Script:SavedPaths | Select-Object -Unique)
        if ($code -eq 0 -and $errText -notmatch 'ERROR:' -and $Script:SavedPaths.Count -gt 0) {
            $Script:DownloadOk = $true
            return
        }

        # stderr was captured to drive the hints above, which means the user
        # never saw any of it. Dig the real errors back out and show them.
        $errors = @()
        if ($errText) {
            $errors = @($errText -split "`r?`n" |
                Where-Object { $_ -match 'ERROR:' } |
                ForEach-Object { $_.Trim() })
        }

        # A 403 here means the media URL went stale between extraction and
        # fetch. Asking again gets a fresh one, so try that before giving up.
        if ($attempt -eq 1 -and $errText -match '403|Forbidden') {
            Say ''
            SayWarn 'Media URL was rejected (HTTP 403) - usually a stale token. Retrying once...'
            Start-Sleep -Seconds 2
            continue
        }

        # On a playlist one dead track should not read as total failure.
        if ($Script:SavedPaths.Count -gt 0) {
            Say ''
            if ($errors.Count -gt 0) {
                SayWarn 'Some downloads or final processing failed. Successfully finished files are listed below:'
                foreach ($e in $errors) { Say $e Yellow }
            }
            else { SayWarn "Finished files were saved, but yt-dlp exited with code $code." }
            Show-FailureHint -Platform $Platform -ErrText $errText
            return
        }

        Say ''
        if ($code -eq 0) { SayErr 'No files were finished.' }
        else { SayErr "yt-dlp exited with code $code." }
        foreach ($e in $errors) { Say $e Yellow }
        if ($errors.Count -eq 0 -and $errText.Trim()) { SayWarn $errText.Trim() }
        Show-FailureHint -Platform $Platform -ErrText $errText
        return
    }
}

function Get-OutputDir {
    param([string]$Platform)
    $sub = switch ($Platform) {
        'youtube'   { 'YouTube' }
        'x'         { 'X' }
        'instagram' { 'Instagram' }
        default     { 'Other' }
    }
    if ($Out) { $dir = $Out } else { $dir = Join-Path (Join-Path $Script:Root 'downloads') $sub }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return $dir
}

function Get-Template {
    param([string]$Platform, [switch]$Playlist)
    if ($Playlist) { return '%(playlist_index)02d - %(title).120B [%(id)s].%(ext)s' }
    switch ($Platform) {
        'x'         { return '%(uploader_id,uploader)s - %(id)s.%(ext)s' }
        'instagram' { return '%(uploader)s - %(id)s.%(ext)s' }
        default     { return '%(title).120B [%(id)s].%(ext)s' }
    }
}

function ConvertTo-Selector {
    param([string]$Q)

    $q = $Q.Trim().ToLower()

    if ($q -eq 'best' -or $q -eq 'max' -or $q -eq 'highest') { return 'bv*+ba/b' }
    if ($q -eq 'audio') { return 'ba/b' }

    switch ($q) {
        '4k'  { $q = '2160' }
        '2k'  { $q = '1440' }
        'uhd' { $q = '2160' }
        'fhd' { $q = '1080' }
        'hd'  { $q = '720' }
    }

    if ($q -match '^(\d+)p?$') {
        $h = $Matches[1]
        # Same preference order the menu shows: H.264 first (plays anywhere,
        # drops straight into editors), then AV1, then whatever is left. The
        # audio is pinned to m4a so the merge lands in .mp4 rather than .mkv.
        $h264 = "bv*[height<=$h][vcodec^=avc1]"
        $av1  = "bv*[height<=$h][vcodec^=av01]"
        return "$h264+ba[ext=m4a]/$h264+ba/$av1+ba[ext=m4a]/$av1+ba/bv*[height<=$h]+ba/b[height<=$h]"
    }
    return $Q   # raw yt-dlp selector, passed through
}

# ------------------------------------------------------------------ entrypoint

function Test-LinkInput {
    param([string]$Text)
    # Keep bare domains and malformed explicit URLs on the existing URL path.
    # Plain titles, artist names and phrases use search instead.
    return ($Text -match '^(?:[a-zA-Z][a-zA-Z0-9+.-]*://|www\.|(?:[^\s/?#]+\.)+[a-zA-Z]{2,}(?=[:/?#]|$)|localhost(?=[:/?#]|$))')
}

function Test-SpotifyInput {
    param([string]$Text)
    if ($Text -match '^spotify:') { return $true }
    $clean = Repair-Url $Text
    $uri = $null
    return ($clean -and [Uri]::TryCreate($clean, [UriKind]::Absolute, [ref]$uri) -and
            $uri.Host -in @('open.spotify.com', 'spotify.link', 'spotify.app.link'))
}

function Get-SpotifyTrackId {
    param([string]$Text)
    if ($Text -cmatch '^spotify:track:([a-zA-Z0-9]{22})$') { return $Matches[1] }
    $clean = Repair-Url $Text
    $uri = $null
    if (-not $clean -or -not [Uri]::TryCreate($clean, [UriKind]::Absolute, [ref]$uri) -or $uri.Host -ne 'open.spotify.com') { return $null }
    if ($uri.AbsolutePath -match '^/(?:intl-[a-z]{2}(?:-[a-z]{2})?/)?(?:embed/)?track/([a-zA-Z0-9]{22})/?$') { return $Matches[1] }
    return $null
}

function ConvertFrom-SpotifyEmbed {
    param([string]$Html, [string]$TrackId)
    # Read only public track metadata from the embed's JSON. Never evaluate
    # page scripts or use the page's session/playback data.
    $match = [regex]::Match($Html, '(?is)<script\b[^>]*\bid\s*=\s*["'']__NEXT_DATA__["''][^>]*>(.*?)</script>')
    if (-not $match.Success) { throw 'Spotify did not return readable track metadata.' }
    try { $data = $match.Groups[1].Value | ConvertFrom-Json }
    catch { throw 'Spotify returned unreadable track metadata.' }
    $entity = $data.props.pageProps.state.data.entity
    if (-not $entity -or $entity.type -ne 'track' -or $entity.id -cne $TrackId) {
        throw 'Spotify did not return metadata for this track.'
    }
    $title = [string]$entity.title
    if (-not $title) { $title = [string]$entity.name }
    $title = ($title -replace '[\x00-\x1f\x7f]', ' ').Trim()
    $artists = @($entity.artists | ForEach-Object {
        $name = ([string]$_.name -replace '[\x00-\x1f\x7f]', ' ').Trim()
        if ($name) { $name }
    } | Select-Object -Unique)
    if (-not $title -or $artists.Count -eq 0) { throw 'Spotify did not provide both the song title and artist.' }
    return [pscustomobject]@{
        Title = $title
        Artists = $artists
        Query = (($artists -join ', ') + ' ' + $title)
    }
}

function Get-SpotifyTrack {
    param([ValidatePattern('^[a-zA-Z0-9]{22}$')][string]$TrackId)
    try {
        $req = @{ Uri = ('https://open.spotify.com/embed/track/' + $TrackId);
                  TimeoutSec = 30; MaximumRedirection = 3;
                  Headers = @{ 'User-Agent' = 'legrabber'; 'Accept-Language' = 'en' } }
        if ($PSVersionTable.PSVersion.Major -lt 6) { $req.UseBasicParsing = $true }
        $response = Invoke-WebRequest @req
        return (ConvertFrom-SpotifyEmbed -Html $response.Content -TrackId $TrackId)
    }
    catch {
        SayErr "Could not read the Spotify track: $($_.Exception.Message)"
        SayWarn 'Try searching by song title and artist instead, or retry the link later.'
        return $null
    }
}

function Get-SearchResults {
    param([string]$Query)
    $info = Get-Info -CleanUrl $Query -BaseArgs @(Get-BaseArgs) -SearchResults
    if (-not $info) { return $null }
    $seen = [System.Collections.Generic.Dictionary[string,bool]]::new([StringComparer]::Ordinal)
    $rows = @()
    foreach ($entry in @($info.entries)) {
        if (-not $entry -or $entry.id -notmatch '^[a-zA-Z0-9_-]{11}$' -or $seen.ContainsKey([string]$entry.id)) { continue }
        $seen[[string]$entry.id] = $true
        $title = [string]$entry.title
        if (-not $title) { $title = [string]$entry.id }
        $channel = [string]$entry.channel
        if (-not $channel) { $channel = [string]$entry.uploader }
        $rows += [pscustomobject]@{
            Title = ($title -replace '[\x00-\x1f\x7f]', ' ')
            Channel = ($channel -replace '[\x00-\x1f\x7f]', ' ')
            Duration = $entry.duration
            LiveStatus = $entry.live_status
            Url = ('https://www.youtube.com/watch?v=' + $entry.id)
        }
        if ($rows.Count -eq 10) { break }
    }
    # An empty successful search is distinct from a native/extraction failure.
    return [pscustomobject]@{ Results = $rows }
}

function Show-SearchResults {
    param($Results)
    SayRule
    $i = 0
    foreach ($row in $Results) {
        $i++
        Say ('{0,3}) {1}' -f $i, $row.Title) White
        $meta = @()
        if ($row.Channel) { $meta += $row.Channel }
        if ($row.LiveStatus -eq 'is_live') { $meta += 'LIVE' }
        elseif ($row.LiveStatus -eq 'is_upcoming') { $meta += 'Upcoming' }
        elseif ($null -ne $row.Duration -and $row.Duration -ge 0) {
            $d = [TimeSpan]::FromSeconds([double]$row.Duration)
            if ($d.TotalHours -ge 1) { $meta += ('{0}:{1:00}:{2:00}' -f [int][Math]::Floor($d.TotalHours), $d.Minutes, $d.Seconds) }
            else { $meta += ('{0}:{1:00}' -f $d.Minutes, $d.Seconds) }
        }
        if ($meta.Count) { Say ('     ' + ($meta -join '  -  ')) DarkGray }
    }
    SayRule
}

function Read-SearchIndex {
    param([int]$Count)
    while ($true) {
        $answer = Read-Host "  Choose 1-$Count (q to cancel)"
        if ($null -eq $answer) { return -1 }
        $answer = $answer.Trim().ToLower()
        if (-not $answer -and [Console]::IsInputRedirected) { return -1 }
        if ($answer -in @('q', 'quit')) { return -1 }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Count) { return $n }
        SayWarn "Not an option - enter 1-$Count, or q to cancel."
    }
}

function Invoke-Input {
    param([string]$Target)
    # Search failure/cancellation must not show a previous download's summary.
    $Script:DownloadOk = $false
    $Script:SavedPaths = @()
    $Script:LastOutDir = $null
    $text = $Target.Trim().Trim('"').Trim("'")
    if (-not $text) { SayErr 'Enter a video address or a YouTube search phrase.'; return $false }
    if (-not $Search -and (Test-SpotifyInput $text)) {
        $trackId = Get-SpotifyTrackId $text
        if (-not $trackId) {
            SayErr 'Use a full Spotify track link: https://open.spotify.com/track/<id>. Albums, playlists and short links are not supported.'
            return $false
        }
        if ($Yes -and -not $Pick) {
            SayErr 'Spotify links with -Yes need -Pick 1-10 to select a YouTube match without prompting.'
            return $false
        }
        Say 'Reading the Spotify song title and artist...' DarkGray
        $track = Get-SpotifyTrack -TrackId $trackId
        if (-not $track) { return $false }
        SayHead ('Spotify: ' + $track.Title + ' - ' + ($track.Artists -join ', '))
        Say 'Choose a YouTube match below; the downloaded file comes from YouTube.' DarkGray
        $text = $track.Query
    }
    elseif (-not $Search -and (Test-LinkInput $text)) {
        if ($Pick) { SayErr '-Pick applies to a search phrase. Omit it for a URL, or add -Search.'; return $false }
        return (Invoke-One -Target $text)
    }
    if ($Yes -and -not $Pick) {
        SayErr 'Searching with -Yes needs -Pick 1-10 to select a result without prompting.'
        return $false
    }
    SayHead "Searching YouTube: $text"
    $searchInfo = Get-SearchResults -Query $text
    if (-not $searchInfo) { return $false }
    $results = @($searchInfo.Results)
    if ($results.Count -eq 0) { SayWarn 'No videos found. Try another search phrase.'; return $false }
    Show-SearchResults $results
    $n = $Pick
    if (-not $n) { $n = Read-SearchIndex -Count $results.Count }
    if ($n -lt 0) { Say 'Cancelled.'; return $true }
    if ($n -gt $results.Count) { SayErr "Only $($results.Count) result(s) were found; -Pick $n is unavailable."; return $false }
    return (Invoke-One -Target $results[$n - 1].Url)
}

function Get-FilenameLimit {
    param([string]$Directory)
    # Reserve space for format IDs, extensions, .part and postprocessing names.
    $limit = [Math]::Min(150, 240 - [IO.Path]::GetFullPath($Directory).Length - 1 - 35)
    if ($limit -lt 32) { throw 'Output path is too long. Choose a shorter folder with -Out.' }
    return [string]$limit
}

function Get-AudioArgs {
    param([string]$Selector = 'ba/b', [string]$Format = 'original')
    if (-not (Get-Ff)) {
        if ($Format -ne 'original') { throw 'Audio conversion needs ffmpeg. Add it with: legrabber -Install' }
        # Without extraction, a combined stream would save video as "audio".
        return @('-f', ($Selector -replace '/b$', ''))
    }
    $a = @('-f', $Selector, '-x', '--audio-format', 'best', '--embed-metadata')
    if ($Format -ne 'original') {
        $a[4] = $Format
        if ($Format -eq 'mp3') { $a += @('--audio-quality', '0') }
        if ($Format -in @('mp3', 'm4a', 'flac', 'opus')) { $a += '--embed-thumbnail' }
    }
    else {
        # yt-dlp's "best" extractor otherwise re-encodes unknown codecs to MP3.
        # Require copying for original mode; unsupported containers fail clearly.
        $a += @('--postprocessor-args', 'ExtractAudio+ffmpeg_o:-acodec copy')
    }
    # Original audio uses lossless extraction/remuxing. Its codec may resolve
    # to a container that cannot hold cover art, so no thumbnail is requested.
    return $a
}

function Show-FormatList {
    param([string]$CleanUrl, [string[]]$BaseArgs, [switch]$Playlist)
    $flags = @('-F', '--no-playlist', $CleanUrl)
    if ($Playlist) { $flags = @('-F', '--yes-playlist', '--playlist-items', '1', $CleanUrl) }
    $errText = ''
    $oldEap = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & (Get-YtDlp) @($BaseArgs + $flags) 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $errText += $_.Exception.Message + "`n" }
            elseif ([string]$_ -match '^ERROR:') { $errText += [string]$_ + "`n" }
            else { Say ([string]$_) }
        }
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $oldEap }
    if ($code -ne 0) {
        SayErr "Could not list formats (yt-dlp exit $code)."
        if ($errText.Trim()) { SayWarn $errText.Trim() }
        Show-FailureHint -Platform (Get-Platform $CleanUrl) -ErrText $errText
        return $false
    }
    return $true
}

function Invoke-One {
    param([string]$Target)

    $Script:DownloadOk = $false
    $Script:SavedPaths = @()
    $Script:LastOutDir = $null
    $Script:PlaylistActivity = 'Playlist'
    $clean    = Repair-Url -Raw $Target -KeepPlaylist:$Playlist
    if (-not $clean) { SayErr 'That is not a valid web address. Paste an http:// or https:// video link.'; return $false }
    $platform = Get-Platform $clean
    $isList   = ($platform -eq 'youtube') -and (Test-PlaylistUrl $clean)

    $base     = @(Get-BaseArgs)

    SayHead "Downloading from $platform"
    Say $clean DarkGray
    if ($List) { return (Show-FormatList -CleanUrl $clean -BaseArgs $base -Playlist:$isList) }
    if ($Audio -and $Quality) { SayWarn '-Quality is ignored for audio-only downloads.' }
    $ff = Get-Ff
    if ($Subs -and -not $ff) { SayErr 'Embedding subtitles needs ffmpeg. Add it with: legrabber -Install'; return $false }
    if ($Audio -and $AudioFormat -ne 'original' -and -not $ff) {
        SayErr 'Audio conversion needs ffmpeg. Add it with: legrabber -Install'
        return $false
    }
    $outDir   = Get-OutputDir $platform
    $template = Get-Template -Platform $platform -Playlist:$isList

    $interactive = ($platform -eq 'youtube' -and -not $Audio -and -not $Quality -and -not $Yes)
    $info = $null
    $ptitle = $null
    $pcount = 0
    if ($isList) {
        $info = Get-Info -CleanUrl $clean -BaseArgs $base -Playlist -FlatPlaylist
        if (-not $info) { return $false }
        $ptitle = $info.title
        if ($info.playlist_count) { $pcount = [int]$info.playlist_count }
        $folderMax = [Math]::Min(80, 240 - [IO.Path]::GetFullPath($outDir).Length - 1 - 1 - 35 - 32)
        if ($folderMax -lt 8) { SayErr 'Output path is too long for a playlist. Choose a shorter folder with -Out.'; return $false }
        $outDir = Join-Path $outDir (Get-SafeName -Name $ptitle -Max $folderMax)
        if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
        $Script:PlaylistActivity = "Playlist: $ptitle"
    }
    $Script:LastOutDir = $outDir
    $filenameLimit = Get-FilenameLimit $outDir

    # --- YouTube: ask what you actually want --------------------------------
    if ($interactive) {

        Say 'Reading available formats...' DarkGray
        if (-not $info) { $info = Get-Info -CleanUrl $clean -BaseArgs $base }
        if (-not $info) { return $false }

        # Use a playable representative for the menu, even if item 1 is private.
        $menuInfo = $info

        if ($isList) {
            $entries = @($info.entries | Where-Object { $null -ne $_ })
            if ($entries.Count -eq 0) { SayErr 'That playlist looks empty.'; return $false }

            $menuInfo = $null
            foreach ($entry in $entries) {
                if ($entry.availability -in @('private', 'premium_only', 'subscriber_only', 'needs_auth') -and -not $Browser) { continue }
                if ($entry.formats) { $menuInfo = $entry; break }
                $entryUrl = $entry.webpage_url
                if (-not $entryUrl) { $entryUrl = $entry.url }
                if (-not $entryUrl) { continue }
                if ($entryUrl -notmatch '^https?://') { $entryUrl = 'https://www.youtube.com/watch?v=' + $entryUrl }
                $candidate = Get-Info -CleanUrl $entryUrl -BaseArgs $base
                if ($candidate -and $candidate.formats) { $menuInfo = $candidate; break }
            }
            if (-not $menuInfo) {
                SayErr 'Could not inspect a playable item among the first ten. Use -Yes, -Audio or -Quality to download the rest without a menu.'
                return $false
            }
            $ptitle   = $info.title
            if ($info.playlist_count) { $pcount = [int]$info.playlist_count }
            else                      { $pcount = $entries.Count }

        }

        $dur = 0
        if ($menuInfo.duration) { $dur = [double]$menuInfo.duration }
        $videoInfo = $menuInfo
        if (-not $ff) {
            $videoInfo = [pscustomobject]@{ formats = @($menuInfo.formats | Where-Object { $_.acodec -and $_.acodec -ne 'none' }) }
        }
        $vids = @(Get-VideoChoices -Info $videoInfo -Duration $dur)
        $auds = @(Get-AudioChoices -Info $menuInfo -Duration $dur | Where-Object { $ff -or -not $_.Convert })
        if ($vids.Count -eq 0 -and $auds.Count -eq 0) { SayErr 'No downloadable streams found.'; return $false }

        Show-Header -Info $menuInfo -PlaylistTitle $ptitle -PlaylistCount $pcount

        $kind = Read-Kind
        if (-not $kind) { Say 'Cancelled.'; return $true }

        $dl = $base + @('-P', $outDir, '-o', $template, '--windows-filenames', '--trim-filenames', $filenameLimit, '--progress',
                        '--no-simulate', '--print', 'after_move:LEGRABBER_OUT:%(filepath)s')
        # Continue after a dead track while preserving the failure exit code.
        if ($isList) { $dl += @('--yes-playlist', '--no-abort-on-error') } else { $dl += '--no-playlist' }

        if ($kind -eq 'video') {
            Show-VideoTable $vids
            $n = Read-Index -Count $vids.Count
            if ($n -lt 0) { Say 'Cancelled.'; return $true }

            if ($n -eq 0) {
                if ($ff) { $dl += @('-f', 'bv*+ba[ext=m4a]/bv*+ba/b') }
                else { $dl += @('-f', 'b') }
            }
            elseif ($isList) {
                # A specific format id may not exist on every item, so aim at
                # the resolution and let each one resolve its own stream.
                $selector = ConvertTo-Selector "$($vids[$n - 1].Height)"
                if (-not $ff) { $selector = "b[height<=$($vids[$n - 1].Height)]" }
                $fps = $vids[$n - 1].Fps
                if ($fps -gt 0) { $selector = $selector -replace '(\[height<=\d+\])', ('$1[fps<=' + $fps + ']') }
                $dl += @('-f', $selector)
            }
            else {
                # Pair the exact video stream with an audio track that fits its
                # container, otherwise yt-dlp falls back to merging into .mkv.
                $v    = $vids[$n - 1].Format
                if (-not $ff) { $dl += @('-f', [string]$v.format_id) }
                else {
                $aext = 'webm'
                if ($v.ext -eq 'mp4') { $aext = 'm4a' }
                $dl += @('-f', "$($v.format_id)+ba[ext=$aext]/$($v.format_id)+ba/$($v.format_id)/bv*+ba/b")
                }
            }
            if ($Subs) { $dl += @('--write-subs', '--embed-subs', '--sub-langs', 'en.*,en', '--convert-subs', 'srt') }
        }
        else {
            Show-AudioTable $auds
            $n = Read-Index -Count $auds.Count
            if ($n -lt 0) { Say 'Cancelled.'; return $true }

            if ($n -eq 0) { $n = 1 }
            $pick = $auds[$n - 1]
            if ($pick.Convert) {
                $dl += @(Get-AudioArgs -Format $pick.Convert)
            }
            else {
                # By container rather than format id, so it survives every item.
                $dl += @(Get-AudioArgs -Selector "ba[ext=$($pick.Format.ext)]/ba/b")
            }
        }

        Say ''
        Invoke-Download -ArgumentList ($dl + $clean) -Platform $platform
        return $Script:DownloadOk
    }

    # --- everything else: pick a format string and go ----------------------
    $dl = $base + @('-P', $outDir, '-o', $template, '--windows-filenames', '--trim-filenames', $filenameLimit, '--progress',
                    '--no-simulate', '--print', 'after_move:LEGRABBER_OUT:%(filepath)s')

    if ($platform -eq 'youtube') {
        if ($isList) { $dl += @('--yes-playlist', '--no-abort-on-error') } else { $dl += '--no-playlist' }
    }

    if ($Audio) {
        $dl += @(Get-AudioArgs -Format $AudioFormat)
    }
    else {
        $selector = 'bv*+ba/b'
        if ($Quality) { $selector = ConvertTo-Selector $Quality }
        if (-not $ff) {
            if (-not $Quality -or $Quality -match '^(best|max|highest)$') { $selector = 'b' }
            elseif ($Quality -match '^(\d+)p?$|^(4k|2k|uhd|fhd|hd)$') {
                $hmatch = [regex]::Match($selector, 'height<=(\d+)')
                $selector = "b[height<=$($hmatch.Groups[1].Value)]"
            }
        }
        $dl += @('-f', $selector)
        if ($Subs) { $dl += @('--write-subs', '--embed-subs', '--sub-langs', 'en.*,en', '--convert-subs', 'srt') }
    }

    $dl += $clean

    Say ''
    Invoke-Download -ArgumentList $dl -Platform $platform
    return $Script:DownloadOk
}

function Show-Result {
    if ($Script:SavedPaths.Count -eq 0) { return }

    $paths = @($Script:SavedPaths)
    SayHead "Saved to $Script:LastOutDir"
    if ($paths.Count -eq 0) { return }

    $shown = $paths
    if ($paths.Count -gt 20) { $shown = @($paths[0..19]) }
    foreach ($p in $shown) { SayGood (Split-Path -Leaf $p) }
    if ($paths.Count -gt $shown.Count) { Say "... and $($paths.Count - $shown.Count) more" DarkGray }
}

function Main {
    Write-Host ''
    Write-Host '  legrabber' -ForegroundColor Magenta -NoNewline
    Write-Host '  x / instagram / youtube' -ForegroundColor DarkGray

    if ($Install)   { Invoke-Install; return }
    if ($Uninstall) { Invoke-Uninstall; return }
    if ($Update)    { Invoke-YtDlpUpdate; return }

    Get-YtDlp | Out-Null
    if (-not $List) { Initialize-Ffmpeg | Out-Null }

    # A URL/search phrase on the command line means "do this one and exit".
    if ($Url) {
        $ok = Invoke-Input -Target $Url
        Show-Result
        if (-not $ok) { exit 1 }
        return
    }

    if ($Yes -or $Pick -or $Search) { SayErr 'No URL or search phrase given.'; exit 1 }

    # Otherwise stay open and keep taking links.
    while ($true) {
        SayRule
        $answer = $null
        try { $answer = Read-Host '  Paste a video address or search YouTube (q to quit)' }
        catch { break }             # stdin went away
        if ($null -eq $answer) { break }

        $answer = $answer.Trim().Trim('"').Trim("'")
        if (-not $answer) { continue }
        if ($answer -eq 'q' -or $answer -eq 'quit' -or $answer -eq 'exit') { break }

        try {
            $null = Invoke-Input -Target $answer
            Show-Result
        }
        catch {
            SayErr $_.Exception.Message
        }
    }

    Say ''
    Say 'Bye.' DarkGray
}

try { Main }
catch { SayErr $_.Exception.Message; exit 1 }
