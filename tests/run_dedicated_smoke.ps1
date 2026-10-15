# Isolated dedicated-server smoke test of batman_RadioSurvivor with the in-game test engine (RST, E01-T07).
# Everything lives in a new temporary cache folder: no existing cache, save, mod folder or source is changed, and
# nothing is written to the Steam Workshop folder (TooltipLib, required by batman_BeltRadio, is only read from it).
#
# Default (automatic): copies batman_BeltRadio (required mod, from the sibling repository Workshop/BeltRadio),
# batman_RadioSurvivor, batman_CharacterReputation and the development mod batman_RadioSurvivorTests into <cache>/mods, writes <cache>/Lua/batman_RadioSurvivor/tests/autorun.txt (one suite
# name or prefix per line, from -Filters), starts the server "rstest_smoke" (test save name: world suites allowed)
# in the background with a redirected stdin, waits for autorun-result.txt (written by RST_Server.lua when the run
# ends), prints the summary, sends "quit" to the server console and waits for the process to end (killed after
# -QuitTimeoutSec). The temporary cache is removed on success unless -KeepCache; it is kept (path printed) on failure.
# Exit codes: 0 = ok=true, 1 = suites failed (or no test selected), 2 = timeout, startup error or refused autorun.
#
# -Manual: former usage. Same cache layout and server, no autorun.txt, no waiting: the server runs in the
# foreground of this console; type "quit" to stop it. The cache is kept.
# -CacheDir <path> (with -Manual only): restarts the server on an existing cache printed by a former run
# (RS_SMOKE_CACHE=...), same world and same mod copies (nothing copied again): restart protocols (E03-T04).
#
#   powershell -ExecutionPolicy Bypass -File RadioSurvivor/tests/run_dedicated_smoke.ps1 [-Filters rst,rs.codec]
#       [-TimeoutSec 600] [-QuitTimeoutSec 90] [-KeepCache] [-Manual [-CacheDir <path>]]
param(
    [string[]]$Filters = @('rst'),
    [int]$TimeoutSec = 600,
    [int]$QuitTimeoutSec = 90,
    [switch]$KeepCache,
    [switch]$Manual,
    [string]$CacheDir = ''
)
$ErrorActionPreference = 'Stop'
if ($CacheDir -ne '' -and -not $Manual) {
    Write-Output 'ERROR: -CacheDir needs -Manual (the automatic run always starts from a new cache)'
    exit 2
}
# "-File" passes "-Filters a,b" as one string: split on commas.
$Filters = @($Filters | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
# Steam library holding the game: $env:PZ_STEAM_LIBRARY, else the libraries listed in libraryfolders.vdf (Steam folder
# from the registry), first one that contains ProjectZomboid. Same rule as tools/pz_paths.py.
function Find-PzSteamLib {
    if ($env:PZ_STEAM_LIBRARY) { return $env:PZ_STEAM_LIBRARY }
    $roots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
        $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($item -and $item.SteamPath) { $roots += $item.SteamPath }
        if ($item -and $item.InstallPath) { $roots += $item.InstallPath }
    }
    if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} 'Steam') }
    $libraries = @()
    foreach ($root in $roots) {
        $libraries += $root
        $vdf = Join-Path $root 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries += $m.Groups[1].Value.Replace('\\', '\')
            }
        }
    }
    foreach ($library in $libraries) {
        if (Test-Path -LiteralPath (Join-Path $library 'steamapps/common/ProjectZomboid')) { return $library }
    }
    return $null
}
$steamLib = Find-PzSteamLib
if (-not $steamLib) {
    Write-Output 'ERROR: ProjectZomboid not found: set PZ_STEAM_LIBRARY to the Steam library that holds it'
    exit 2
}
$gameRoot = if ($env:PZ_DIR) { $env:PZ_DIR } else { Join-Path $steamLib 'steamapps/common/ProjectZomboid' }
$serverName = 'rstest_smoke'
$projectRoot = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)

