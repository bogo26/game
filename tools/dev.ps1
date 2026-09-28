# Windows version of tools/dev.sh, with the same commands. Start it with tools\dev.cmd,
# which works from PowerShell or cmd whatever the script execution policy is.
$Usage = @'
Developer helper for Windows.
  tools\dev.cmd                     run the game
  tools\dev.cmd import              re-import assets / rebuild class cache
  tools\dev.cmd test [--filter=x]   run the headless test suite
  tools\dev.cmd run [scene] [...]   run the game (or a scene); re-imports first if needed
  tools\dev.cmd editor              open the Godot editor
  tools\dev.cmd stress [...]        run the horde stress test
  tools\dev.cmd export [mac|win]    export release builds into build\ (needs export templates)
Set GODOT to the Godot .exe to override discovery.
'@

$Root = Split-Path -Parent $PSScriptRoot
$Stamp = Join-Path $Root '.godot\dev_import_stamp'

function Find-Godot {
    if ($env:GODOT) { return $env:GODOT }
    foreach ($name in 'godot', 'godot4') {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    # An unzipped download, on its own or in the folder Extract All makes for it; newest version first.
    $dirs = $env:ProgramFiles, "$env:LOCALAPPDATA\Programs", "$env:USERPROFILE\Downloads" | Where-Object { $_ -and (Test-Path $_) }
    Get-ChildItem -Path $dirs -Filter 'Godot_v4*_win64.exe' -File -Recurse -Depth 1 -ErrorAction SilentlyContinue |
        Sort-Object { if ($_.Name -match '^Godot_v(\d+(\.\d+)+)') { [version]$Matches[1] } } -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

$Godot = Find-Godot
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    [Console]::Error.WriteLine('Godot not found. Set GODOT to the Godot .exe, e.g. $env:GODOT = "C:\Godot\Godot_v4.7.2-stable_win64.exe"')
    exit 1
}
# The _console build waits for Godot to exit and prints to this terminal. The plain build
# returns at once unless its output is captured, so without a _console build it gets piped.
$ConsoleBuild = $Godot -replace '(?<!_console)\.exe$', '_console.exe'
if (Test-Path -LiteralPath $ConsoleBuild -PathType Leaf) { $Godot = $ConsoleBuild }
$Waits = $Godot -like '*_console.exe'

function Invoke-Godot([string[]]$GodotArgs, [switch]$Quiet) {
    if ($Quiet) { & $Godot @GodotArgs *> $null }
    elseif ($Waits) { & $Godot @GodotArgs }
    else { & $Godot @GodotArgs | Out-Host }
}

# Godot keeps the script class list and imported assets in .godot/, which isn't in git, and
# only the editor (or --import) refreshes them; see tools/dev.sh. run and stress re-import
# when class names or assets changed since the last import.
function Get-ClassListHash {
    $lines = Get-ChildItem -Path $Root -Filter *.gd -File -Recurse |
        Where-Object { $_.FullName -notmatch '\\(\.godot|\.git|build)\\' } |
        Select-String -Pattern '^(class_name|extends) ' -CaseSensitive |
        ForEach-Object { $_.Path.Substring($Root.Length) + ':' + $_.Line } |
        Sort-Object
    $bytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
    [BitConverter]::ToString([Security.Cryptography.SHA1]::Create().ComputeHash($bytes))
}

function Write-Stamp {
    New-Item -ItemType Directory -Force (Split-Path $Stamp) | Out-Null
    Set-Content -LiteralPath $Stamp -Value (Get-ClassListHash) -Encoding Ascii
}

function Import-Project([switch]$Quiet) {
    Invoke-Godot @('--headless', '--path', $Root, '--import') -Quiet:$Quiet
    if ($LASTEXITCODE -eq 0) { Write-Stamp }
}

function Import-IfStale {
    if (Test-Path -LiteralPath $Stamp) {
        $since = (Get-Item -LiteralPath $Stamp).LastWriteTimeUtc
        $newAsset = Get-ChildItem -Path (Join-Path $Root 'assets') -File -Recurse |
            Where-Object { $_.LastWriteTimeUtc -gt $since } | Select-Object -First 1
        if (-not $newAsset -and (Get-Content -LiteralPath $Stamp -TotalCount 1) -eq (Get-ClassListHash)) { return }
    }
    [Console]::Error.WriteLine('Scripts or assets changed since the last import: re-importing the project...')
    Import-Project -Quiet
}

$Command = if ($args.Count) { $args[0] } else { 'run' }
$Rest = @($args | Select-Object -Skip 1)

switch ($Command) {
    'import' {
        Import-Project
    }
    'test' {
        Import-Project -Quiet
        Invoke-Godot (@('--headless', '--path', $Root, '-s', 'res://tests/run_tests.gd', '--') + $Rest)
    }
    'run' {
        Import-IfStale
        Invoke-Godot (@('--path', $Root) + $Rest)
    }
    'editor' {
        Invoke-Godot (@('--path', $Root, '--editor') + $Rest)
    }
    'stress' {
        Import-IfStale
        Invoke-Godot (@('--path', $Root, 'res://tools/stress_test.tscn', '--') + $Rest)
    }
    'export' {
        $target = if ($Rest.Count) { $Rest[0] } else { 'all' }
        Import-Project -Quiet
        $status = 0
        if ($target -in 'all', 'mac') {
            New-Item -ItemType Directory -Force (Join-Path $Root 'build\macos') | Out-Null
            Invoke-Godot @('--headless', '--path', $Root, '--export-release', 'macOS', (Join-Path $Root 'build\macos\HordeCrawler.zip'))
            if ($LASTEXITCODE -ne 0) { $status = 1 }
        }
        if ($target -in 'all', 'win') {
            New-Item -ItemType Directory -Force (Join-Path $Root 'build\windows') | Out-Null
            Invoke-Godot @('--headless', '--path', $Root, '--export-release', 'Windows Desktop', (Join-Path $Root 'build\windows\HordeCrawler.exe'))
            if ($LASTEXITCODE -ne 0) { $status = 1 }
        }
        Get-ChildItem -Path (Join-Path $Root 'build') -File -Recurse -ErrorAction SilentlyContinue | Out-Host
        exit $status
    }
    default {
        Write-Host $Usage
        exit 1
    }
}
exit $LASTEXITCODE
