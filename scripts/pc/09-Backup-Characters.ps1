<#
    .SYNOPSIS
    Dumps the three character databases.

    .DESCRIPTION
    World databases are reproducible from the repos; character databases are
    not. This backs up only what cannot be rebuilt, plus the auth databases,
    which hold your accounts.

    Register it as a weekly scheduled task with -RegisterScheduledTask.

    .EXAMPLE
    .\09-Backup-Characters.ps1

    .EXAMPLE
    .\09-Backup-Characters.ps1 -RegisterScheduledTask
#>
[CmdletBinding()]
param(
    # Delete dumps older than this. 0 keeps everything.
    [int]$KeepDays = 60,

    [switch]$IncludeAuth = $true,

    [switch]$RegisterScheduledTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig

if ($RegisterScheduledTask) {
    Assert-Administrator -Because 'Registering a scheduled task needs Administrator rights.'

    $scriptPath = $PSCommandPath
    $action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries

    Register-ScheduledTask -TaskName 'WoW character backup' `
        -Action $action -Trigger $trigger -Settings $settings `
        -Description 'Weekly dump of the WoW character and auth databases' -Force | Out-Null

    Write-Ok 'Registered weekly task "WoW character backup" (Sundays, 4am).'
    return
}

$backupDir = $config.Paths.Backups
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$dumpExe = Resolve-MySqlClient -Config $config -Tool mysqldump

$databases = @()
foreach ($era in Get-WowLabEra -Era all) {
    $databases += $era.Db.Chars
    if ($IncludeAuth) { $databases += $era.Db.Auth }
}

# Only dump databases that actually exist, so a backup during a partial build
# does not fail outright.
$present = Invoke-MySql -Config $config -Query 'SHOW DATABASES;' -Raw
$toDump  = $databases | Where-Object { $present -contains $_ }
$skipped = $databases | Where-Object { $present -notcontains $_ }

foreach ($db in $skipped) { Write-Info "Skipping $db (does not exist yet)." }

if (-not $toDump) {
    Write-Warn 'No character or auth databases exist yet — nothing to back up.'
    return
}

$stamp    = Get-Date -Format 'yyyy-MM-dd-HHmm'
$outFile  = Join-Path $backupDir "wow-chars-$stamp.sql"
$defaults = $null

Write-Step "Dumping $($toDump.Count) database(s) to $outFile"

try {
    # Same reasoning as Invoke-MySql: keep the password out of the process list.
    $defaults = [System.IO.Path]::GetTempFileName()
    Set-Content -LiteralPath $defaults -Encoding ASCII -Value @(
        '[client]'
        "user=$($config.MySQL.User)"
        "password=$($config.MySQL.Password)"
        "host=$($config.MySQL.Host)"
        "port=$($config.MySQL.Port)"
    )

    & $dumpExe "--defaults-extra-file=$defaults" --single-transaction --routines --events `
        --databases @toDump --result-file="$outFile"

    if ($LASTEXITCODE -ne 0) { throw "mysqldump exited with code $LASTEXITCODE." }
} finally {
    if ($defaults) { Remove-Item -LiteralPath $defaults -Force -ErrorAction SilentlyContinue }
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $outFile).Length / 1MB, 1)
Write-Ok "$outFile ($sizeMb MB)"
foreach ($db in $toDump) { Write-Info "  $db" }

if ($KeepDays -gt 0) {
    $cutoff = (Get-Date).AddDays(-$KeepDays)
    $old = Get-ChildItem -LiteralPath $backupDir -Filter 'wow-chars-*.sql' -File |
        Where-Object { $_.LastWriteTime -lt $cutoff }
    foreach ($file in $old) {
        Remove-Item -LiteralPath $file.FullName -Force
        Write-Info "Removed old backup $($file.Name)"
    }
}