if ($CacheDir -ne '') {
    $cacheRoot = $CacheDir
    if (-not (Test-Path -LiteralPath (Join-Path $cacheRoot ('Server/' + $serverName + '.ini')))) {
        Write-Output ('ERROR: ' + $cacheRoot + ' is not a cache of this script (Server/' + $serverName + '.ini missing)')
        exit 2
    }
    Write-Output ('RS_SMOKE_CACHE=' + $cacheRoot + ' (reused)')
} else {
$cacheRoot = Join-Path ([IO.Path]::GetTempPath()) ('rs-dedicated-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $cacheRoot | Out-Null
$modsDir = Join-Path $cacheRoot 'mods'
New-Item -ItemType Directory -Path $modsDir, (Join-Path $cacheRoot 'Server') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'Contents/mods/batman_RadioSurvivor') -Destination $modsDir -Recurse
$reputationRoot = Join-Path (Split-Path $projectRoot -Parent) 'CharacterReputation/Contents/mods/batman_CharacterReputation'
Copy-Item -LiteralPath $reputationRoot -Destination $modsDir -Recurse
# Required mod (require=\batman_BeltRadio): without it the game does not load batman_RadioSurvivor at all.
$beltRadioRoot = Join-Path (Split-Path $projectRoot -Parent) 'BeltRadio/Contents/mods/batman_BeltRadio'
if (-not (Test-Path -LiteralPath (Join-Path $beltRadioRoot '42.21/mod.info'))) {
    Write-Output ('ERROR: required mod batman_BeltRadio not found: ' + $beltRadioRoot)
    Remove-Item -LiteralPath $cacheRoot -Recurse -Force
    exit 2
}
Copy-Item -LiteralPath $beltRadioRoot -Destination $modsDir -Recurse
# batman_BeltRadio requires TooltipLib (Workshop item 3694097672, subscribed): copied READ-ONLY from the Workshop
# folder into the temporary cache (the Workshop folder itself is never changed). Without it nothing of ours loads.
$tooltipRoot = Join-Path $steamLib 'steamapps/workshop/content/108600/3694097672/mods/TooltipLib'
if (-not (Test-Path -LiteralPath (Join-Path $tooltipRoot 'mod.info'))) {
    Write-Output ('ERROR: required mod TooltipLib not found: ' + $tooltipRoot)
    Remove-Item -LiteralPath $cacheRoot -Recurse -Force
    exit 2
}
Copy-Item -LiteralPath $tooltipRoot -Destination $modsDir -Recurse
Copy-Item -LiteralPath (Join-Path $projectRoot 'dev/batman_RadioSurvivorTests') -Destination $modsDir -Recurse
$config = @'
Public=false
UPnP=false
PauseEmpty=true
DefaultPort=17381
UDPPort=17382
MaxPlayers=2
Mods=\TooltipLib;\batman_BeltRadio;\batman_CharacterReputation;\batman_RadioSurvivor;\batman_RadioSurvivorTests
WorkshopItems=
Map=Muldraugh, KY
ChatStreams=s,r,a,w,y,sh,f,all
'@
[IO.File]::WriteAllText((Join-Path $cacheRoot ('Server/' + $serverName + '.ini')), $config, $utf8)
Write-Output ('RS_SMOKE_CACHE=' + $cacheRoot)
}

# Same Java options as the former manual script. This installation has older DLLs in natives/win64; the current
# root DLLs come first in java.library.path.
$javaArgs = @('-Djava.awt.headless=true', '-Dzomboid.steam=0', '--enable-native-access=ALL-UNNAMED',
    '--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED', '-XX:+UseZGC', '-XX:-CreateCoredumpOnCrash',
    '-XX:-OmitStackTraceInFastThrow', '-Xmx2048m', ('-XX:ErrorFile=' + $cacheRoot + '/java-error.log'),
    '-Djava.library.path=./;./natives/win64/;./natives/', '-cp', './;projectzomboid.jar', 'zombie.network.GameServer',
    ('-cachedir=' + $cacheRoot), '-nosteam', '-ip', '127.0.0.1', '-servername', $serverName,
    '-adminusername', 'rs_smoke_admin', '-adminpassword', 'local-smoke-only', '-disablelog=NetworkPacket')

if ($Manual) {
    Push-Location $gameRoot
    try {
        & './jre64/bin/java.exe' @javaArgs
    } finally {
        Pop-Location
    }
    exit $LASTEXITCODE
}

