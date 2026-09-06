<#
    .SYNOPSIS
    Configures and builds a core with CMake + MSBuild, with playerbots enabled.

    .DESCRIPTION
    The single most commonly missed step in this whole project is building
    CMaNGOS without BUILD_PLAYERBOTS, which produces a working server with no
    bots and no error explaining why. This script always passes that flag for
    the CMaNGOS eras, and the AzerothCore equivalents for WotLK.

    Expect the first build to take a while — 20-60 minutes depending on the PC.

    .PARAMETER Clean
    Delete the build directory first. Use after changing CMake options.

    .EXAMPLE
    .\03-Build-Core.ps1 -Era classic

    .EXAMPLE
    .\03-Build-Core.ps1 -Era wotlk -Clean
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('classic', 'tbc', 'wotlk')]
    [string]$Era,

    [switch]$Clean,

    [ValidateSet('Release', 'RelWithDebInfo', 'Debug')]
    [string]$Configuration = 'Release',

    # Defaults to one job per logical core.
    [int]$Jobs = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config  = Get-WowLabConfig
$eraDef  = Get-WowLabEra -Era $Era

$sourceDir  = Get-WowLabSourceDir  -Config $config -EraDef $eraDef
$installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef
$buildDir   = Join-Path $sourceDir 'build'

if (-not (Test-Path -LiteralPath $sourceDir)) {
    throw "Source not found at '$sourceDir'. Run .\02-Clone-Sources.ps1 -Era $Era first."
}

$botDir = Join-Path $sourceDir ($eraDef.BotPath -replace '/', '\')
if (-not (Test-Path -LiteralPath $botDir)) {
    throw ("Playerbots module missing at '$botDir'. Run .\02-Clone-Sources.ps1 -Era $Era — " +
           "building without it gives you a server with no bots.")
}

if ($Jobs -le 0) { $Jobs = [Environment]::ProcessorCount }

if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
    Write-Step "Removing $buildDir"
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
New-Item -ItemType Directory -Path $installDir -Force | Out-Null

# Per-family CMake options. Only flags whose names are stable upstream are set
# here; anything else is left at its default rather than guessed at.
$cmakeOptions = switch ($eraDef.Family) {
    'cmangos' {
        @(
            '-DBUILD_PLAYERBOTS=ON'      # the flag everyone forgets
            '-DBUILD_EXTRACTORS=ON'      # map/vmap/mmap tools, needed for step 05
        )
    }
    'azerothcore' {
        @(
            '-DTOOLS_BUILD=all'          # AzerothCore's extractor equivalent
            '-DSCRIPTS=static'
            '-DMODULES=static'           # builds mod-playerbots into worldserver
        )
    }
    default { throw "Unknown core family '$($eraDef.Family)'." }
}

Write-Step "$($eraDef.Name) — CMake configure"
Write-Info "Source:  $sourceDir"
Write-Info "Build:   $buildDir"
Write-Info "Install: $installDir"
Write-Info "Options: $($cmakeOptions -join ' ')"

$configureArgs = @(
    '-S', $sourceDir
    '-B', $buildDir
    '-G', 'Visual Studio 17 2022'
    '-A', 'x64'
    "-DCMAKE_INSTALL_PREFIX=$installDir"
) + $cmakeOptions

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) {
    Write-Fail 'CMake configure failed.'
    Write-Info 'Most common causes: Boost or OpenSSL not found (set BOOST_ROOT / OPENSSL_ROOT_DIR),'
    Write-Info 'or the "Desktop development with C++" workload missing from Visual Studio.'
    exit 1
}
Write-Ok 'Configured.'

# Confirm the bot flag actually took, rather than trusting that it did.
if ($eraDef.Family -eq 'cmangos') {
    $cacheFile = Join-Path $buildDir 'CMakeCache.txt'
    if (Test-Path -LiteralPath $cacheFile) {
        $botLine = Select-String -LiteralPath $cacheFile -Pattern '^BUILD_PLAYERBOTS:BOOL=(.*)$' |
            Select-Object -First 1
        if ($botLine -and $botLine.Matches[0].Groups[1].Value -eq 'ON') {
            Write-Ok 'BUILD_PLAYERBOTS=ON confirmed in CMakeCache.'
        } else {
            Write-Fail 'BUILD_PLAYERBOTS is not ON in the CMake cache. Bots would be missing from this build.'
            exit 1
        }
    }
}

Write-Step "$($eraDef.Name) — building $Configuration with $Jobs job(s)"
Write-Info 'This is the long one. 20-60 minutes is normal for a first build.'

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& cmake --build $buildDir --config $Configuration --parallel $Jobs
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Build failed after $([int]$sw.Elapsed.TotalMinutes) minutes."
    exit 1
}
$sw.Stop()
Write-Ok "Built in $([int]$sw.Elapsed.TotalMinutes) minutes."

Write-Step 'Installing to the run directory'
& cmake --install $buildDir --config $Configuration
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'cmake --install failed. Copying binaries manually instead.'
    $binaries = Get-ChildItem -LiteralPath $buildDir -Recurse -File -Include '*.exe', '*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match "\\$Configuration\\" }
    foreach ($bin in $binaries) {
        Copy-Item -LiteralPath $bin.FullName -Destination $installDir -Force
    }
    Write-Info "Copied $($binaries.Count) file(s) to $installDir"
}

Write-Step 'Checking for the server binaries'
$missing = @()
foreach ($bin in @($eraDef.AuthBin, $eraDef.WorldBin)) {
    $found = Get-ChildItem -LiteralPath $installDir -Filter $bin -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) {
        Write-Ok "$bin — $($found.FullName)"
    } else {
        Write-Fail "$bin not found under $installDir"
        $missing += $bin
    }
}
if ($missing.Count -gt 0) {
    Write-Info "Look under $buildDir for the compiled output and copy it into $installDir."
    exit 1
}

Write-Host ''
Write-Info "Next: .\04-Write-Configs.ps1 -Era $Era"
