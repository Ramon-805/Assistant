<#
    .SYNOPSIS
    Checks that everything needed to build the cores is installed.

    .DESCRIPTION
    Run this before anything else. It only reports; it installs nothing and
    changes nothing. A red line here is a build failure you get to skip.

    .EXAMPLE
    .\00-Check-Prereqs.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\WowLab.psm1') -Force

$problems = 0

function Test-Tool {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Command,
        [string]$VersionArg = '--version',
        [string]$Hint
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Fail "$Name not found on PATH."
        if ($Hint) { Write-Info $Hint }
        return $false
    }

    $version = try {
        (& $Command $VersionArg 2>&1 | Select-Object -First 1) -replace '\s+', ' '
    } catch {
        '(version check failed)'
    }

    Write-Ok "$Name — $version"
    return $true
}

Write-Step 'Build tools'

if (-not (Test-Tool -Name 'Git' -Command 'git' -Hint 'https://git-scm.com/download/win')) { $problems++ }
if (-not (Test-Tool -Name 'CMake' -Command 'cmake' -Hint 'Need 3.22+. Tick "Add to PATH" during install.')) {
    $problems++
} else {
    $cmakeVersion = (cmake --version | Select-Object -First 1) -replace '[^\d\.]', ''
    try {
        if ([version]($cmakeVersion -split '-')[0] -lt [version]'3.22') {
            Write-Fail "CMake $cmakeVersion is too old — 3.22 or newer required."
            $problems++
        }
    } catch {
        Write-Warn "Could not parse the CMake version string; check it is 3.22+."
    }
}

Write-Step 'Visual Studio 2022 with the C++ workload'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhere) {
    $vs = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property displayName 2>$null
    if ($vs) {
        Write-Ok "$vs (with Desktop development with C++)"
    } else {
        Write-Fail 'Visual Studio found, but the "Desktop development with C++" workload is missing.'
        Write-Info 'Open the Visual Studio Installer, Modify, tick that workload.'
        $problems++
    }
} else {
    Write-Fail 'Visual Studio 2022 not found.'
    Write-Info 'Community edition is fine. Select "Desktop development with C++" only.'
    $problems++
}

Write-Step 'MySQL'

$config = $null
try {
    $config = Get-WowLabConfig
} catch {
    Write-Warn "config\settings.psd1 not readable yet — skipping the connection test."
    Write-Info $_.Exception.Message
}

try {
    $mysqlExe = if ($config) { Resolve-MySqlClient -Config $config } else { (Get-Command mysql.exe -ErrorAction Stop).Source }
    Write-Ok "mysql client — $mysqlExe"
} catch {
    Write-Fail 'mysql.exe not found. Install MySQL 8.0, or set MySQL.ClientPath in settings.psd1.'
    $problems++
}

if ($config) {
    if (Test-MySqlConnection -Config $config) {
        Write-Ok "Connected to MySQL as '$($config.MySQL.User)'."
    } else {
        Write-Warn "Could not connect as '$($config.MySQL.User)' — run 01-Create-Databases.ps1 to create the user."
    }
}

Write-Step 'Libraries (CMaNGOS needs these; CMake will fail without them)'

foreach ($lib in @(
    @{ Name = 'Boost';   Var = 'BOOST_ROOT';   Hint = 'Boost 1.78+. Set BOOST_ROOT to the install folder.' }
    @{ Name = 'OpenSSL'; Var = 'OPENSSL_ROOT_DIR'; Hint = 'OpenSSL 3.x Win64. Set OPENSSL_ROOT_DIR to the install folder.' }
)) {
    $value = [Environment]::GetEnvironmentVariable($lib.Var)
    if ($value -and (Test-Path -LiteralPath $value)) {
        Write-Ok "$($lib.Name) — $($lib.Var)=$value"
    } elseif ($value) {
        Write-Fail "$($lib.Name): $($lib.Var) is set to '$value' but that path does not exist."
        $problems++
    } else {
        Write-Warn "$($lib.Name): $($lib.Var) is not set. CMake may still find it, but set it if configure fails."
        Write-Info $lib.Hint
    }
}

Write-Step 'Disk space'

if ($config) {
    $root = $config.Paths.Root
    $drive = try { (Get-Item -LiteralPath $root -ErrorAction Stop).PSDrive } catch {
        Get-PSDrive -Name ($root.Substring(0, 1)) -ErrorAction SilentlyContinue
    }
    if ($drive -and $drive.Free) {
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGb -lt 110) {
            Write-Warn "$freeGb GB free on $($drive.Name): — the full three-era build budgets ~110 GB."
        } else {
            Write-Ok "$freeGb GB free on $($drive.Name):"
        }
    }
}

Write-Step 'Game clients (needed for map extraction)'

if ($config) {
    foreach ($era in Get-WowLabEra -Era all) {
        $clientDir = Get-WowLabClientDir -Config $config -EraDef $era
        if (Test-Path -LiteralPath $clientDir) {
            Write-Ok "$($era.Name) $($era.ClientVer) — $clientDir"
        } else {
            Write-Warn "$($era.Name) $($era.ClientVer) client not at '$clientDir' (only needed when you reach that era)."
        }
    }
}

Write-Host ''
if ($problems -gt 0) {
    Write-Fail "$problems blocking problem(s) above. Fix them before building."
    exit 1
}
Write-Ok 'Prerequisites look good.'
