<#
    .SYNOPSIS
    Opens the six server ports on the private network profile only.

    .DESCRIPTION
    -Profile Private means these ports open on your home network and stay shut
    on public Wi-Fi. Requires an elevated PowerShell.

    .EXAMPLE
    .\07-Open-Firewall.ps1

    .EXAMPLE
    .\07-Open-Firewall.ps1 -Remove
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RuleName = 'WoW Private Servers',
    [switch]$Remove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

Assert-Administrator -Because 'Firewall rules need Administrator rights.'

$ports = @()
foreach ($era in Get-WowLabEra -Era all) {
    $ports += $era.AuthPort
    $ports += $era.WorldPort
}
$ports = $ports | Sort-Object

$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue

if ($Remove) {
    if ($existing) {
        if ($PSCmdlet.ShouldProcess($RuleName, 'remove firewall rule')) {
            $existing | Remove-NetFirewallRule
        }
        Write-Ok "Removed '$RuleName'."
    } else {
        Write-Info "No rule named '$RuleName' to remove."
    }
    return
}

if ($existing) {
    Write-Info "Rule '$RuleName' already exists — replacing it so the port list stays correct."
    if ($PSCmdlet.ShouldProcess($RuleName, 'remove existing rule')) {
        $existing | Remove-NetFirewallRule
    }
}

Write-Step "Opening TCP $($ports -join ', ') on the Private profile"

if ($PSCmdlet.ShouldProcess($RuleName, 'create firewall rule')) {
    New-NetFirewallRule -DisplayName $RuleName `
        -Direction Inbound -Protocol TCP -LocalPort $ports `
        -Action Allow -Profile Private | Out-Null
}

Write-Ok "Created '$RuleName'."

foreach ($era in Get-WowLabEra -Era all) {
    Write-Info "$($era.Name): auth $($era.AuthPort), world $($era.WorldPort)"
}

Write-Host ''
Write-Warn 'Give the PC a DHCP reservation in the router as well.'
Write-Info 'If the PC IP changes, every realmlist entry and every phone client breaks at once.'
