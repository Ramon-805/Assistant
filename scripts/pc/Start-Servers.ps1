<#
    .SYNOPSIS
    Starts the auth and world servers for one or all eras, minimized.

    .DESCRIPTION
    Auth starts first, then a short pause, then world — the world server wants
    the login database reachable when it comes up.

    Nothing is displayed beyond minimized console windows. For genuinely
    invisible operation install them as services (08-Install-Services.ps1) and
    use -UseServices here.

    .EXAMPLE
    .\Start-Servers.ps1 -Era classic

    .EXAMPLE
    .\Start-Servers.ps1 -Era all -UseServices
#>
[CmdletBinding()]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all',

    [switch]$UseServices,

    [int]$DelaySeconds = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

foreach ($eraDef in $eras) {

    Write-Step "$($eraDef.Name)"

    if ($UseServices) {
        foreach ($svcName in @($eraDef.ServiceAuth, $eraDef.ServiceWorld)) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) {
                Write-Fail "Service $svcName not installed. Run .\08-Install-Services.ps1 first."
                continue
            }
            if ($svc.Status -eq 'Running') {
                Write-Info "$svcName already running."
            } else {
                Start-Service -Name $svcName
                Write-Ok "$svcName started."
            }
            if ($svcName -eq $eraDef.ServiceAuth) { Start-Sleep -Seconds $DelaySeconds }
        }
        continue
    }

    $installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef

    foreach ($bin in @($eraDef.AuthBin, $eraDef.WorldBin)) {

        $exe = Get-ChildItem -LiteralPath $installDir -Filter $bin -Recurse -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $exe) {
            Write-Fail "$bin not found under $installDir."
            continue
        }

        $procName  = [System.IO.Path]::GetFileNameWithoutExtension($bin)
        $alreadyUp = Get-Process -Name $procName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $exe.FullName }

        if ($alreadyUp) {
            Write-Info "$bin already running (PID $($alreadyUp.Id))."
        } else {
            Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -WindowStyle Minimized
            Write-Ok "Started $bin"
        }

        if ($bin -eq $eraDef.AuthBin) { Start-Sleep -Seconds $DelaySeconds }
    }
}

Write-Host ''
Write-Info 'Give the world servers a minute to load maps, then run .\Test-Deployment.ps1'
