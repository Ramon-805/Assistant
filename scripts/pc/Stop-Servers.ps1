<#
    .SYNOPSIS
    Stops the servers for one or all eras.

    .DESCRIPTION
    World servers first, then auth — the world server flushes character state to
    MySQL on shutdown, so it gets a graceful close and time to finish.

    .EXAMPLE
    .\Stop-Servers.ps1 -Era all
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
    [string]$Era = 'all',

    [switch]$UseServices,

    # Seconds to wait for a graceful exit before killing the process.
    [int]$TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$config = Get-WowLabConfig
$eras   = @(Get-WowLabEra -Era $Era)

foreach ($eraDef in $eras) {

    Write-Step "$($eraDef.Name)"

    if ($UseServices) {
        foreach ($svcName in @($eraDef.ServiceWorld, $eraDef.ServiceAuth)) {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if (-not $svc) { Write-Info "$svcName not installed."; continue }
            if ($svc.Status -eq 'Stopped') { Write-Info "$svcName already stopped."; continue }
            if ($PSCmdlet.ShouldProcess($svcName, 'stop service')) {
                Stop-Service -Name $svcName -Force
            }
            Write-Ok "$svcName stopped."
        }
        continue
    }

    $installDir = Get-WowLabInstallDir -Config $config -EraDef $eraDef

    foreach ($bin in @($eraDef.WorldBin, $eraDef.AuthBin)) {

        $procName = [System.IO.Path]::GetFileNameWithoutExtension($bin)
        $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -and $_.Path.StartsWith($installDir, [StringComparison]::OrdinalIgnoreCase) }

        if (-not $procs) {
            Write-Info "$bin not running."
            continue
        }

        foreach ($proc in $procs) {
            if (-not $PSCmdlet.ShouldProcess("$bin (PID $($proc.Id))", 'stop')) { continue }

            Write-Info "Asking $bin (PID $($proc.Id)) to close — it flushes to MySQL on the way out."
            $proc.CloseMainWindow() | Out-Null

            if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
                Write-Ok "$bin exited cleanly."
            } else {
                Write-Warn "$bin did not exit within ${TimeoutSeconds}s — killing it."
                Stop-Process -Id $proc.Id -Force
            }
        }
    }
}
