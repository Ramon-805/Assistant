<#
    .SYNOPSIS
    Installs the servers as Windows services with NSSM, so nothing appears on
    the living room monitor and everything starts at boot.

    .DESCRIPTION
    This is the right answer once the servers are staying up permanently. Note
    the tradeoff: services have no console, so you cannot type server commands
    any more. Create a GM account BEFORE converting:

        account create youraccount yourpassword
        account set gmlevel youraccount 3 -1

    Requires nssm.exe — set Paths.Nssm in settings.psd1 (https://nssm.cc).

    .EXAMPLE
    .\08-Install-Services.ps1 -Era classic

    .EXAMPLE
    .\08-Install-Services.ps1 -Era all -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all',

    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

Assert-Administrator -Because 'Installing services needs Administrator rights.'

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

$nssm = $config.Paths.Nssm
if (-not $nssm -or -not (Test-Path -LiteralPath $nssm)) {
    $onPath = Get-Command 'nssm.exe' -ErrorAction SilentlyContinue
    if ($onPath) {
        $nssm = $onPath.Source
    } else {
        throw "nssm.exe not found. Download it from https://nssm.cc and set Paths.Nssm in settings.psd1."
    }
}
Write-Info "Using $nssm"

foreach ($eraDef in $eras) {

    $installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef

    $services = @(
        @{ Name = $eraDef.ServiceAuth;  Bin = $eraDef.AuthBin;  Label = 'auth'  }
        @{ Name = $eraDef.ServiceWorld; Bin = $eraDef.WorldBin; Label = 'world' }
    )

    foreach ($svc in $services) {

        $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue

        if ($Remove) {
            if (-not $existing) {
                Write-Info "$($svc.Name) not installed."
                continue
            }
            if ($PSCmdlet.ShouldProcess($svc.Name, 'stop and remove service')) {
                & $nssm stop $svc.Name confirm | Out-Null
                & $nssm remove $svc.Name confirm | Out-Null
            }
            Write-Ok "Removed $($svc.Name)."
            continue
        }

        $exe = Get-ChildItem -LiteralPath $installDir -Filter $svc.Bin -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $exe) {
            Write-Fail "$($eraDef.Name) $($svc.Label): $($svc.Bin) not found under $installDir — build it first."
            continue
        }

        if ($existing) {
            Write-Info "$($svc.Name) already installed — updating its settings."
        } else {
            if ($PSCmdlet.ShouldProcess($svc.Name, "install service for $($exe.FullName)")) {
                & $nssm install $svc.Name $exe.FullName | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($svc.Name, 'configure service')) {
            & $nssm set $svc.Name AppDirectory $exe.DirectoryName | Out-Null
            & $nssm set $svc.Name DisplayName  "WoW $($eraDef.Name) $($svc.Label) server" | Out-Null
            & $nssm set $svc.Name Description  "$($eraDef.Name) ($($eraDef.ClientVer)) $($svc.Label) server" | Out-Null
            & $nssm set $svc.Name Start        SERVICE_AUTO_START | Out-Null

            # The world server needs the auth server's database up first; a short
            # restart delay avoids a boot-time thrash if MySQL is still starting.
            & $nssm set $svc.Name AppRestartDelay 10000 | Out-Null
        }

        Write-Ok "$($svc.Name) -> $($exe.FullName)"
    }
}

if (-not $Remove) {
    Write-Host ''
    Write-Warn 'Services have no console, so server commands are unavailable.'
    Write-Info 'Create a GM account before you rely on services:'
    Write-Info '  account create youraccount yourpassword'
    Write-Info '  account set gmlevel youraccount 3 -1'
    Write-Host ''
    Write-Info 'Start them with:  .\Start-Servers.ps1 -UseServices'
}
