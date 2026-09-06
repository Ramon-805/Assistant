<#
    .SYNOPSIS
    Clones a core's source tree together with its playerbots module.

    .DESCRIPTION
    The bot module has to sit at a specific path inside the source tree, and for
    WotLK the core itself must come from the mod-playerbots fork's 'Playerbot'
    branch — mainline AzerothCore will not build with mod-playerbots. This script
    encodes both facts so they cannot be got wrong.

    Re-running fetches and fast-forwards instead of re-cloning.

    .EXAMPLE
    .\02-Clone-Sources.ps1 -Era classic

    .EXAMPLE
    .\02-Clone-Sources.ps1 -Era all
#>
[CmdletBinding()]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'classic'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

if (-not (Test-Path -LiteralPath $config.Paths.Sources)) {
    New-Item -ItemType Directory -Path $config.Paths.Sources -Force | Out-Null
    Write-Ok "Created $($config.Paths.Sources)"
}

foreach ($eraDef in $eras) {
    Write-Step "$($eraDef.Name) — source"

    $sourceDir = Get-WowLabSourceDir -Config $config -EraDef $eraDef

    if (Test-Path -LiteralPath (Join-Path $sourceDir '.git')) {
        Write-Info "Already cloned at $sourceDir — fetching."
        Push-Location $sourceDir
        try {
            git fetch --all --prune
            git pull --ff-only
            if ($LASTEXITCODE -ne 0) {
                Write-Warn 'Fast-forward pull failed (local commits?). Leaving the tree as-is.'
            }
        } finally { Pop-Location }
    } else {
        $cloneArgs = @('clone', '--recursive')
        if ($eraDef.RepoBranch) { $cloneArgs += @('--branch', $eraDef.RepoBranch) }
        $cloneArgs += @($eraDef.Repo, $sourceDir)

        Write-Info "git $($cloneArgs -join ' ')"
        git @cloneArgs
        if ($LASTEXITCODE -ne 0) { throw "Clone of $($eraDef.Repo) failed." }
        Write-Ok "Cloned to $sourceDir"
    }

    if ($eraDef.RepoBranch) {
        Push-Location $sourceDir
        try {
            $branch = (git rev-parse --abbrev-ref HEAD).Trim()
            if ($branch -ne $eraDef.RepoBranch) {
                Write-Warn "On branch '$branch', expected '$($eraDef.RepoBranch)'. Checking it out."
                git checkout $eraDef.RepoBranch
            }
            Write-Ok "Branch: $($eraDef.RepoBranch)"
        } finally { Pop-Location }
    }

    Write-Step "$($eraDef.Name) — playerbots module"

    $botDir = Join-Path $sourceDir ($eraDef.BotPath -replace '/', '\')

    if (Test-Path -LiteralPath (Join-Path $botDir '.git')) {
        Write-Info "Bot module already at $botDir — fetching."
        Push-Location $botDir
        try {
            git fetch --all --prune
            git pull --ff-only
        } finally { Pop-Location }
    } else {
        $parent = Split-Path -Parent $botDir
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        git clone $eraDef.BotRepo $botDir
        if ($LASTEXITCODE -ne 0) { throw "Clone of $($eraDef.BotRepo) failed." }
        Write-Ok "Bot module cloned to $botDir"
    }
}

Write-Host ''
Write-Info "Next: .\03-Build-Core.ps1 -Era $($eras[0].Key)"
