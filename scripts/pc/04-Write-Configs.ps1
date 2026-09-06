<#
    .SYNOPSIS
    Creates the server .conf files from their .dist templates and fills in
    database credentials, ports, data paths and bot settings.

    .DESCRIPTION
    Implements the Config section of docs/01-pc-server-setup.md for every era.
    Existing .conf files are edited in place rather than overwritten, so hand
    edits survive a re-run. Pass -Force to start again from the .dist templates.

    Also enables mmap pathfinding explicitly — bots that spawn but stand
    motionless are almost always either missing mmaps or running with
    pathfinding switched off.

    .EXAMPLE
    .\04-Write-Configs.ps1 -Era classic
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('classic', 'tbc', 'wotlk')]
    [string]$Era,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eraDef = Get-WowLabEra -Era $Era

$sourceDir  = Get-WowLabSourceDir  -Config $config -EraDef $eraDef
$installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef

if (-not (Test-Path -LiteralPath $installDir)) {
    throw "Install dir '$installDir' not found. Run .\03-Build-Core.ps1 -Era $Era first."
}

# Connection strings use the format both cores share:
#   "host;port;user;password;database"
function New-DbInfo {
    param([string]$Database)
    return ('"{0};{1};{2};{3};{4}"' -f $config.MySQL.Host, $config.MySQL.Port,
                                       $config.MySQL.User, $config.MySQL.Password, $Database)
}

# Forward slashes are accepted by both cores and avoid escaping headaches.
$dataDir = '"' + ($installDir -replace '\\', '/') + '"'

function Find-ConfTemplate {
    <#
        Locates a .conf.dist. Build output and source tree both get searched,
        because where it lands differs between cores and CMake versions.
    #>
    param([string]$ConfName)

    $distName = "$ConfName.dist"
    foreach ($root in @($installDir, $sourceDir)) {
        $hit = Get-ChildItem -LiteralPath $root -Filter $distName -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

# AzerothCore reads its configs from a 'configs' subfolder; CMaNGOS reads them
# from beside the binaries.
$confDir = if ($eraDef.Family -eq 'azerothcore') {
    $acConf = Join-Path $installDir 'configs'
    if (-not (Test-Path -LiteralPath $acConf)) { New-Item -ItemType Directory -Path $acConf -Force | Out-Null }
    $acConf
} else {
    $installDir
}

# ---------------------------------------------------------------------------
# World server config
# ---------------------------------------------------------------------------

Write-Step "$($eraDef.Name) — $($eraDef.WorldConf)"

$worldDist = Find-ConfTemplate -ConfName $eraDef.WorldConf
if (-not $worldDist) { throw "Could not find $($eraDef.WorldConf).dist under $installDir or $sourceDir." }

$worldConf = Initialize-ConfFromDist -DistPath $worldDist -DestPath (Join-Path $confDir $eraDef.WorldConf) -Force:$Force

Set-ConfValue -Path $worldConf -Key 'LoginDatabaseInfo'     -Value (New-DbInfo $eraDef.Db.Auth)  | Out-Null
Set-ConfValue -Path $worldConf -Key 'WorldDatabaseInfo'     -Value (New-DbInfo $eraDef.Db.World) | Out-Null
Set-ConfValue -Path $worldConf -Key 'CharacterDatabaseInfo' -Value (New-DbInfo $eraDef.Db.Chars) | Out-Null
Set-ConfValue -Path $worldConf -Key 'WorldServerPort'       -Value $eraDef.WorldPort             | Out-Null
Set-ConfValue -Path $worldConf -Key 'DataDir'               -Value $dataDir                      | Out-Null

# Pathfinding. Different key names per core, same purpose: without these the
# bots cannot navigate and stand still.
if ($eraDef.Family -eq 'azerothcore') {
    Set-ConfValue -Path $worldConf -Key 'MoveMaps.Enable' -Value 1 | Out-Null
} else {
    Set-ConfValue -Path $worldConf -Key 'mmap.enabled'    -Value 1 | Out-Null
}
Set-ConfValue -Path $worldConf -Key 'vmap.enableLOS'    -Value 1 | Out-Null
Set-ConfValue -Path $worldConf -Key 'vmap.enableHeight' -Value 1 | Out-Null

Write-Ok "World port $($eraDef.WorldPort), databases $($eraDef.Db.World)/$($eraDef.Db.Chars), pathfinding on."

# ---------------------------------------------------------------------------
# Auth server config
# ---------------------------------------------------------------------------

Write-Step "$($eraDef.Name) — $($eraDef.AuthConf)"

$authDist = Find-ConfTemplate -ConfName $eraDef.AuthConf
if (-not $authDist) { throw "Could not find $($eraDef.AuthConf).dist under $installDir or $sourceDir." }

$authConf = Initialize-ConfFromDist -DistPath $authDist -DestPath (Join-Path $confDir $eraDef.AuthConf) -Force:$Force

Set-ConfValue -Path $authConf -Key 'LoginDatabaseInfo' -Value (New-DbInfo $eraDef.Db.Auth) | Out-Null
Set-ConfValue -Path $authConf -Key 'RealmServerPort'   -Value $eraDef.AuthPort             | Out-Null

Write-Ok "Auth port $($eraDef.AuthPort), database $($eraDef.Db.Auth)."

# ---------------------------------------------------------------------------
# Playerbots config
# ---------------------------------------------------------------------------

Write-Step "$($eraDef.Name) — $($eraDef.BotConf)"

$botDist = Join-Path $sourceDir ($eraDef.BotConfDist -replace '/', '\')
if (-not (Test-Path -LiteralPath $botDist)) {
    # Fall back to a search — upstream moves these around between versions.
    $botDist = Find-ConfTemplate -ConfName $eraDef.BotConf
    if (-not $botDist) {
        $expected = Join-Path $sourceDir ($eraDef.BotConfDist -replace '/', '\')
        Write-Warn "Bot config template not found at '$expected' and no $($eraDef.BotConf).dist elsewhere."
        Write-Info 'Skipping bot config — find the .dist in the module and copy it in by hand.'
        $botDist = $null
    }
}

if ($botDist) {
    $botConf = Initialize-ConfFromDist -DistPath $botDist -DestPath (Join-Path $confDir $eraDef.BotConf) -Force:$Force

    Set-ConfValue -Path $botConf -Key 'AiPlayerbot.Enabled'           -Value 1 | Out-Null
    Set-ConfValue -Path $botConf -Key 'AiPlayerbot.MinRandomBots'     -Value $config.Bots.MinRandomBots | Out-Null
    Set-ConfValue -Path $botConf -Key 'AiPlayerbot.MaxRandomBots'     -Value $config.Bots.MaxRandomBots | Out-Null
    Set-ConfValue -Path $botConf -Key 'AiPlayerbot.RandomBotAutologin' -Value 1 | Out-Null

    Write-Ok "Bots enabled, $($config.Bots.MinRandomBots)-$($config.Bots.MaxRandomBots) random bots."
    Write-Info 'Raise the bot counts in settings.psd1 once you know the PC keeps up.'
}

Write-Host ''
Write-Info "Configs are in $confDir"
Write-Info "Next: .\05-Extract-MapData.ps1 -Era $Era   (the multi-hour one)"
