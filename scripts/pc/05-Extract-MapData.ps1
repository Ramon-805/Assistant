<#
    .SYNOPSIS
    Runs the four-stage map/vmap/mmap extraction against a PC copy of the client.

    .DESCRIPTION
    The extractors read the client's MPQ/data files to build the server's
    navigation data. They must run in this order, in the client folder, and the
    last stage takes hours:

        1. map-extractor      10-20 min
        2. vmap-extractor     20-40 min
        3. vmap-assembler     ~10 min
        4. mmap-generator     2-6 HOURS   <- start before bed

    Every stage is skipped if its output already exists, so an interrupted run
    picks up where it left off. Pass -Force to redo a stage anyway.

    Bots need mmaps to pathfind. Without them they spawn and stand still — the
    single most common bot failure.

    .PARAMETER Stage
    Run one stage only. Handy for redoing just the mmaps.

    .PARAMETER SkipMmaps
    Run stages 1-3 and stop. Gets you a playable server quickly; bots will not
    move until you come back and run stage 4.

    .EXAMPLE
    .\05-Extract-MapData.ps1 -Era classic

    .EXAMPLE
    .\05-Extract-MapData.ps1 -Era classic -Stage mmaps -Force
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('classic', 'tbc', 'wotlk')]
    [string]$Era,

    [ValidateSet('all', 'maps', 'vmaps', 'assemble', 'mmaps')]
    [string]$Stage = 'all',

    [switch]$SkipMmaps,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eraDef = Get-WowLabEra -Era $Era

$installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef
$sourceDir  = Get-WowLabSourceDir  -Config $config -EraDef $eraDef
$clientDir  = Get-WowLabClientDir  -Config $config -EraDef $eraDef

