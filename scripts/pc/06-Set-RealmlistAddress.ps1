<#
    .SYNOPSIS
    Points the realm's advertised address at the PC's LAN IP instead of 127.0.0.1.

    .DESCRIPTION
    This is the step everyone gets wrong. With 127.0.0.1 in the realmlist table
    the phone authenticates fine and then tries to connect to *itself* for the
    world server, giving "world server is down" with no clue why.

    Handles both schemas: CMaNGOS's realmlist table, and AzerothCore's, which
    also has localAddress/localSubnetMask columns that need to agree.

    Run this after the databases are populated — the realmlist table has to exist.

    .PARAMETER Address
    Override the address to advertise. Defaults to LanIP from settings.psd1.
    Use this to switch the realm to a Tailscale address for remote play.

    .EXAMPLE
    .\06-Set-RealmlistAddress.ps1 -Era all

    .EXAMPLE
    .\06-Set-RealmlistAddress.ps1 -Era classic -Address 100.101.102.103
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all',

    [string]$Address
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

if (-not $Address) { $Address = $config.LanIP }

if ($Address -eq '127.0.0.1' -or $Address -eq 'localhost') {
    throw ("Refusing to set the realm address to '$Address'. That is the exact mistake this " +
           "script exists to prevent — the phone would try to reach the world server on itself.")
}

Write-Step "Advertising realms at $Address"

$failures = 0

foreach ($eraDef in $eras) {

    $db = $eraDef.Db.Auth

    # Does this database have a realmlist table yet?
    $tableCheck = Invoke-MySql -Config $config -Raw -Query @"
SELECT COUNT(*) FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = 'realmlist';
"@
    if (($tableCheck | Select-Object -First 1) -ne '1') {
        Write-Warn "$($eraDef.Name): no realmlist table in '$db' yet — import the auth database first."
        $failures++
        continue
    }

    # AzerothCore's realmlist also carries localAddress; CMaNGOS's does not.
    $hasLocalAddress = (Invoke-MySql -Config $config -Raw -Query @"
SELECT COUNT(*) FROM information_schema.COLUMNS
 WHERE TABLE_SCHEMA = '$db' AND TABLE_NAME = 'realmlist' AND COLUMN_NAME = 'localAddress';
"@ | Select-Object -First 1) -eq '1'

    $sets = @("address = '$Address'", "port = $($eraDef.WorldPort)")
    if ($hasLocalAddress) { $sets += "localAddress = '$Address'" }

    $update = "UPDATE realmlist SET $($sets -join ', ');"

    if ($PSCmdlet.ShouldProcess("$db.realmlist", "set address=$Address port=$($eraDef.WorldPort)")) {
        Invoke-MySql -Config $config -Database $db -Query $update | Out-Null
    }

    # Read it back rather than assuming the update landed.
    $rows = Invoke-MySql -Config $config -Database $db -Raw -Query 'SELECT id, name, address, port FROM realmlist;'
    if (-not $rows) {
        Write-Warn "$($eraDef.Name): realmlist table is empty. The core writes a default row on first start."
        $failures++
        continue
    }

    foreach ($row in $rows) {
        $fields = $row -split "`t"
        if ($fields.Count -ge 4) {
            if ($fields[2] -eq $Address -and $fields[3] -eq [string]$eraDef.WorldPort) {
                Write-Ok "$($eraDef.Name): realm '$($fields[1])' -> $($fields[2]):$($fields[3])"
            } else {
                Write-Fail "$($eraDef.Name): realm '$($fields[1])' is $($fields[2]):$($fields[3]), expected $Address`:$($eraDef.WorldPort)"
                $failures++
            }
        }
    }
}

Write-Host ''
if ($failures -gt 0) {
    Write-Warn "$failures realm(s) not set. Import the auth database, start the core once, then re-run."
    exit 1
}
Write-Ok 'All realms advertise a routable address.'
Write-Info 'The phone realmlist ports are the AUTH ports (3724/3725/3726), not these world ports.'
