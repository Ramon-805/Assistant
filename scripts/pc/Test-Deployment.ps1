<#
    .SYNOPSIS
    Runs the "before touching the phone" checklist from docs/01-pc-server-setup.md.

    .DESCRIPTION
    Checks, per era: databases present and populated, map/vmap/mmap data in the
    right place, configs pointing at the right databases and ports, servers
    listening, and the realmlist advertising a routable address.

    Every failure line names the fix. Run it whenever something stops working —
    it is faster than guessing which of the six moving parts broke.

    .EXAMPLE
    .\Test-Deployment.ps1

    .EXAMPLE
    .\Test-Deployment.ps1 -Era classic
#>
[CmdletBinding()]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

$pass = 0
$fail = 0
$warn = 0

function Check-Ok   { param([string]$m) Write-Ok   $m; $script:pass++ }
function Check-Fail { param([string]$m, [string]$fix) Write-Fail $m; if ($fix) { Write-Info "-> $fix" }; $script:fail++ }
function Check-Warn { param([string]$m, [string]$fix) Write-Warn $m; if ($fix) { Write-Info "-> $fix" }; $script:warn++ }

# ---------------------------------------------------------------------------

Write-Step 'MySQL'

if (Test-MySqlConnection -Config $config) {
    Check-Ok "Connected as '$($config.MySQL.User)'."
    $allDatabases = Invoke-MySql -Config $config -Query 'SHOW DATABASES;' -Raw
} else {
    Check-Fail "Cannot connect to MySQL as '$($config.MySQL.User)'." 'Run .\01-Create-Databases.ps1'
    $allDatabases = @()
}

Write-Step 'Network address'