# ------------------------------------------------------------------ automatic run
$testsDir = Join-Path $cacheRoot 'Lua/batman_RadioSurvivor/tests'
New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
$autorun = @('# Written by run_dedicated_smoke.ps1: one suite name or dot-separated prefix per line.') + $Filters
[IO.File]::WriteAllText((Join-Path $testsDir 'autorun.txt'), (($autorun -join "`n") + "`n"), $utf8)
$resultFile = Join-Path $testsDir 'autorun-result.txt'
$stdoutLog = Join-Path $cacheRoot 'server-stdout.log'
$consoleLog = Join-Path $cacheRoot 'server-console.txt'

function Show-Tail([string]$path, [int]$count) {
    if (Test-Path -LiteralPath $path) {
        Write-Output ('--- last ' + $count + ' lines of ' + $path)
        Get-Content -LiteralPath $path -Tail $count | ForEach-Object { Write-Output ('    ' + $_) }
    } else {
        Write-Output ('--- missing: ' + $path)
    }
}

function Show-ModErrors {
    if (-not (Test-Path -LiteralPath $consoleLog)) { return }
    # Kahlua logs every error() as "ERROR: ... Lua((MOD:<mod name>)).<function>> Exception thrown", even when a
    # pcall catches it. Ignored:
    # - known load noise (AnimSets / actiongroups folders missing, AdvancedAnimator);
    # - the RST assertion signals raised on purpose by the development mod (dev/.../shared/RST/RST.lua): T:fail and
    #   T:skip raise a signal table, logged as "...).fail> Exception thrown" / "...).skip> Exception thrown" followed
    #   by "KahluaException: table 0x...". RST catches them and reports the test as FAIL / SKIP in
    #   autorun-result.txt (printed above), so a failed test is not lost;
    # - the error that T:fails catches on purpose in the function it was given ("...).fails> Exception thrown").
    # Only lines of the development mod ("batman_RadioSurvivor Tests (dev only)") are ignored, and only for these
    # three functions: any other error of our mods (main mod, or another function of the development mod) is shown.
    $devMod = [regex]::Escape('Lua((MOD:batman_RadioSurvivor Tests (dev only)))')
    $signalLine = '^ERROR:.*' + $devMod + '\.(fail|skip)> Exception thrown'
    $failsLine = '^ERROR:.*' + $devMod + '\.fails> Exception thrown'
    $hits = Select-String -LiteralPath $consoleLog -CaseSensitive -Context 0, 1 -Pattern '^ERROR.*batman_', '\[RS[^\]]*\].*ERROR' |
        Where-Object {
            $next = ''
            if ($_.Context -and $_.Context.PostContext.Count -gt 0) { $next = $_.Context.PostContext[0] }
            -not ($_.Line -match 'NoSuchFileException.*(AnimSets|actiongroups)' -or
                ($_.Line -cmatch $signalLine -and $next -match 'KahluaException: table 0x[0-9a-fA-F]+ ') -or
                $_.Line -cmatch $failsLine)
        }
    if ($hits) {
        Write-Output ('Lua errors mentioning our mods (' + @($hits).Count + ' line(s), first 20):')
        $hits | Select-Object -First 20 | ForEach-Object { Write-Output ('    ' + $_.Line.Trim()) }
    } else {
        Write-Output 'Lua errors mentioning our mods: none found in server-console.txt'
    }
}

