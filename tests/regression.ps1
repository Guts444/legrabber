#Requires -Version 5.1
<#[Run with both Windows PowerShell and pwsh; no network or media downloads.]#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'legrabber.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
foreach ($definition in $functions) { . ([scriptblock]::Create($definition.Extent.Text)) }

$Script:Root = Split-Path -Parent $PSScriptRoot
$Script:PlaylistActivity = 'Fixture playlist'
$Script:Fixture = Join-Path $PSScriptRoot 'native-fixture.cmd'
$Script:TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('legrabber-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $Script:TempRoot
$Script:Failures = @()
$Script:Passed = 0
$Script:Messages = @()
$Script:CapturedArgs = @()
$Script:TempDirs = @()
function Say { param([string]$Text, [string]$Color) $Script:Messages += $Text }
function SayWarn { param([string]$Text) $Script:Messages += $Text }
function SayErr { param([string]$Text) $Script:Messages += $Text }
function SayGood { param([string]$Text) $Script:Messages += $Text }
function SayHead { param([string]$Text) $Script:Messages += $Text }
function Get-YtDlp { return $Script:Fixture }
function Assert { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Contains { param($Actual, [string]$Expected) Assert (($Actual -join "`n") -like "*$Expected*") "Expected '$Expected' in: $($Actual -join ' | ')" }
function Run-Test {
    param([string]$Name, [scriptblock]$Action)
    $Script:Messages = @()
    $Script:CapturedArgs = @()
    $Script:DownloadCalled = $false
    $Url = $null; $Out = $Script:TempRoot; $Quality = $null; $Audio = $false
    $AudioFormat = 'original'; $Browser = $null; $Client = $null
    $Playlist = $false; $Subs = $false; $List = $false; $Yes = $false
    $Search = $false; $Pick = 0
    # Extras added after v1.0.1. Reset here or a previous test leaks them in.
    $Cookies = $null; $SubLangs = $null; $Batch = $null; $Archive = $false
    $Chapters = $false; $Tags = $false; $Thumb = $false; $KeepMtime = $false
    $Retries = 10; $FragmentRetries = 3; $LimitRate = $null
    $Sleep = 0; $SleepRequests = 0; $SocketTimeout = 20
    try { & $Action; $Script:Passed++; Write-Host "PASS $Name" -ForegroundColor Green }
    catch { $Script:Failures += "$Name : $($_.Exception.Message)"; Write-Host "FAIL $Name : $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber) :: $($_.InvocationInfo.Line.Trim())" -ForegroundColor Red }
}
function Arg-Value { param([string]$Name) $index = [array]::IndexOf($Script:CapturedArgs, $Name); if ($index -lt 0) { return $null }; return $Script:CapturedArgs[$index + 1] }
# Value that follows a flag in an argument list the test captured itself.
function Pair-Value { param([string[]]$List, [string]$Name) $index = [array]::IndexOf($List, $Name); if ($index -lt 0) { return $null }; return $List[$index + 1] }
# Temp files for the new checks stay independent of the suite's shared temp root,
# and are removed by the outer finally block.
function New-TestDir {
    param([string]$Tag)
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('legrabber-' + $Tag + '-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $dir
    $Script:TempDirs += $dir
    return $dir
}

try {
    Run-Test 'Spotify track IDs accept canonical localized embed and desktop links' {
        $id='0j2T0R9dR9qdJYsB7ciXhf'
        foreach ($text in @("https://open.spotify.com/track/$id`?si=tracking", "open.spotify.com/intl-pt/track/$id", "https://open.spotify.com/embed/track/$id/", "spotify:track:$id")) {
            Assert (Test-SpotifyInput $text) "Spotify input was missed: $text"
            Assert ((Get-SpotifyTrackId $text) -ceq $id) "Spotify track ID changed: $text"
        }
    }
    Run-Test 'Spotify rejects unsupported links and lookalike hosts' {
        $id='0j2T0R9dR9qdJYsB7ciXhf'
        foreach ($text in @("https://open.spotify.com/album/$id", "https://open.spotify.com/playlist/$id", 'https://open.spotify.com/track/short', 'https://spotify.link/short', "https://open.spotify.com.evil.test/track/$id", "https://evil.test/track/$id", "spotify:album:$id")) {
            Assert ($null -eq (Get-SpotifyTrackId $text)) "Unsupported track ID accepted: $text"
        }
        Assert (-not (Test-SpotifyInput "https://open.spotify.com.evil.test/track/$id")) 'Lookalike host treated as Spotify'
    }
    Run-Test 'Spotify metadata keeps track title and all artists without using playback fields' {
        $id='0j2T0R9dR9qdJYsB7ciXhf'
        $html='<script type="application/json" id="__NEXT_DATA__">{"props":{"pageProps":{"state":{"data":{"entity":{"type":"track","id":"0j2T0R9dR9qdJYsB7ciXhf","title":"Fixture Song","artists":[{"name":"Artist One"},{"name":"Artist Two"},{"name":"Artist One"}],"audioPreview":{"url":"https://example.invalid/never-download"}}}}}}}</script>'
        $track=ConvertFrom-SpotifyEmbed -Html $html -TrackId $id
        Assert ($track.Title -eq 'Fixture Song') 'Spotify title changed'
        Assert ($track.Artists.Count -eq 2) 'Spotify featured artists lost or duplicated'
        Assert ($track.Query -eq 'Artist One, Artist Two Fixture Song') 'Spotify search query is not artist plus title'
        Assert ($null -eq $track.audioPreview) 'Spotify playback data escaped metadata normalization'
    }
    Run-Test 'Spotify metadata parses Unicode cleans controls and accepts alternate attributes' {
        $html="<script id='__NEXT_DATA__' type='application/json'>"+'{"props":{"pageProps":{"state":{"data":{"entity":{"type":"track","id":"0j2T0R9dR9qdJYsB7ciXhf","name":"C\u00e9u\u001b Azul","artists":[{"name":"Charlie Brown Jr."}]}}}}}}</script>'
        $track=ConvertFrom-SpotifyEmbed -Html $html -TrackId '0j2T0R9dR9qdJYsB7ciXhf'
        Assert ($track.Title -eq ('C'+[char]0x00e9+'u  Azul')) 'Unicode title or control cleanup failed'
        Assert ($track.Query -like 'Charlie Brown Jr.*') 'Spotify title fallback lost artist'
    }
    Run-Test 'Spotify missing malformed and mismatched metadata fails safely' {
        $id='0j2T0R9dR9qdJYsB7ciXhf'
        $valid='{"props":{"pageProps":{"state":{"data":{"entity":{"type":"track","id":"0j2T0R9dR9qdJYsB7ciXhf","title":"Fixture","artists":[{"name":"Artist"}]}}}}}}'
        foreach ($html in @('<html>Not found</html>', '<script id="__NEXT_DATA__">invalid JSON</script>', ('<script id="__NEXT_DATA__">'+($valid -replace $id,'1j2T0R9dR9qdJYsB7ciXhf')+'</script>'), ('<script id="__NEXT_DATA__">'+($valid -replace '"name":"Artist"','"name":""')+'</script>'))) {
            $rejected=$false
            try { $null=ConvertFrom-SpotifyEmbed -Html $html -TrackId $id } catch { $rejected=$true }
            Assert $rejected 'Incomplete or wrong-track metadata was accepted'
        }
    }
    Run-Test 'Spotify metadata request uses canonical HTTPS and handles network failure' {
        function Invoke-WebRequest {
            param($Uri,$TimeoutSec,$MaximumRedirection,$Headers,[switch]$UseBasicParsing)
            $Script:SpotifyRequest=$Uri
            throw 'fixture network failure'
        }
        $track=Get-SpotifyTrack -TrackId '0j2T0R9dR9qdJYsB7ciXhf'
        Assert ($null -eq $track) 'Spotify network failure returned metadata'
        Assert ($Script:SpotifyRequest -eq 'https://open.spotify.com/embed/track/0j2T0R9dR9qdJYsB7ciXhf') 'Spotify request used a user-supplied destination'
        Assert-Contains $Script:Messages 'Could not read the Spotify track'
        Assert-Contains $Script:Messages 'song title and artist'
    }
    Run-Test 'Spotify link enters YouTube selection and downloads only the selected match' {
        $Audio=$true; $Pick=2
        function Get-SpotifyTrack { param($TrackId) Assert ($TrackId -ceq '0j2T0R9dR9qdJYsB7ciXhf') 'Spotify lookup used wrong ID'; return [pscustomobject]@{Title='Stronger';Artists=@('Kanye West');Query='Kanye West Stronger'} }
        function Get-SearchResults { param($Query) $Script:SpotifyQuery=$Query; return [pscustomobject]@{Results=@(
            [pscustomobject]@{Title='First';Url='https://www.youtube.com/watch?v=abcdefghijk'},
            [pscustomobject]@{Title='Second';Url='https://www.youtube.com/watch?v=-abcdefghij'}
        )} }
        function Read-SearchIndex { throw 'Explicit Spotify Pick prompted' }
        function Invoke-One { param($Target) $Script:SelectedTarget=$Target; $Script:DownloadCalled=$true; Assert $Audio 'Spotify lost Audio option'; return $true }
        Assert (Invoke-Input 'https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf?si=tracking') 'Spotify matching flow failed'
        Assert ($Script:SpotifyQuery -eq 'Kanye West Stronger') 'Spotify URL rather than metadata was searched'
        Assert ($Script:SelectedTarget -eq 'https://www.youtube.com/watch?v=-abcdefghij') 'Spotify downloaded wrong match or original DRM URL'
        Assert-Contains $Script:Messages 'comes from YouTube'
    }
    Run-Test 'Spotify metadata failure clears stale results and never searches or downloads' {
        $Script:SavedPaths=@('C:\old.mp4'); $Script:DownloadOk=$true
        function Get-SpotifyTrack { return $null }
        function Get-SearchResults { throw 'Spotify metadata failure searched' }
        function Invoke-One { throw 'Spotify metadata failure downloaded' }
        Assert (-not (Invoke-Input 'spotify:track:0j2T0R9dR9qdJYsB7ciXhf')) 'Spotify metadata failure succeeded'
        Assert ($Script:SavedPaths.Count -eq 0 -and -not $Script:DownloadOk) 'Spotify metadata failure retained saved summary'
    }
    Run-Test 'Unattended Spotify requires Pick before metadata requests' {
        $Yes=$true
        function Get-SpotifyTrack { throw 'Unselected unattended Spotify requested metadata' }
        Assert (-not (Invoke-Input 'https://open.spotify.com/track/0j2T0R9dR9qdJYsB7ciXhf')) 'Unselected Spotify succeeded'
        Assert-Contains $Script:Messages '-Pick'
    }
    Run-Test 'Unsupported Spotify collection is rejected before extraction' {
        function Get-SpotifyTrack { throw 'Spotify album requested track metadata' }
        function Invoke-One { throw 'Spotify album reached DRM downloader' }
        Assert (-not (Invoke-Input 'https://open.spotify.com/album/0j2T0R9dR9qdJYsB7ciXhf')) 'Spotify album accepted'
        Assert-Contains $Script:Messages 'full Spotify track link'
    }
    Run-Test 'Input detection preserves links and recognizes search phrases' {
        foreach ($text in @('https://not a url', 'https://youtube.com/watch?v=fixture', 'x.com/user/status/123', 'youtu.be/-abcdefghij', 'www.example.com', 'ftp://example.com')) {
            Assert (Test-LinkInput $text) "Link became a search: $text"
        }
        foreach ($text in @('50 cent many men', 'AC/DC', 'hello', 'Céu Azul', 'Mr. Brightside')) {
            Assert (-not (Test-LinkInput $text)) "Search became a link: $text"
        }
    }
    Run-Test 'Native search metadata survives stderr and keeps ordered video results' {
        function Get-BaseArgs { return @() }
        $env:LEGRABBER_TEST_MODE = 'search'
        $info = Get-SearchResults 'fixture song'
        Assert ($info.Results.Count -eq 2) 'Search did not remove null, duplicate, or invalid entries'
        Assert ($info.Results[0].Title -eq 'First result') 'Search order changed'
        Assert ($info.Results[1].Url -eq 'https://www.youtube.com/watch?v=-abcdefghij') 'Leading-dash result URL changed'
        Assert ($info.Results[1].Channel -eq 'Second channel') 'Uploader fallback missing'
        Assert ($ErrorActionPreference -eq 'Stop') 'Search leaked native error preference'
    }
    Run-Test 'Search native failure stops before selection or downloading' {
        function Get-BaseArgs { return @() }
        $env:LEGRABBER_TEST_MODE = 'failure'
        function Read-SearchIndex { throw 'Search prompted after failure' }
        function Invoke-One { throw 'Search downloaded after failure' }
        Assert (-not (Invoke-Input 'fixture song')) 'Search native failure succeeded'
        Assert-Contains $Script:Messages 'Could not search YouTube'
        Assert-Contains $Script:Messages 'ERROR: fixture format unavailable'
    }
    Run-Test 'Search selection downloads only the chosen result' {
        function Get-SearchResults { return [pscustomobject]@{Results=@(
            [pscustomobject]@{Title='First';Url='https://youtube.com/watch?v=abcdefghijk'},
            [pscustomobject]@{Title='Second';Url='https://youtube.com/watch?v=-abcdefghij'}
        )} }
        function Read-SearchIndex { return 2 }
        function Invoke-One { param($Target) $Script:SelectedTarget=$Target; $Script:DownloadCalled=$true; return $true }
        Assert (Invoke-Input 'fixture song') 'Selected result failed'
        Assert ($Script:SelectedTarget -eq 'https://youtube.com/watch?v=-abcdefghij') 'Wrong result downloaded'
        Assert $Script:DownloadCalled 'Selection did not download'
    }
    Run-Test 'Search cancellation clears stale results and never downloads' {
        $Script:SavedPaths=@('C:\old.mp4'); $Script:DownloadOk=$true
        function Get-SearchResults { return [pscustomobject]@{Results=@([pscustomobject]@{Title='First';Url='https://youtube.com/watch?v=abcdefghijk'})} }
        function Read-SearchIndex { return -1 }
        function Invoke-One { throw 'Cancelled search downloaded' }
        Assert (Invoke-Input 'fixture song') 'Cancellation was treated as a failure'
        Assert ($Script:SavedPaths.Count -eq 0 -and -not $Script:DownloadOk) 'Search cancellation retained stale saved result'
    }
    Run-Test 'Empty successful search stops without a selection prompt' {
        function Get-SearchResults { return [pscustomobject]@{Results=@()} }
        function Read-SearchIndex { throw 'Empty search prompted' }
        function Invoke-One { throw 'Empty search downloaded' }
        Assert (-not (Invoke-Input 'fixture song')) 'Empty search succeeded'
        Assert-Contains $Script:Messages 'No videos found'
    }
    Run-Test 'Unattended search requires a deliberate result index' {
        $Yes=$true
        function Get-SearchResults { throw 'Unselected unattended search hit the network' }
        function Read-SearchIndex { throw 'Unattended search prompted' }
        Assert (-not (Invoke-Input 'fixture song')) 'Unselected unattended search succeeded'
        Assert-Contains $Script:Messages '-Pick'
    }
    Run-Test 'Pick skips only search selection and validates available result count' {
        $Yes=$true; $Pick=2; $Audio=$true
        function Get-SearchResults { return [pscustomobject]@{Results=@(
            [pscustomobject]@{Title='First';Url='https://youtube.com/watch?v=abcdefghijk'},
            [pscustomobject]@{Title='Second';Url='https://youtube.com/watch?v=-abcdefghij'}
        )} }
        function Read-SearchIndex { throw 'Explicit Pick prompted' }
        function Invoke-One { param($Target) Assert ($Audio -and $Yes) 'Selection lost download options'; $Script:SelectedTarget=$Target; return $true }
        Assert (Invoke-Input 'fixture song') 'Explicit Pick failed'
        Assert ($Script:SelectedTarget -like '*-abcdefghij') 'Explicit Pick downloaded wrong result'
        $Pick=3
        Assert (-not (Invoke-Input 'fixture song')) 'Out-of-range available result count succeeded'
        Assert-Contains $Script:Messages 'Only 2 result'
    }
    Run-Test 'Explicit Search overrides domain-like phrase and URLs stay direct' {
        $Search=$true; $Pick=1
        function Get-SearchResults { param($Query) $Script:CapturedQuery=$Query; return [pscustomobject]@{Results=@([pscustomobject]@{Title='First';Url='https://youtube.com/watch?v=abcdefghijk'})} }
        function Invoke-One { param($Target) $Script:SelectedTarget=$Target; return $true }
        Assert (Invoke-Input 'Mr.Brightside') 'Forced domain-like search failed'
        Assert ($Script:CapturedQuery -eq 'Mr.Brightside') 'Forced search changed query'
        $Search=$false; $Pick=0; $Script:CapturedQuery=$null
        Assert (Invoke-Input 'https://x.com/i/status/123') 'Direct URL failed'
        Assert ($null -eq $Script:CapturedQuery) 'Direct URL performed search'
        Assert ($Script:SelectedTarget -eq 'https://x.com/i/status/123') 'Direct URL changed'
        $Pick=1
        Assert (-not (Invoke-Input 'https://x.com/i/status/123')) 'URL accepted search-only Pick'
    }
    Run-Test 'Search menu rejects overflow and invalid values then accepts a number' {
        $Script:SearchAnswers=@('999999999999999999999999','b','0','4','2'); $Script:SearchAnswerIndex=0
        function Read-Host { $a=$Script:SearchAnswers[$Script:SearchAnswerIndex]; $Script:SearchAnswerIndex++; return $a }
        Assert ((Read-SearchIndex -Count 3) -eq 2) 'Search picker did not reprompt safely'
        Assert ($Script:SearchAnswerIndex -eq 5) 'Search picker accepted invalid input'
    }
    Run-Test 'Native success completes progress on this engine' {
        $env:LEGRABBER_TEST_MODE = 'success'
        $Script:ItemTotal = 17; $Script:ItemIndex = 17
        $display = @(Invoke-Download -ArgumentList @('fixture') -Platform youtube 6>&1)
        Assert $Script:DownloadOk 'Successful native exit was not successful'
        Assert ($Script:SavedPaths.Count -eq 1) 'Saved marker missing'
        Assert ($Script:ItemTotal -eq 0) 'Single download retained playlist progress state'
        Assert ($ErrorActionPreference -eq 'Stop') 'Native invocation leaked ErrorActionPreference'
        Assert (-not (($display -join "`n") -match '\[youtube:tab\]')) 'Extractor chatter with colon escaped noise filter'
    }
    Run-Test 'Native stderr failure preserves diagnostics and exit code' {
        $env:LEGRABBER_TEST_MODE = 'failure'
        Invoke-Download -ArgumentList @('fixture') -Platform youtube
        Assert (-not $Script:DownloadOk) 'Native failure was marked successful'
        Assert-Contains $Script:Messages 'yt-dlp exited with code 7'
        Assert-Contains $Script:Messages 'ERROR: fixture format unavailable'
        Assert (-not (($Script:Messages -join "`n") -match 'NativeCommandError|CategoryInfo|FullyQualifiedErrorId')) 'PowerShell wrapper garbage leaked into errors'
    }
    Run-Test 'Partial playlist keeps saved paths and reports failure' {
        $env:LEGRABBER_TEST_MODE = 'partial'
        Invoke-Download -ArgumentList @('fixture') -Platform youtube
        Assert (-not $Script:DownloadOk) 'Partial playlist returned a successful exit'
        Assert ($Script:SavedPaths.Count -eq 1) 'Partial playlist lost completed paths'
        Assert-Contains $Script:Messages 'ERROR: fixture second item unavailable'
    }
    Run-Test 'No completed files means failure even with native exit zero' {
        $env:LEGRABBER_TEST_MODE = 'empty'
        Invoke-Download -ArgumentList @('fixture') -Platform youtube
        Assert (-not $Script:DownloadOk) 'Empty native success was reported as saved'
        Assert-Contains $Script:Messages 'No files were finished'
    }
    Run-Test 'Postprocessing errors fail even when native exit zero' {
        $env:LEGRABBER_TEST_MODE = 'errorzero'
        Invoke-Download -ArgumentList @('fixture') -Platform youtube
        Assert (-not $Script:DownloadOk) 'Native zero exit hid ERROR diagnostic'
        Assert ($Script:SavedPaths.Count -eq 1) 'Error path lost finished files'
        Assert-Contains $Script:Messages 'ERROR: fixture postprocessing failed'
    }
    Run-Test '403 retries once and deduplicates completed paths' {
        $env:LEGRABBER_TEST_MODE = 'retry'
        $env:LEGRABBER_TEST_RETRY_STATE = Join-Path $Script:TempRoot 'retry-state'
        Invoke-Download -ArgumentList @('fixture') -Platform youtube
        Assert $Script:DownloadOk '403 recovery did not succeed'
        Assert ($Script:SavedPaths.Count -eq 1) 'Retry duplicated completed filenames'
        Assert-Contains $Script:Messages 'Retrying once'
    }
    Run-Test 'Info JSON survives native stderr on both engines' {
        $env:LEGRABBER_TEST_MODE = 'json'
        $info = Get-Info -CleanUrl 'https://example.com/video' -BaseArgs @()
        Assert ($info.id -eq 'fixture') 'stderr corrupted JSON parsing'
    }
    Run-Test 'Info extraction failure is friendly' {
        $env:LEGRABBER_TEST_MODE = 'failure'
        $info = Get-Info -CleanUrl 'https://example.com/video' -BaseArgs @()
        Assert ($null -eq $info) 'Failure produced usable info'
        Assert-Contains $Script:Messages 'ERROR: fixture format unavailable'
    }
    Run-Test 'Unreadable info JSON is friendly' {
        $env:LEGRABBER_TEST_MODE = 'badjson'
        $info = Get-Info -CleanUrl 'https://example.com/video' -BaseArgs @()
        Assert ($null -eq $info) 'Unreadable JSON produced info'
        Assert-Contains $Script:Messages 'unreadable'
    }
    Run-Test 'Native format listing failure preserves diagnostics' {
        $env:LEGRABBER_TEST_MODE = 'failure'
        $ok = Show-FormatList -CleanUrl 'https://x.com/i/status/123' -BaseArgs @()
        Assert (-not $ok) 'Format listing failure returned success'
        Assert-Contains $Script:Messages 'exit 7'
        Assert-Contains $Script:Messages 'ERROR: fixture format unavailable'
        Assert ($ErrorActionPreference -eq 'Stop') 'Listing leaked ErrorActionPreference'
    }
    Run-Test 'Malformed URLs reject cleanly' {
        foreach ($value in @('https://not a url', 'file:///C:/secret.txt', 'ftp://example.com/video', '')) {
            Assert ($null -eq (Repair-Url -Raw $value)) "Accepted malformed/unsupported URL '$value'"
        }
    }
    Run-Test 'Tracking repair preserves requested playlist and leading dash id' {
        $url = Repair-Url 'https://music.youtube.com/watch?v=-xbzGngfQEw&list=PL123&index=2&si=tracking'
        Assert ($url -eq 'https://music.youtube.com/watch?v=-xbzGngfQEw') 'Single video repair wrong'
        $url = Repair-Url 'https://music.youtube.com/watch?v=-xbzGngfQEw&list=PL123&index=2&si=tracking' -KeepPlaylist
        Assert ($url -eq 'https://music.youtube.com/watch?v=-xbzGngfQEw&list=PL123&index=2') 'Requested playlist lost'
        Assert (Test-PlaylistUrl (Repair-Url 'music.youtube.com/playlist?list=PL123&si=tracking')) 'Playlist URL lost list'
    }
    Run-Test 'Generic query arguments retain site meaning' {
        $url = Repair-Url 'https://example.com/watch?list=one&index=two&s=token&t=cursor&si=site-token&utm_source=tracking'
        Assert ($url -eq 'https://example.com/watch?list=one&index=two&s=token&t=cursor&si=site-token') 'Generic query arguments were removed'
    }
    Run-Test 'Download hashes accept valid bytes and reject mismatches' {
        $file = Join-Path $Script:TempRoot 'hash-fixture.bin'
        [IO.File]::WriteAllText($file, 'fixture bytes', [Text.Encoding]::ASCII)
        $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        Assert-DownloadHash -Path $file -Expected $digest.ToLowerInvariant()
        $rejected = $false
        try { Assert-DownloadHash -Path $file -Expected ('0' * 64) }
        catch { $rejected = $_.Exception.Message -match 'failed SHA-256' }
        Assert $rejected 'Mismatched download was accepted'
        $rejected = $false
        try { Assert-DownloadHash -Path $file -Expected 'not a checksum' }
        catch { $rejected = $_.Exception.Message -match 'valid SHA-256' }
        Assert $rejected 'Malformed publisher digest was accepted'
    }
    Run-Test 'Verified dependency install preserves old executable on mismatch' {
        $hashFile = Join-Path $Script:TempRoot 'dependency-bytes.bin'
        [IO.File]::WriteAllText($hashFile, 'new verified executable', [Text.Encoding]::ASCII)
        $Script:PublishedHash = (Get-FileHash -LiteralPath $hashFile -Algorithm SHA256).Hash
        $destination = Join-Path $Script:TempRoot 'mock-yt-dlp.exe'
        $Script:CorruptDependency = $false
        $Script:RequestedUris = @()
        function Invoke-RestMethod {
            return [pscustomobject]@{ tag_name='fixture-version'; assets=@(
                [pscustomobject]@{name='yt-dlp.exe'; browser_download_url='https://fixture.invalid/fixture-version/yt-dlp.exe'},
                [pscustomobject]@{name='yt-dlp_x86.exe'; browser_download_url='https://fixture.invalid/fixture-version/yt-dlp_x86.exe'},
                [pscustomobject]@{name='yt-dlp_arm64.exe'; browser_download_url='https://fixture.invalid/fixture-version/yt-dlp_arm64.exe'},
                [pscustomobject]@{name='SHA2-256SUMS'; browser_download_url='https://fixture.invalid/fixture-version/SHA2-256SUMS'}
            ) }
        }
        function Save-Url {
            param([string]$Uri, [string]$Destination)
            $Script:RequestedUris += $Uri
            if ($Uri -like '*/SHA2-256SUMS') {
                $lines = foreach ($name in @('yt-dlp.exe', 'yt-dlp_x86.exe', 'yt-dlp_arm64.exe')) { "$Script:PublishedHash *$name" }
                [IO.File]::WriteAllText($Destination, ($lines -join "`n"), [Text.Encoding]::ASCII)
            }
            else {
                $bytes = 'new verified executable'
                if ($Script:CorruptDependency) { $bytes = 'tampered executable' }
                [IO.File]::WriteAllText($Destination, $bytes, [Text.Encoding]::ASCII)
            }
        }
        Save-YtDlp -Destination $destination
        Assert ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $Script:PublishedHash) 'Valid dependency was not installed'
        Assert ($Script:RequestedUris.Count -eq 2) 'Unexpected dependency downloads'
        Assert (($Script:RequestedUris | Where-Object { $_ -notlike '*/fixture-version/*' }).Count -eq 0) 'Dependency assets were not pinned to the resolved release'
        $Script:CorruptDependency = $true
        $rejected = $false
        try { Save-YtDlp -Destination $destination }
        catch { $rejected = $_.Exception.Message -match 'failed SHA-256' }
        Assert $rejected 'Tampered dependency was installed'
        Assert ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $Script:PublishedHash) 'Mismatch replaced the working executable'
        $leftovers = @(Get-ChildItem -LiteralPath $Script:TempRoot | Where-Object { $_.Name -like 'mock-yt-dlp.exe.*' })
        Assert ($leftovers.Count -eq 0) 'Dependency temporary files were left behind'
    }
    Run-Test 'Folder names avoid Windows reserved devices and trailing dots' {
        foreach ($value in @('CON', 'NUL.txt', 'COM1', 'LPT9.wav')) {
            Assert ((Get-SafeName $value) -notmatch '^(CON|NUL|COM1|LPT9)(\.|$)') "Unsafe folder '$value'"
        }
        Assert ((Get-SafeName ('a' * 79 + '.x')) -notmatch '[. ]$') 'Truncation retained trailing dot/space'
    }
    Run-Test 'Audio menu best shortcut is zero' {
        function Read-Host { return 'b' }
        Assert ((Read-Index -Count 3) -eq 0) 'Best shortcut changed'
    }
    Run-Test 'Oversized numeric menu input reprompts' {
        $Script:PromptIndex = 0
        function Read-Host { $Script:PromptIndex++; if ($Script:PromptIndex -eq 1) { return '999999999999999999999' }; return 'b' }
        Assert ((Read-Index -Count 3) -eq 0) 'Overflow input did not allow reprompt'
    }

    # Keep the real download implementation for native tests above; scoped mocks
    # below inspect command construction without calling yt-dlp or ffmpeg.
    Run-Test 'Generic List reads formats and never downloads' {
        $List = $true
        $Script:Listed = $false
        function Get-Ff { return $null }
        function Show-FormatList { $Script:Listed = $true; return $true }
        function Invoke-Download { $Script:DownloadCalled = $true }
        $null = Invoke-One 'https://x.com/i/status/123'
        Assert $Script:Listed '-List did not list generic formats'
        Assert (-not $Script:DownloadCalled) '-List downloaded media'
    }
    Run-Test 'Noninteractive playlist lands inside title folder' {
        $Yes = $true
        function Get-Ff { return $null }
        function Get-Info { return [pscustomobject]@{ title='Fixture playlist'; playlist_count=2; entries=@([pscustomobject]@{title='First';formats=@()}) } }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://music.youtube.com/playlist?list=PL123'
        Assert ((Arg-Value '-P') -eq (Join-Path $Out 'Fixture playlist')) 'Playlist did not use its named folder'
        Assert ($Script:CapturedArgs -contains '--yes-playlist') 'Playlist download not enabled'
    }
    Run-Test 'Playlist menu advances past unavailable first entries' {
        $Script:InspectedUrls = @()
        $Script:HeaderTitle = $null
        function Get-Ff { return 'C:\fixture\ffmpeg.exe' }
        function Get-Info {
            param([string]$CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist)
            if ($FlatPlaylist) {
                return [pscustomobject]@{ title='Accessible playlist'; playlist_count=3; entries=@(
                    [pscustomobject]@{ title='Private first'; availability='private'; url='private-id' },
                    [pscustomobject]@{ title='Deleted next'; availability='public'; url='deleted-id' },
                    [pscustomobject]@{ title='Playable third'; availability='public'; url='playable-id' }
                ) }
            }
            $Script:InspectedUrls += $CleanUrl
            if ($CleanUrl -like '*deleted-id') { return $null }
            return [pscustomobject]@{title='Playable third'; duration=1; formats=@(
                [pscustomobject]@{format_id='18'; ext='mp4'; height=480; fps=30; vcodec='avc1'; acodec='mp4a'; filesize=100}
            )}
        }
        function Show-Header { param($Info) $Script:HeaderTitle = $Info.title }
        function Show-VideoTable {}
        function Read-Kind { return 'video' }
        function Read-Index { return 1 }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true; $Script:DownloadCalled = $true }
        $ok = Invoke-One 'https://music.youtube.com/playlist?list=PL123'
        Assert $ok 'Playlist with later playable items failed'
        Assert $Script:DownloadCalled 'Playable playlist did not download'
        Assert ($Script:HeaderTitle -eq 'Playable third') 'Menu did not use a playable item'
        Assert ($Script:InspectedUrls.Count -eq 2) 'Known private item was inspected or fallback scan stopped early'
        Assert ($Script:CapturedArgs -contains '--no-abort-on-error') 'Playlist lost continuation with failure exit status'
    }
    Run-Test 'Original audio without ffmpeg avoids postprocessors' {
        $Audio = $true; $Yes = $true
        function Get-Ff { return $null }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://youtube.com/watch?v=fixture'
        foreach ($flag in @('--embed-metadata', '--embed-thumbnail', '-x', '--remux-video')) { Assert (-not ($Script:CapturedArgs -contains $flag)) "Missing ffmpeg still enabled $flag" }
    }
    Run-Test 'Audio conversion without ffmpeg fails before download' {
        $Audio = $true; $AudioFormat = 'mp3'; $Yes = $true
        function Get-Ff { return $null }
        function Invoke-Download { $Script:DownloadCalled = $true }
        $ok = Invoke-One 'https://youtube.com/watch?v=fixture'
        Assert (-not $ok) 'Unavailable conversion succeeded'
        Assert (-not $Script:DownloadCalled) 'Unavailable conversion started download'
        Assert-Contains $Script:Messages 'ffmpeg'
    }
    Run-Test 'Video quality without ffmpeg selects a combined stream' {
        $Yes = $true; $Quality = '720'
        function Get-Ff { return $null }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://youtube.com/watch?v=fixture'
        Assert ((Arg-Value '-f') -eq 'b[height<=720]') 'No-ffmpeg quality requested a merge'
    }
    Run-Test 'Interactive video without ffmpeg offers combined streams only' {
        function Get-Ff { return $null }
        function Get-Info { return [pscustomobject]@{title='Fixture';duration=1;formats=@(
            [pscustomobject]@{format_id='137';ext='mp4';height=1080;fps=30;vcodec='avc1';acodec='none';filesize=100},
            [pscustomobject]@{format_id='22';ext='mp4';height=480;fps=30;vcodec='avc1';acodec='mp4a';filesize=100}
        )} }
        function Show-Header {}
        function Show-VideoTable {}
        function Read-Kind { return 'video' }
        function Read-Index { return 1 }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://youtube.com/watch?v=fixture'
        Assert ((Arg-Value '-f') -eq '22') 'No-ffmpeg menu selected a separate video stream or required a merge'
    }
    Run-Test 'Subtitle embedding without ffmpeg fails before download' {
        $Yes = $true; $Subs = $true
        function Get-Ff { return $null }
        function Invoke-Download { $Script:DownloadCalled = $true }
        $ok = Invoke-One 'https://youtube.com/watch?v=fixture'
        Assert (-not $ok) 'Unavailable subtitle embedding succeeded'
        Assert (-not $Script:DownloadCalled) 'Unavailable subtitle embedding started download'
        Assert-Contains $Script:Messages 'Embedding subtitles needs ffmpeg'
    }
    Run-Test 'Best audio shortcut keeps original stream' {
        function Get-Ff { return 'C:\fixture\ffmpeg.exe' }
        function Get-Info { return [pscustomobject]@{ title='Fixture'; duration=1; formats=@() } }
        function Get-VideoChoices { return @() }
        function Get-AudioChoices { return @([pscustomobject]@{ Format=[pscustomobject]@{ext='webm';format_id='251'}; Convert=$null },[pscustomobject]@{ Format=$null; Convert='m4a' }) }
        function Show-Header {}
        function Show-AudioTable {}
        function Read-Kind { return 'audio' }
        function Read-Index { return 0 }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://youtube.com/watch?v=fixture'
        Assert ((-not ($Script:CapturedArgs -contains '--audio-format')) -or ((Arg-Value '--audio-format') -eq 'best')) 'Best audio selected converted last row'
        Assert ($Script:CapturedArgs -contains '-f') 'Best audio has no stream selector'
    }
    Run-Test 'WebM audio does not request incompatible thumbnail embedding' {
        $Audio = $true; $Yes = $true
        function Get-Ff { return 'C:\fixture\ffmpeg.exe' }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $null = Invoke-One 'https://youtube.com/watch?v=fixture'
        $safe = -not ($Script:CapturedArgs -contains '--embed-thumbnail')
        $safe = $safe -or ($Script:CapturedArgs -contains '--remux-video') -or ((Arg-Value '-f') -match '^ba\[ext=m4a\]')
        Assert $safe 'Best stream may be WebM but thumbnail embedding is unconditional'
    }
    Run-Test 'ffmpeg failures get an actionable local hint' {
        Show-FailureHint -Platform youtube -ErrText 'ERROR: ffmpeg not found. Please install or provide the path using --ffmpeg-location'
        Assert-Contains $Script:Messages 'ffmpeg'
        Assert (-not (($Script:Messages -join "`n") -match '-Browser')) 'Missing ffmpeg blamed browser authentication'
    }
    Run-Test 'Conversion cover art is limited to supported containers' {
        function Get-Ff { return 'C:\fixture\ffmpeg.exe' }
        foreach ($format in @('mp3', 'm4a', 'flac', 'opus')) {
            $argsForAudio = @(Get-AudioArgs -Format $format)
            Assert ($argsForAudio -contains '--embed-thumbnail') "$format lost supported cover art"
            $index = [array]::IndexOf($argsForAudio, '--audio-format')
            Assert ($argsForAudio[$index + 1] -eq $format) "$format conversion selector is wrong"
        }
        $argsForAudio = @(Get-AudioArgs -Format wav)
        Assert (-not ($argsForAudio -contains '--embed-thumbnail')) 'WAV requested unsupported cover art'
    }
    Run-Test 'Filename budget contracts for nested output folders' {
        $short = [int](Get-FilenameLimit -Directory 'C:\short')
        $long = [int](Get-FilenameLimit -Directory ('C:\' + ('a' * 100)))
        Assert ($short -gt $long) 'Nested path did not shorten filename limit'
        Assert ($long + 104 + 35 -le 240) 'Filename budget exceeds path allowance'
        $rejected = $false
        try { $null = Get-FilenameLimit -Directory ('C:\' + ('a' * 210)) }
        catch { $rejected = $_.Exception.Message -match 'shorter folder' }
        Assert $rejected 'Impossible output path was not rejected'
    }
    Run-Test 'Video sizes add separate audio only to video-only rows' {
        $info = [pscustomobject]@{formats=@(
            [pscustomobject]@{format_id='video';ext='mp4';height=720;fps=30;vcodec='avc1';acodec='none';filesize=100},
            [pscustomobject]@{format_id='combined';ext='mp4';height=480;fps=30;vcodec='avc1';acodec='mp4a';filesize=100},
            [pscustomobject]@{format_id='audio';ext='m4a';vcodec='none';acodec='mp4a';filesize=10;abr=128}
        )}
        $rows = @(Get-VideoChoices -Info $info)
        Assert ($rows.Count -eq 2) 'Video rows missing'
        Assert (($rows | Where-Object {$_.Height -eq 720}).Size -eq 110) 'Separate audio was omitted from video-only estimate'
        Assert (($rows | Where-Object {$_.Height -eq 480}).Size -eq 100) 'Combined stream counted its audio twice'
    }
    Run-Test 'Network resilience arguments are explicit and survive the base argument list' {
        $base = @(Get-NetworkArgs)
        Assert ((Pair-Value $base '--retries') -eq '10') 'Default retry count missing or wrong'
        Assert ((Pair-Value $base '--fragment-retries') -eq '3') 'Default fragment retry count missing'
        Assert ((Pair-Value $base '--socket-timeout') -eq '20') 'Default socket timeout missing'
        Assert ($base -contains '--no-mtime') 'Default did not keep the local timestamp'
        Assert (-not ($base -contains '--limit-rate')) 'Default capped the download rate'

        $Retries = 25; $FragmentRetries = 0; $SocketTimeout = 45; $LimitRate = '2M'; $Sleep = 5; $SleepRequests = 2
        $base = @(Get-NetworkArgs)
        Assert ((Pair-Value $base '--retries') -eq '25') 'Configured retry count lost'
        Assert (-not ($base -contains '--fragment-retries')) 'Zero fragment retries still passed a flag'
        Assert ((Pair-Value $base '--limit-rate') -eq '2M') 'Rate limit lost'
        Assert ((Pair-Value $base '--sleep-interval') -eq '5') 'Download interval lost'
        Assert ((Pair-Value $base '--sleep-requests') -eq '2') 'Request interval lost'

        $KeepMtime = $true
        Assert (-not (@(Get-NetworkArgs) -contains '--no-mtime')) 'KeepMtime still forced the local timestamp'
    }
    Run-Test 'Cookie files and subtitle languages reach the downloader' {
        $cookiesFile = Join-Path (New-TestDir 'cookies') 'cookies.txt'
        $Cookies = $cookiesFile
        $Browser = 'chrome'; $Subs = $true; $SubLangs = 'pt.*,en.*'
        $base = @(Get-BaseArgs)
        Assert ((Pair-Value $base '--cookies') -eq $cookiesFile) 'Cookies file not passed to the downloader'
        Assert ((Pair-Value $base '--cookies-from-browser') -eq 'chrome') 'Browser cookies were dropped'
        Assert ($base -contains '--no-mtime') 'Downloader command lost the network arguments'
        $embed = @(Get-EmbedArgs -Video)
        Assert ((Pair-Value $embed '--sub-langs') -eq 'pt.*,en.*') 'Subtitle language selection lost'
        Assert ($embed -contains '--write-subs' -and $embed -contains '--embed-subs') 'Subtitle embedding incomplete'
        Assert (-not ($embed -contains '--embed-chapters')) 'Chapters embedded without being asked for'
        Assert (-not ($embed -contains '--embed-thumbnail')) 'Cover art embedded without being asked for'
    }
    Run-Test 'Video extras stay opt-in and out of the audio path' {
        $Subs = $true
        $embed = @(Get-EmbedArgs -Video)
        Assert ((Pair-Value $embed '--sub-langs') -eq 'en.*,en') 'Default subtitle languages changed'
        Assert (-not ($embed -contains '--embed-metadata')) 'Video metadata embedded without being asked for'
        $Chapters = $true; $Tags = $true
        $embed = @(Get-EmbedArgs -Video)
        Assert ($embed -contains '--embed-chapters') 'Chapters flag lost'
        Assert ($embed -contains '--embed-metadata') 'Metadata flag lost'
        $audio = @(Get-EmbedArgs)
        Assert (-not ($audio -contains '--embed-chapters')) 'Chapters leaked into the audio path'
        Assert (-not ($audio -contains '--embed-metadata')) 'Audio embed args duplicated existing metadata handling'
    }
    Run-Test 'Archive state reaches the download command' {
        $Archive = $true
        $info = [pscustomobject]@{
            id = 'fixture'; title = 'Fixture'; duration = 60
            formats = @([pscustomobject]@{format_id='18';ext='mp4';height=360;fps=30;vcodec='avc1';acodec='mp4a';filesize=1000})
        }
        function Get-Ff { return 'C:\ffmpeg.exe' }
        function Get-Info { param($CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist) return $info }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $Quality = '360'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=abcdefghijk') 'Archived download run failed'
        Assert ($Script:CapturedArgs -contains '--download-archive') 'Archive flag not passed to the downloader'
        Assert ($Script:CapturedArgs -contains '--no-mtime') 'Network arguments missing from the download command'
    }
    Run-Test 'Archive is opt in and bare -Archive needs no value' {
        # What the prologue sets, so 'legrabber <url> -Archive' binds with no value.
        $PSDefaultParameterValues['*:Archive'] = $true
        $Archive = $true
        $info = [pscustomobject]@{
            id = 'fixture'; title = 'Fixture'; duration = 60
            formats = @([pscustomobject]@{format_id='18';ext='mp4';height=360;fps=30;vcodec='avc1';acodec='mp4a';filesize=1000})
        }
        function Get-Ff { return 'C:\ffmpeg.exe' }
        function Get-Info { param($CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist) return $info }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $Quality = '360'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=abcdefghijk') 'Bare -Archive run failed'
        Assert ($Script:CapturedArgs -contains '--download-archive') 'Bare -Archive was not honoured'
        $PSDefaultParameterValues.Remove('*:Archive')
    }
    Run-Test 'Archive stays off unless it is asked for' {
        $info = [pscustomobject]@{
            id = 'fixture'; title = 'Fixture'; duration = 60
            formats = @([pscustomobject]@{format_id='18';ext='mp4';height=360;fps=30;vcodec='avc1';acodec='mp4a';filesize=1000})
        }
        function Get-Ff { return 'C:\ffmpeg.exe' }
        function Get-Info { param($CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist) return $info }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $Quality = '360'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=abcdefghijk') 'Default download run failed'
        Assert (-not ($Script:CapturedArgs -contains '--download-archive')) 'Archive was enabled without being asked for'
    }
    Run-Test 'Archive identities come from the URL and never guess' {
        Assert ((Get-ArchiveId -CleanUrl 'https://www.youtube.com/watch?v=jNQXAC9IVRw' -Platform youtube) -eq 'jNQXAC9IVRw') 'YouTube watch id lost'
        Assert ((Get-ArchiveId -CleanUrl 'https://youtu.be/-abcdefghij' -Platform youtube) -eq '-abcdefghij') 'Short-link id lost'
        Assert ((Get-ArchiveId -CleanUrl 'https://www.youtube.com/playlist?list=PL123' -Platform youtube) -eq $null) 'Playlist produced an id'
        Assert ((Get-ArchiveId -CleanUrl 'https://x.com/user/status/2108405185542270976' -Platform x) -eq '2108405185542270976') 'X status id lost'
        Assert ((Get-ArchiveId -CleanUrl 'https://www.instagram.com/reel/Cx1y2z3A/' -Platform instagram) -eq 'Cx1y2z3A') 'Instagram reel id lost'
        Assert ((Get-ArchiveId -CleanUrl 'https://example.invalid/whatever' -Platform other) -eq $null) 'Unknown site produced an id'
    }
    Run-Test 'Archived items are skipped before any network work' {
        $dir = New-TestDir 'archive-skip'
        $Script:ArchiveFile = Join-Path $dir 'archive.txt'
        [IO.File]::WriteAllText($Script:ArchiveFile, "youtube jNQXAC9IVRw`r`n", (New-Object Text.UTF8Encoding($false)))
        $Archive = $true
        $info = [pscustomobject]@{ id='fixture'; title='Fixture'; duration=60; formats=@([pscustomobject]@{format_id='18';ext='mp4';height=360;fps=30;vcodec='avc1';acodec='mp4a';filesize=1000}) }
        function Get-Ff { return 'C:\ffmpeg.exe' }
        function Get-Info { param($CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist) throw 'Archived item requested metadata' }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) throw 'Archived item was downloaded again' }
        $Quality = '360'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=jNQXAC9IVRw') 'Archived item reported failure instead of a skip'
        Assert $Script:DownloadOk 'Archived skip was not counted as success'
        Assert-Contains $Script:Messages 'Already grabbed'
    }
    Run-Test 'Unarchived and archive-off runs still download' {
        $dir = New-TestDir 'archive-miss'
        $Script:ArchiveFile = Join-Path $dir 'archive.txt'
        [IO.File]::WriteAllText($Script:ArchiveFile, "youtube -abcdefghij`r`n", (New-Object Text.UTF8Encoding($false)))
        $info = [pscustomobject]@{ id='fixture'; title='Fixture'; duration=60; formats=@([pscustomobject]@{format_id='18';ext='mp4';height=360;fps=30;vcodec='avc1';acodec='mp4a';filesize=1000}) }
        function Get-Ff { return 'C:\ffmpeg.exe' }
        function Get-Info { param($CleanUrl, [string[]]$BaseArgs, [switch]$Playlist, [switch]$FlatPlaylist) return $info }
        function Invoke-Download { param([string[]]$ArgumentList, [string]$Platform) $Script:CapturedArgs = $ArgumentList; $Script:DownloadOk = $true }
        $Quality = '360'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=jNQXAC9IVRw') 'Unarchived item failed'
        Assert ($Script:CapturedArgs.Count -gt 0) 'Unarchived item did not download'
        $Script:CapturedArgs = @()
        $Script:ArchiveFile = Join-Path $dir 'missing.txt'
        Assert (Invoke-One 'https://www.youtube.com/watch?v=jNQXAC9IVRw') 'Missing archive file broke the download'
        Assert ($Script:CapturedArgs.Count -gt 0) 'Missing archive file skipped the download'
    }
    Run-Test 'Batch input keeps order, strips trim and skips blanks and comments' {
        $file = Join-Path (New-TestDir 'batch-input') 'links.txt'
        [IO.File]::WriteAllText($file, "# a comment`r`n`r`n  https://x.com/user/status/123  `r`n50 cent many men`r`n   `r`nhttps://youtu.be/-abcdefghij`r`n", (New-Object Text.UTF8Encoding($false)))
        $targets = @(Read-BatchTargets -LiteralPath $file)
        Assert ($targets.Count -eq 3) "Expected 3 targets, got $($targets.Count)"
        Assert ($targets[0] -eq 'https://x.com/user/status/123') 'Surrounding whitespace was kept'
        Assert ($targets[1] -eq '50 cent many men') 'Search phrase order changed'
        Assert ($targets[2] -eq 'https://youtu.be/-abcdefghij') 'Leading-dash link changed'
    }
    Run-Test 'Batch refuses a conflicting or unselectable run' {
        $dir = New-TestDir 'batch-refuse'
        $file = Join-Path $dir 'links.txt'
        [IO.File]::WriteAllText($file, "https://youtu.be/-abcdefghij`r`n", (New-Object Text.UTF8Encoding($false)))
        $List = $true
        Assert (-not (Invoke-Batch -LiteralPath $file)) 'Batch combined with -List'
        Assert-Contains $Script:Messages 'cannot be combined with -Batch'
        $List = $false; $Url = 'https://youtu.be/-abcdefghij'
        Assert (-not (Invoke-Batch -LiteralPath $file)) 'Batch combined with a URL'
        $Url = $null; $Search = $true
        Assert (-not (Invoke-Batch -LiteralPath $file)) 'Batch search ran without -Pick'
        Assert-Contains $Script:Messages 'needs -Pick'
        $Search = $false
        Assert (-not (Invoke-Batch -LiteralPath (Join-Path $dir 'missing.txt'))) 'Missing batch file accepted'
        Assert-Contains $Script:Messages 'Could not read the batch file'
    }
    Run-Test 'Batch visits every item and preserves order with a failure' {
        $file = Join-Path (New-TestDir 'batch-order') 'mixed.txt'
        # First item is an unsupported scheme, so it fails without any network.
        [IO.File]::WriteAllText($file, "ftp://example.invalid/video`r`nhttps://x.com/user/status/123`r`n", (New-Object Text.UTF8Encoding($false)))
        # A real bin folder, so the portable-ffmpeg probe behaves as it does on a
        # machine that has never installed ffmpeg.
        $Script:Bin = New-TestDir 'batch-bin'
        $env:LEGRABBER_TEST_MODE = 'success'
        Assert (-not (Invoke-Batch -LiteralPath $file)) 'Partially failed batch reported overall success'
        Assert-Contains $Script:Messages '1 downloaded, 1 failed'
        Assert-Contains $Script:Messages 'ftp://example.invalid/video'
        Assert-Contains $Script:Messages 'Saved to'
    }
}
finally {
    Remove-Item Env:LEGRABBER_TEST_MODE -ErrorAction SilentlyContinue
    Remove-Item Env:LEGRABBER_TEST_RETRY_STATE -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($Script:TempRoot)
    $expectedPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'legrabber-tests-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    foreach ($dir in $Script:TempDirs) {
        $path = [IO.Path]::GetFullPath($dir)
        if ($path.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $path) -like 'legrabber-*') {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "PowerShell $($PSVersionTable.PSVersion): $Script:Passed passed, $($Script:Failures.Count) failed."
if ($Script:Failures.Count) { exit 1 }
exit 0
