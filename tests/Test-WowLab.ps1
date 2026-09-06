<#
    .SYNOPSIS
    Tests the platform-independent parts of the toolkit.

    .DESCRIPTION
    Covers the era table (ports, databases and build numbers must not collide
    or drift from the plan) and the .conf patcher, which is the piece most
    likely to quietly corrupt a config file.

    Runs anywhere PowerShell runs — it touches no Windows-only cmdlets, so a
    change can be checked without a Windows box or a full server rebuild.

    .EXAMPLE
    pwsh -File tests\Test-WowLab.ps1
#>
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts/pc/lib/WowLab.psm1') -Force

$fails = 0
function T($name, $cond) {
    if ($cond) { Write-Host "  PASS $name" }
    else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:fails++ }
}

Write-Host '-- era definitions --'
$all = Get-WowLabEra -Era all
T 'three eras' ($all.Count -eq 3)
T 'unique auth ports' ((($all | ForEach-Object { $_.AuthPort }) | Sort-Object -Unique).Count -eq 3)
T 'unique world ports' ((($all | ForEach-Object { $_.WorldPort }) | Sort-Object -Unique).Count -eq 3)
$dbs = $all | ForEach-Object { $_.Db.Auth; $_.Db.World; $_.Db.Chars }
T 'nine distinct databases' (($dbs | Sort-Object -Unique).Count -eq 9)
T 'classic ports 3724/8085' ((Get-WowLabEra classic).AuthPort -eq 3724 -and (Get-WowLabEra classic).WorldPort -eq 8085)
T 'tbc ports 3725/8086' ((Get-WowLabEra tbc).AuthPort -eq 3725 -and (Get-WowLabEra tbc).WorldPort -eq 8086)
T 'wotlk ports 3726/8087' ((Get-WowLabEra wotlk).AuthPort -eq 3726 -and (Get-WowLabEra wotlk).WorldPort -eq 8087)
T 'wotlk uses the Playerbot fork branch' ((Get-WowLabEra wotlk).RepoBranch -eq 'Playerbot')
T 'client builds 5875/8606/12340' (
    (Get-WowLabEra classic).ClientBuild -eq 5875 -and
    (Get-WowLabEra tbc).ClientBuild -eq 8606 -and
    (Get-WowLabEra wotlk).ClientBuild -eq 12340)

Write-Host '-- conf patcher --'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'wowlab-test.conf'
@'
# sample core config
WorldServerPort = 8085
#LoginDatabaseInfo = "127.0.0.1;3306;mangos;mangos;realmd"
mmap.enabled = 0
'@ | Set-Content -LiteralPath $tmp

T 'rewrites an existing key (returns true)' ((Set-ConfValue -Path $tmp -Key 'WorldServerPort' -Value 8086) -eq $true)
T 'value is updated' ((Get-ConfValue -Path $tmp -Key 'WorldServerPort') -eq '8086')

$dbInfo = '"127.0.0.1;3306;wow;pw;classicrealmd"'
T 'uncomments a commented key' ((Set-ConfValue -Path $tmp -Key 'LoginDatabaseInfo' -Value $dbInfo) -eq $true)
T 'commented key is now active' ((Get-ConfValue -Path $tmp -Key 'LoginDatabaseInfo') -eq $dbInfo)

T 'appends an absent key (returns false)' ((Set-ConfValue -Path $tmp -Key 'DataDir' -Value '"C:/wow/classic"') -eq $false)
T 'appended key reads back' ((Get-ConfValue -Path $tmp -Key 'DataDir') -eq '"C:/wow/classic"')

Set-ConfValue -Path $tmp -Key 'mmap.enabled' -Value 1 | Out-Null
T 'dotted key names work' ((Get-ConfValue -Path $tmp -Key 'mmap.enabled') -eq '1')
T 'missing key returns null' ($null -eq (Get-ConfValue -Path $tmp -Key 'NoSuchKey'))
T 'surrounding comments are preserved' ((Get-Content -LiteralPath $tmp -Raw) -match '# sample core config')

Set-ConfValue -Path $tmp -Key 'WorldServerPort' -Value 9999 | Out-Null
T 'no duplicate lines when re-setting' (
    ((Get-Content -LiteralPath $tmp) | Where-Object { $_ -match '^WorldServerPort' }).Count -eq 1)

Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

Write-Host '-- config loader --'
$examplePath = Join-Path $repoRoot 'config/settings.example.psd1'
$cfgPath = Join-Path ([System.IO.Path]::GetTempPath()) 'wowlab-settings.psd1'
(Get-Content -LiteralPath $examplePath -Raw) -replace 'CHANGE-ME', 'realpw' | Set-Content -LiteralPath $cfgPath

$cfg = Get-WowLabConfig -Path $cfgPath
T 'loads the example config' ($cfg.MySQL.User -eq 'wow')
T 'bot defaults are 50/100' ($cfg.Bots.MinRandomBots -eq 50 -and $cfg.Bots.MaxRandomBots -eq 100)
T 'client paths for all three eras' ($cfg.Paths.Clients.Keys.Count -eq 3)

$threw = $false
try { Get-WowLabConfig -Path $examplePath | Out-Null } catch { $threw = $true }
T 'refuses the placeholder password' $threw

$threw = $false
try { Get-WowLabConfig -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'nope.psd1') | Out-Null } catch { $threw = $true }
T 'errors on a missing config file' $threw

Remove-Item -LiteralPath $cfgPath -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($fails -gt 0) {
    Write-Host "$fails FAILURE(S)" -ForegroundColor Red
    exit 1
}
Write-Host 'All tests passed.' -ForegroundColor Green
