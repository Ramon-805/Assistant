<#
    .SYNOPSIS
    Generates the realmlist files to copy onto the phone, home and away variants.

    .DESCRIPTION
    Vanilla and TBC read realmlist.wtf from the client root. WotLK reads
    'SET realmList' from WTF/Config.wtf instead, so for that era this writes a
    snippet and, with -PatchConfigWtf, edits a real Config.wtf in place.

    The port in a client's realmlist is the AUTH port (3724/3725/3726), never
    the world port — the world port is what the server advertises via its
    realmlist table, and the client never types it.

    Files land in out/phone/<era>/ for you to copy over USB.

    .PARAMETER PatchConfigWtf
    Path to an actual WTF\Config.wtf to edit in place (WotLK only).

    .EXAMPLE
    .\Write-Realmlist.ps1

    .EXAMPLE
    .\Write-Realmlist.ps1 -Era wotlk -PatchConfigWtf 'D:\wow-335\WTF\Config.wtf'
#>
[CmdletBinding()]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all',

    [string]$PatchConfigWtf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'scripts\pc\lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

$outRoot = Join-Path $repoRoot 'out\phone'

$targets = @(@{ Suffix = 'home'; Address = $config.LanIP })
if ($config.TailscaleIP) {
    $targets += @{ Suffix = 'away'; Address = $config.TailscaleIP }
} else {
    Write-Info 'TailscaleIP is empty in settings.psd1 — writing home variants only.'
}

foreach ($eraDef in $eras) {

    Write-Step "$($eraDef.Name) ($($eraDef.ClientVer), build $($eraDef.ClientBuild)) — auth port $($eraDef.AuthPort)"

    $outDir = Join-Path $outRoot $eraDef.Key
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    foreach ($target in $targets) {

        $endpoint = "$($target.Address):$($eraDef.AuthPort)"

        if ($eraDef.Family -eq 'azerothcore') {
            # WotLK: a Config.wtf line, not a realmlist.wtf file.
            $line = "SET realmList `"$endpoint`""
            $file = Join-Path $outDir "config-realmlist-$($target.Suffix).txt"
        } else {
            $line = "set realmlist $endpoint"
            $file = Join-Path $outDir "realmlist-$($target.Suffix).wtf"
        }

        Set-Content -LiteralPath $file -Value $line -Encoding ASCII -NoNewline
        Write-Ok "$([System.IO.Path]::GetFileName($file)) -> $line"
    }

    if ($eraDef.Family -eq 'azerothcore') {
        Write-Info "Put the line into WTF\Config.wtf, replacing any existing SET realmList."
    } else {
        Write-Info "Copy the -home file to the client root as realmlist.wtf, then set it read-only."
    }
}

# ---------------------------------------------------------------------------

if ($PatchConfigWtf) {

    Write-Step "Patching $PatchConfigWtf"

    if (-not (Test-Path -LiteralPath $PatchConfigWtf)) {
        throw "Config.wtf not found at '$PatchConfigWtf'."
    }

    $wotlk = Get-WowLabEra -Era wotlk
    $newLine = "SET realmList `"$($config.LanIP):$($wotlk.AuthPort)`""

    $backup = "$PatchConfigWtf.bak"
    Copy-Item -LiteralPath $PatchConfigWtf -Destination $backup -Force
    Write-Info "Backed up to $backup"

    $lines = @(Get-Content -LiteralPath $PatchConfigWtf)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*SET\s+realmList\s') {
            $lines[$i] = $newLine
            $found = $true
        }
    }
    if (-not $found) { $lines += $newLine }

    Set-Content -LiteralPath $PatchConfigWtf -Value $lines -Encoding ASCII
    Write-Ok $newLine
}

Write-Host ''
Write-Step 'On the phone'
Write-Info "Files are in $outRoot"
Write-Info '1. Copy the client folder to Internal Storage/Download/wow-<era>/ (internal storage, not external media).'
Write-Info '2. Drop the realmlist file in, then mark it READ-ONLY — some clients rewrite it on exit.'
Write-Info '3. Container settings and thermal tuning: docs/02-zfold-client-setup.md'
Write-Host ''
Write-Warn 'Build numbers must match exactly, or login fails with a generic error and empty server logs:'
foreach ($eraDef in $eras) {
    Write-Info "   $($eraDef.Name): $($eraDef.ClientVer) (build $($eraDef.ClientBuild))"
}