$quoted = ($javaArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
# cmd keeps java's stdout/stderr in a file; java inherits the redirected stdin of cmd (server console).
$psi.Arguments = '/d /s /c ""' + $gameRoot + '/jre64/bin/java.exe" ' + $quoted + ' > "' + $stdoutLog + '" 2>&1"'
$psi.WorkingDirectory = $gameRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $true

$code = 2
$started = Get-Date
$proc = $null
try {
    # Windows PowerShell 5.1 (.NET Framework) has no ProcessStartInfo.StandardInputEncoding: Process.Start wraps the
    # stdin pipe in a StreamWriter using [Console]::InputEncoding and, by setting AutoFlush, writes that encoding's
    # preamble at once. With the console in code page 65001 this is a UTF-8 BOM, so the server read "<BOM>quit" and
    # answered "Unknown command". The input encoding is therefore set to UTF-8 without BOM only around Start (the
    # writer keeps its own copy), then restored.
    $previousInputEncoding = $null
    try {
        $previousInputEncoding = [Console]::InputEncoding
        [Console]::InputEncoding = $utf8
    } catch {
        Write-Output ('WARNING: console input encoding not changed: ' + $_.Exception.Message)
    }
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
    } finally {
        if ($previousInputEncoding -ne $null) {
            try { [Console]::InputEncoding = $previousInputEncoding } catch { }
        }
    }
    Write-Output ('server started (pid ' + $proc.Id + '), filters: ' + ($Filters -join ', ') + ', waiting up to ' + $TimeoutSec + ' s')
    $deadline = $started.AddSeconds($TimeoutSec)
    $complete = $false
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $resultFile) {
            $lines = @(Get-Content -LiteralPath $resultFile -Encoding UTF8)
            if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq 'RST-END') { $complete = $true; break }
        }
        if ($proc.HasExited) { break }
        Start-Sleep -Seconds 1
    }
    $elapsed = [int]((Get-Date) - $started).TotalSeconds
    if ($complete) {
        $first = $lines[0]
        Write-Output ('autorun finished after ' + $elapsed + ' s')
        Write-Output $first
        $lines | Where-Object { $_ -match '^(FAIL |ERROR|EMPTY)' } | Select-Object -First 40 | ForEach-Object { Write-Output ('    ' + $_) }
        if ($lines.Count -ge 2) { Write-Output $lines[$lines.Count - 2] }
        if ($first -match '^RST-RESULT ok=true ') {
            $code = 0
        } elseif ($first -match '^RST-RESULT ok=false .* reason=(.*)$' -and $Matches[1] -ne 'no test selected') {
            $code = 2
        } else {
            $code = 1
        }
    } elseif ($proc.HasExited) {
        Write-Output ('ERROR: the server stopped after ' + $elapsed + ' s without autorun-result.txt (exit code ' + $proc.ExitCode + ')')
    } else {
        Write-Output ('ERROR: no complete autorun-result.txt after ' + $TimeoutSec + ' s')
    }
} catch {
    Write-Output ('ERROR: server start failed: ' + $_.Exception.Message)
} finally {
    if ($proc -ne $null -and -not $proc.HasExited) {
        try {
            if ($proc.StandardInput.Encoding.GetPreamble().Length -gt 0) {
                # Fallback when the encoding could not be changed: the preamble is already in the pipe, so an empty
                # line keeps it away from the command.
                $proc.StandardInput.WriteLine('')
            }
            $proc.StandardInput.WriteLine('quit')
            $proc.StandardInput.Flush()
            Write-Output 'sent "quit" to the server console'
        } catch {
            Write-Output ('WARNING: "quit" not sent: ' + $_.Exception.Message)
        }
        if (-not $proc.WaitForExit($QuitTimeoutSec * 1000)) {
            Write-Output ('WARNING: server still running after ' + $QuitTimeoutSec + ' s, killing process tree ' + $proc.Id)
            & taskkill.exe /PID $proc.Id /T /F | Out-Null
            $proc.WaitForExit(15000) | Out-Null
            if ($code -eq 0) { $code = 2 }
        } else {
            Write-Output 'server stopped'
        }
    }
}

Show-ModErrors
if ($code -ne 0) {
    Show-Tail $stdoutLog 30
    Show-Tail $consoleLog 30
}
$total = [int]((Get-Date) - $started).TotalSeconds
if ($code -eq 0 -and -not $KeepCache) {
    Start-Sleep -Seconds 1
    try {
        Remove-Item -LiteralPath $cacheRoot -Recurse -Force
        Write-Output 'temporary cache removed'
    } catch {
        Write-Output ('WARNING: temporary cache not removed: ' + $cacheRoot + ' (' + $_.Exception.Message + ')')
    }
} else {
    Write-Output ('temporary cache kept: ' + $cacheRoot)
}
Write-Output ('RS_SMOKE_EXIT=' + $code + ' (' + $total + ' s)')
exit $code