$localIPs = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
if ($localIPs -contains $config.LanIP) {
    Check-Ok "LanIP $($config.LanIP) is an address on this machine."
} else {
    Check-Warn "LanIP $($config.LanIP) is not currently an address on this machine." `
               "Check settings.psd1 and the router's DHCP reservation. This PC has: $($localIPs -join ', ')"
}

# ---------------------------------------------------------------------------

foreach ($eraDef in $eras) {

    Write-Step "$($eraDef.Name) ($($eraDef.ClientVer), build $($eraDef.ClientBuild))"

    $installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef

    if (-not (Test-Path -LiteralPath $installDir)) {
        Check-Warn "Not built yet — $installDir does not exist." "Run .\03-Build-Core.ps1 -Era $($eraDef.Key)"
        continue
    }

    # --- databases ---------------------------------------------------------

    foreach ($entry in @(
        @{ Db = $eraDef.Db.Auth;  Table = 'realmlist' }
        @{ Db = $eraDef.Db.World; Table = $null }
        @{ Db = $eraDef.Db.Chars; Table = $null }
    )) {
        if ($allDatabases -notcontains $entry.Db) {
            Check-Fail "Database $($entry.Db) missing." 'Run .\01-Create-Databases.ps1'
            continue
        }

        $tableCount = (Invoke-MySql -Config $config -Raw -Query `
            "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$($entry.Db)';" |
            Select-Object -First 1)

        if ([int]$tableCount -eq 0) {
            Check-Fail "Database $($entry.Db) exists but is empty ($tableCount tables)." `
                       'Import the core''s SQL — CMaNGOS installer script, or AzerothCore''s auto-updater on first worldserver start.'
        } else {
            Check-Ok "$($entry.Db): $tableCount tables."
        }
    }

    # --- map data ----------------------------------------------------------

    foreach ($dir in @('dbc', 'maps', 'vmaps', 'mmaps')) {
        $path = Join-Path $installDir $dir
        $count = if (Test-Path -LiteralPath $path) {
            (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue).Count
        } else { 0 }

        if ($count -gt 0) {
            Check-Ok "$dir/: $count files."
        } elseif ($dir -eq 'mmaps') {
            Check-Fail "mmaps/ is missing or empty — bots will spawn and stand still." `
                       ".\05-Extract-MapData.ps1 -Era $($eraDef.Key) -Stage mmaps"
        } else {
            Check-Fail "$dir/ is missing or empty." ".\05-Extract-MapData.ps1 -Era $($eraDef.Key)"
        }
    }

    # --- configs -----------------------------------------------------------

    $confDir = if ($eraDef.Family -eq 'azerothcore') { Join-Path $installDir 'configs' } else { $installDir }

    $worldConfPath = Join-Path $confDir $eraDef.WorldConf
    $authConfPath  = Join-Path $confDir $eraDef.AuthConf

    if (Test-Path -LiteralPath $worldConfPath) {
        $worldPort = Get-ConfValue -Path $worldConfPath -Key 'WorldServerPort'
        if ($worldPort -eq [string]$eraDef.WorldPort) {
            Check-Ok "$($eraDef.WorldConf): WorldServerPort $worldPort."
        } else {
            Check-Fail "$($eraDef.WorldConf): WorldServerPort is '$worldPort', expected $($eraDef.WorldPort)." `
                       ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
        }

        $pathfindKey   = if ($eraDef.Family -eq 'azerothcore') { 'MoveMaps.Enable' } else { 'mmap.enabled' }
        $pathfindValue = Get-ConfValue -Path $worldConfPath -Key $pathfindKey
        if ($pathfindValue -eq '1') {
            Check-Ok "$pathfindKey = 1 (bot pathfinding on)."
        } else {
            Check-Fail "$pathfindKey is '$pathfindValue' — bots will not path." `
                       ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
        }
    } else {
        Check-Fail "$($eraDef.WorldConf) not found in $confDir." ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
    }

    if (Test-Path -LiteralPath $authConfPath) {
        $authPort = Get-ConfValue -Path $authConfPath -Key 'RealmServerPort'
        if ($authPort -eq [string]$eraDef.AuthPort) {
            Check-Ok "$($eraDef.AuthConf): RealmServerPort $authPort."
        } else {
            Check-Fail "$($eraDef.AuthConf): RealmServerPort is '$authPort', expected $($eraDef.AuthPort)." `
                       ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
        }
    } else {
        Check-Fail "$($eraDef.AuthConf) not found in $confDir." ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
    }

    $botConfPath = Join-Path $confDir $eraDef.BotConf
    if (Test-Path -LiteralPath $botConfPath) {
        $botsOn = Get-ConfValue -Path $botConfPath -Key 'AiPlayerbot.Enabled'
        if ($botsOn -eq '1') {
            Check-Ok "$($eraDef.BotConf): bots enabled."
        } else {
            Check-Warn "$($eraDef.BotConf): AiPlayerbot.Enabled is '$botsOn'." ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
        }
    } else {
        Check-Warn "$($eraDef.BotConf) not found — no bots." ".\04-Write-Configs.ps1 -Era $($eraDef.Key)"
    }

    # --- realmlist ---------------------------------------------------------

    if ($allDatabases -contains $eraDef.Db.Auth) {
        $hasRealmlist = (Invoke-MySql -Config $config -Raw -Query `
            "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$($eraDef.Db.Auth)' AND TABLE_NAME = 'realmlist';" |
            Select-Object -First 1) -eq '1'

        if ($hasRealmlist) {
            $rows = Invoke-MySql -Config $config -Database $eraDef.Db.Auth -Raw `
                -Query 'SELECT name, address, port FROM realmlist;'
            if (-not $rows) {
                Check-Warn "$($eraDef.Db.Auth).realmlist is empty." 'Start the world server once, then re-run.'
            }
            foreach ($row in $rows) {
                $f = $row -split "`t"
                if ($f.Count -lt 3) { continue }
                if ($f[1] -in @('127.0.0.1', 'localhost')) {
                    Check-Fail "Realm '$($f[0])' advertises $($f[1]) — the phone will get 'world server is down'." `
                               ".\06-Set-RealmlistAddress.ps1 -Era $($eraDef.Key)"
                } elseif ($f[1] -ne $config.LanIP) {
                    Check-Warn "Realm '$($f[0])' advertises $($f[1]), not LanIP $($config.LanIP)." `
                               'Fine if deliberate (Tailscale); otherwise run 06-Set-RealmlistAddress.ps1.'
                } else {
                    Check-Ok "Realm '$($f[0])' -> $($f[1]):$($f[2])."
                }
            }
        } else {
            Check-Warn "No realmlist table in $($eraDef.Db.Auth) yet." 'Import the auth database.'
        }
    }

    # --- listeners ---------------------------------------------------------

    foreach ($entry in @(
        @{ Port = $eraDef.AuthPort;  Label = 'auth'  }
        @{ Port = $eraDef.WorldPort; Label = 'world' }
    )) {
        if (Test-PortListening -Port $entry.Port) {
            Check-Ok "Listening on $($entry.Port) ($($entry.Label))."
        } else {
            Check-Warn "Nothing listening on $($entry.Port) ($($entry.Label))." `
                       ".\Start-Servers.ps1 -Era $($eraDef.Key)"
        }
    }
}

# ---------------------------------------------------------------------------

Write-Step 'Firewall'

$rule = Get-NetFirewallRule -DisplayName 'WoW Private Servers' -ErrorAction SilentlyContinue
if ($rule) {
    $ports = ($rule | Get-NetFirewallPortFilter).LocalPort
    Check-Ok "Rule present for TCP $($ports -join ', ')."
} else {
    Check-Warn 'No "WoW Private Servers" firewall rule.' 'Run .\07-Open-Firewall.ps1 from an elevated prompt.'
}

# ---------------------------------------------------------------------------

Write-Host ''
Write-Host "  $pass passed, $warn warning(s), $fail failure(s)" -ForegroundColor $(if ($fail) { 'Red' } elseif ($warn) { 'Yellow' } else { 'Green' })
Write-Host ''

if ($fail -eq 0 -and $warn -eq 0) {
    Write-Ok 'Server side is ready. Next: connect a local PC client, then the phone.'
    Write-Info 'Phone realmlist: scripts\phone\Write-Realmlist.ps1'
}

exit $(if ($fail -gt 0) { 1 } else { 0 })