if (-not (Test-Path -LiteralPath $clientDir)) {
    throw ("PC client for $($eraDef.Name) not found at '$clientDir'. " +
           "Set Paths.Clients.$($eraDef.Key) in settings.psd1.")
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$logDir   = Join-Path $repoRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

# Extractor executables are named differently per core and have been renamed
# upstream over time, so each stage carries a candidate list rather than one
# hard-coded name.
$stages = if ($eraDef.Family -eq 'azerothcore') {
    @(
        @{ Id = 'maps';     Name = 'map-extractor';   Candidates = @('mapextractor.exe', 'map-extractor.exe');
           Args = @();                  Outputs = @('maps', 'dbc');  Estimate = '10-20 min' }
        @{ Id = 'vmaps';    Name = 'vmap-extractor';  Candidates = @('vmap4extractor.exe', 'vmap-extractor.exe');
           Args = @();                  Outputs = @('Buildings');     Estimate = '20-40 min' }
        @{ Id = 'assemble'; Name = 'vmap-assembler';  Candidates = @('vmap4assembler.exe', 'vmap-assembler.exe');
           Args = @('Buildings', 'vmaps'); Outputs = @('vmaps');      Estimate = '~10 min' }
        @{ Id = 'mmaps';    Name = 'mmap-generator';  Candidates = @('mmaps_generator.exe', 'mmap-generator.exe', 'MoveMapGen.exe');
           Args = @();                  Outputs = @('mmaps');         Estimate = '2-6 HOURS' }
    )
} else {
    @(
        @{ Id = 'maps';     Name = 'map-extractor';   Candidates = @('map-extractor.exe', 'mapextractor.exe');
           Args = @();                  Outputs = @('maps', 'dbc');  Estimate = '10-20 min' }
        @{ Id = 'vmaps';    Name = 'vmap-extractor';  Candidates = @('vmap-extractor.exe', 'vmapextractor.exe');
           Args = @();                  Outputs = @('Buildings');     Estimate = '20-40 min' }
        @{ Id = 'assemble'; Name = 'vmap-assembler';  Candidates = @('vmap-assembler.exe', 'vmapassembler.exe');
           Args = @('Buildings', 'vmaps'); Outputs = @('vmaps');      Estimate = '~10 min' }
        @{ Id = 'mmaps';    Name = 'mmap-generator';  Candidates = @('MoveMapGen.exe', 'mmap-generator.exe', 'movemap-generator.exe');
           Args = @();                  Outputs = @('mmaps');         Estimate = '2-6 HOURS' }
    )
}

if ($Stage -ne 'all') {
    $stages = @($stages | Where-Object { $_.Id -eq $Stage })
}
if ($SkipMmaps) {
    $stages = @($stages | Where-Object { $_.Id -ne 'mmaps' })
}

function Test-OutputPresent {
    param([string]$Dir)
    if (-not (Test-Path -LiteralPath $Dir)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $Dir -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
}

Write-Step "$($eraDef.Name) — extracting from $clientDir"
Write-Info "Extractor binaries are searched for under $installDir and $sourceDir"

$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($stg in $stages) {

    $exe = Resolve-ToolPath -Candidates $stg.Candidates -SearchDirs @($installDir, $sourceDir)
    if (-not $exe) {
        Write-Fail "$($stg.Name): none of $($stg.Candidates -join ', ') found."
        Write-Info "Build the extractors first (03-Build-Core.ps1 passes the tools flag), then re-run."
        exit 1
    }

    $outputPaths = $stg.Outputs | ForEach-Object { Join-Path $clientDir $_ }
    $allPresent  = -not ($outputPaths | Where-Object { -not (Test-OutputPresent $_) })

    if ($allPresent -and -not $Force) {
        Write-Ok "$($stg.Name): output already present ($($stg.Outputs -join ', ')) — skipping. Use -Force to redo."
        continue
    }

    # mmaps_generator needs the directory to exist before it will write into it.
    foreach ($out in $outputPaths) {
        if (-not (Test-Path -LiteralPath $out)) { New-Item -ItemType Directory -Path $out -Force | Out-Null }
    }

    $stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFile = Join-Path $logDir "$Era-$($stg.Id)-$stamp.log"

    Write-Step "$($stg.Name) — estimated $($stg.Estimate)"
    Write-Info "Binary: $exe"
    Write-Info "Log:    $logFile"
    if ($stg.Id -eq 'mmaps') {
        Write-Warn 'This is the long one. Leave it running — it is unattended from here.'
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Extractors must run with the client folder as the working directory:
    # they look for the MPQ/Data files relative to it.
    $procArgs = @{
        FilePath               = $exe
        WorkingDirectory       = $clientDir
        NoNewWindow            = $true
        Wait                   = $true
        RedirectStandardOutput = $logFile
        RedirectStandardError  = "$logFile.err"
        PassThru               = $true
    }
    if ($stg.Args.Count -gt 0) { $procArgs.ArgumentList = $stg.Args }

    $proc = Start-Process @procArgs
    $sw.Stop()

    if ($proc.ExitCode -ne 0) {
        Write-Fail "$($stg.Name) exited with code $($proc.ExitCode) after $([int]$sw.Elapsed.TotalMinutes) min."
        Write-Info "Check $logFile and $logFile.err"
        exit 1
    }

    $produced = foreach ($out in $outputPaths) {
        $count = (Get-ChildItem -LiteralPath $out -Recurse -File -ErrorAction SilentlyContinue).Count
        "$([System.IO.Path]::GetFileName($out)): $count files"
    }
    Write-Ok "$($stg.Name) finished in $([int]$sw.Elapsed.TotalMinutes) min — $($produced -join ', ')"
}

# ---------------------------------------------------------------------------
# Move the results next to the server binaries
# ---------------------------------------------------------------------------

Write-Step 'Moving extracted data next to the server binaries'

foreach ($dirName in @('dbc', 'maps', 'vmaps', 'mmaps', 'Cameras')) {
    $src = Join-Path $clientDir $dirName
    if (-not (Test-OutputPresent $src)) { continue }

    $dst = Join-Path $installDir $dirName
    if ((Test-Path -LiteralPath $dst) -and -not $Force) {
        Write-Info "$dirName already in the install dir — leaving it. Use -Force to replace."
        continue
    }

    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
    $count = (Get-ChildItem -LiteralPath $dst -Recurse -File).Count
    Write-Ok "$dirName -> $dst ($count files)"
}

$totalSw.Stop()
Write-Host ''
Write-Ok "Extraction done in $([int]$totalSw.Elapsed.TotalMinutes) minutes total."

if ($SkipMmaps) {
    Write-Warn 'mmaps were skipped — bots will spawn but not move until you run:'
    Write-Info "  .\05-Extract-MapData.ps1 -Era $Era -Stage mmaps"
}

Write-Host ''
Write-Info "Next: import the world database, then .\06-Set-RealmlistAddress.ps1 -Era $Era"
