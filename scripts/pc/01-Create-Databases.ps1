<#
    .SYNOPSIS
    Creates the nine databases and the dedicated 'wow' MySQL user.

    .DESCRIPTION
    Implements Step 1 of docs/01-pc-server-setup.md. Prompts for the MySQL root
    password rather than reading it from settings.psd1, so the root credential
    is never written to disk.

    Safe to re-run — databases use IF NOT EXISTS and the user grant is idempotent.

    .EXAMPLE
    .\01-Create-Databases.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipUserCreation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config   = Get-WowLabConfig
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$sqlFile  = Join-Path $repoRoot 'sql\01-create-databases.sql'

Write-Step "Connecting to MySQL at $($config.MySQL.Host):$($config.MySQL.Port) as '$($config.MySQL.RootUser)'"

$rootSecure = Read-Host -Prompt "MySQL password for '$($config.MySQL.RootUser)'" -AsSecureString
$rootPlain  = [System.Net.NetworkCredential]::new('', $rootSecure).Password

try {
    Invoke-MySql -Config $config -Query 'SELECT VERSION();' -AsRoot -RootPassword $rootPlain -Raw | ForEach-Object {
        Write-Ok "MySQL $_"
    }

    Write-Step 'Creating databases'
    if ($PSCmdlet.ShouldProcess('MySQL', 'create nine databases')) {
        Invoke-MySql -Config $config -File $sqlFile -AsRoot -RootPassword $rootPlain | Out-Null
    }

    foreach ($era in Get-WowLabEra -Era all) {
        Write-Ok "$($era.Name): $($era.Db.Auth), $($era.Db.World), $($era.Db.Chars)"
    }

    if (-not $SkipUserCreation) {
        Write-Step "Creating the '$($config.MySQL.User)' user"

        # Scoped to the nine databases rather than *.* — the servers never need
        # anything else, and this keeps a leaked server config from owning MySQL.
        $dbNames = (Get-WowLabEra -Era all | ForEach-Object { $_.Db.Auth; $_.Db.World; $_.Db.Chars })

        $grantSql = @(
            "CREATE USER IF NOT EXISTS '$($config.MySQL.User)'@'localhost' IDENTIFIED BY '$($config.MySQL.Password)';"
            "ALTER USER '$($config.MySQL.User)'@'localhost' IDENTIFIED BY '$($config.MySQL.Password)';"
        )
        foreach ($db in $dbNames) {
            $grantSql += "GRANT ALL PRIVILEGES ON ``$db``.* TO '$($config.MySQL.User)'@'localhost';"
        }
        $grantSql += 'FLUSH PRIVILEGES;'

        if ($PSCmdlet.ShouldProcess('MySQL', "create/grant user '$($config.MySQL.User)'")) {
            Invoke-MySql -Config $config -Query ($grantSql -join "`n") -AsRoot -RootPassword $rootPlain | Out-Null
        }
        Write-Ok "User '$($config.MySQL.User)'@'localhost' granted on the nine project databases."
    }
} finally {
    $rootPlain = $null
    [System.GC]::Collect()
}

Write-Step 'Verifying'
if (Test-MySqlConnection -Config $config) {
    Write-Ok "'$($config.MySQL.User)' can connect."
    $existing = Invoke-MySql -Config $config -Query 'SHOW DATABASES;' -Raw
    foreach ($era in Get-WowLabEra -Era all) {
        foreach ($db in @($era.Db.Auth, $era.Db.World, $era.Db.Chars)) {
            if ($existing -contains $db) { Write-Ok "  $db" } else { Write-Fail "  $db missing" }
        }
    }
} else {
    Write-Fail "'$($config.MySQL.User)' still cannot connect — check MySQL.Password in settings.psd1."
    exit 1
}

Write-Host ''
Write-Info 'Next: .\02-Clone-Sources.ps1 -Era classic'
