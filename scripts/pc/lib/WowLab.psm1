<#
    WowLab.psm1 — shared helpers for the triple-era WoW server toolkit.

    Everything the individual scripts need in common lives here: the per-era
    facts (ports, databases, repos, binary names), config loading, a MySQL
    wrapper that keeps the password off the command line, and a patcher for
    the cores' .conf files.

    Import with:  Import-Module "$PSScriptRoot\lib\WowLab.psm1" -Force
#>

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Console output helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [ ok ] $Message" -ForegroundColor Green
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [info] $Message" -ForegroundColor Gray
}

function Write-Warn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [warn] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Era definitions
#
# These are facts about the cores, not user preferences, so they live in code
# rather than in settings.psd1. Ports and database names match docs/00-project-plan.md.
# ---------------------------------------------------------------------------

$script:Eras = [ordered]@{

    classic = @{
        Key          = 'classic'
        Name         = 'Vanilla'
        ClientVer    = '1.12.1'
        ClientBuild  = 5875
        Family       = 'cmangos'
        Repo         = 'https://github.com/cmangos/mangos-classic.git'
        RepoBranch   = ''                                   # default branch
        SourceDir    = 'mangos-classic'
        BotRepo      = 'https://github.com/cmangos/playerbots.git'
        BotPath      = 'src/modules/Bots'
        InstallName  = 'classic'
        AuthPort     = 3724
        WorldPort    = 8085
        AuthBin      = 'realmd.exe'
        WorldBin     = 'mangosd.exe'
        AuthConf     = 'realmd.conf'
        WorldConf    = 'mangosd.conf'
        BotConf      = 'aiplayerbot.conf'
        BotConfDist  = 'src/modules/Bots/playerbot/aiplayerbotvanilla.conf.dist'
        Db           = @{ Auth = 'classicrealmd'; World = 'classicmangos'; Chars = 'classiccharacters' }
        ServiceAuth  = 'WoWClassicAuth'
        ServiceWorld = 'WoWClassicWorld'
    }

    tbc = @{
        Key          = 'tbc'
        Name         = 'TBC'
        ClientVer    = '2.4.3'
        ClientBuild  = 8606
        Family       = 'cmangos'
        Repo         = 'https://github.com/cmangos/mangos-tbc.git'
        RepoBranch   = ''
        SourceDir    = 'mangos-tbc'
        BotRepo      = 'https://github.com/cmangos/playerbots.git'
        BotPath      = 'src/modules/Bots'
        InstallName  = 'tbc'
        AuthPort     = 3725
        WorldPort    = 8086
        AuthBin      = 'realmd.exe'
        WorldBin     = 'mangosd.exe'
        AuthConf     = 'realmd.conf'
        WorldConf    = 'mangosd.conf'
        BotConf      = 'aiplayerbot.conf'
        BotConfDist  = 'src/modules/Bots/playerbot/aiplayerbottbc.conf.dist'
        Db           = @{ Auth = 'tbcrealmd'; World = 'tbcmangos'; Chars = 'tbccharacters' }
        ServiceAuth  = 'WoWTbcAuth'
        ServiceWorld = 'WoWTbcWorld'
    }

    wotlk = @{
        Key          = 'wotlk'
        Name         = 'WotLK'
        ClientVer    = '3.3.5a'
        ClientBuild  = 12340
        Family       = 'azerothcore'
        # mod-playerbots does NOT build against mainline AzerothCore. This fork
        # and this branch are required — see docs/01-pc-server-setup.md Step 4.
        Repo         = 'https://github.com/mod-playerbots/azerothcore-wotlk.git'
        RepoBranch   = 'Playerbot'
        SourceDir    = 'azerothcore-wotlk'
        BotRepo      = 'https://github.com/mod-playerbots/mod-playerbots.git'
        BotPath      = 'modules/mod-playerbots'
        InstallName  = 'wotlk'
        AuthPort     = 3726
        WorldPort    = 8087
        AuthBin      = 'authserver.exe'
        WorldBin     = 'worldserver.exe'
        AuthConf     = 'authserver.conf'
        WorldConf    = 'worldserver.conf'
        BotConf      = 'playerbots.conf'
        BotConfDist  = 'modules/mod-playerbots/conf/playerbots.conf.dist'
        Db           = @{ Auth = 'acore_auth'; World = 'acore_world'; Chars = 'acore_characters' }
        ServiceAuth  = 'WoWWotlkAuth'
        ServiceWorld = 'WoWWotlkWorld'
    }
}

function Get-WowLabEra {
    <#
        .SYNOPSIS
        Returns the definition hashtable for one era, or all three.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('classic', 'tbc', 'wotlk', 'all')]
        [string]$Era = 'all'
    )

    if ($Era -eq 'all') { return @($script:Eras.Values) }
    return $script:Eras[$Era]
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

function Get-WowLabConfig {
    <#
        .SYNOPSIS
        Loads config/settings.psd1 and validates the fields the scripts rely on.

        .DESCRIPTION
        Looks for settings.psd1 relative to the repository root unless -Path is
        given. Fails loudly on the placeholder password so a half-configured
        run cannot reach MySQL with a guessable credential.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) {
        # $PSScriptRoot here is <repo>\scripts\pc\lib — three levels below the repo root.
        $repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $Path = Join-Path $repoRoot 'config\settings.psd1'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("Config not found at '$Path'. Copy config\settings.example.psd1 to " +
               "config\settings.psd1 and fill it in first.")
    }

    $cfg = Import-PowerShellDataFile -LiteralPath $Path

    foreach ($key in @('LanIP', 'MySQL', 'Paths')) {
        if (-not $cfg.ContainsKey($key)) { throw "settings.psd1 is missing the '$key' section." }
    }

    if ($cfg.LanIP -eq '192.168.1.50') {
        Write-Warn "LanIP is still the example value 192.168.1.50 — set your PC's reserved LAN IP."
    }
    if ([string]::IsNullOrWhiteSpace($cfg.LanIP)) {
        throw "settings.psd1: LanIP must be set to your PC's LAN IP."
    }
    if ($cfg.MySQL.Password -eq 'CHANGE-ME') {
        throw "settings.psd1: set MySQL.Password to a real password before running anything."
    }

    return $cfg
}

function Get-WowLabInstallDir {
    <#
        .SYNOPSIS
        Absolute path where a given era's binaries, configs and map data live.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$EraDef
    )
    return (Join-Path $Config.Paths.Root $EraDef.InstallName)
}

function Get-WowLabSourceDir {
    <#
        .SYNOPSIS
        Absolute path to a given era's cloned source tree.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$EraDef
    )
    return (Join-Path $Config.Paths.Sources $EraDef.SourceDir)
}

function Get-WowLabClientDir {
    <#
        .SYNOPSIS
        Absolute path to the PC copy of a given era's game client, used for map extraction.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)]$EraDef
    )

    $clients = $Config.Paths.Clients
    if (-not $clients.ContainsKey($EraDef.Key)) {
        throw "settings.psd1: Paths.Clients has no entry for era '$($EraDef.Key)'."
    }
    return $clients[$EraDef.Key]
}

# ---------------------------------------------------------------------------
# MySQL
# ---------------------------------------------------------------------------

function Resolve-MySqlClient {
    <#
        .SYNOPSIS
        Locates mysql.exe (or mysqldump.exe), preferring the configured path.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [ValidateSet('mysql', 'mysqldump')][string]$Tool = 'mysql'
    )

    $configured = if ($Tool -eq 'mysql') { $Config.MySQL.ClientPath } else { $Config.MySQL.DumpPath }
    if ($configured -and (Test-Path -LiteralPath $configured)) { return $configured }

    $onPath = Get-Command "$Tool.exe" -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    # Common default install locations, newest first.
    $guesses = Get-ChildItem 'C:\Program Files\MySQL' -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "bin\$Tool.exe" }

    foreach ($g in $guesses) {
        if (Test-Path -LiteralPath $g) { return $g }
    }

    throw ("Could not find $Tool.exe. Add it to PATH or set MySQL." +
           $(if ($Tool -eq 'mysql') { 'ClientPath' } else { 'DumpPath' }) + " in settings.psd1.")
}

function New-MySqlDefaultsFile {
    <#
        .SYNOPSIS
        Writes a temporary my.cnf-style credentials file.

        .DESCRIPTION
        Passing --password on the command line exposes it to anyone who can list
        processes. --defaults-extra-file does not. The caller is responsible for
        deleting the returned path.
    #>
    param(
        [Parameter(Mandatory)]$Config,
        [string]$User,
        [string]$Password
    )

    if (-not $User)     { $User     = $Config.MySQL.User }
    if (-not $Password) { $Password = $Config.MySQL.Password }

    $file = [System.IO.Path]::GetTempFileName()
    $lines = @(
        '[client]'
        "user=$User"
        "password=$Password"
        "host=$($Config.MySQL.Host)"
        "port=$($Config.MySQL.Port)"
    )
    Set-Content -LiteralPath $file -Value $lines -Encoding ASCII
    return $file
}

function Invoke-MySql {
    <#
        .SYNOPSIS
        Runs a query or a .sql file against MySQL and returns stdout lines.

        .PARAMETER AsRoot
        Use MySQL.RootUser plus the -RootPassword argument instead of the
        dedicated 'wow' user. Needed only for creating databases and users.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Query')]
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory, ParameterSetName = 'Query')][string]$Query,
        [Parameter(Mandatory, ParameterSetName = 'File')][string]$File,
        [string]$Database,
        [switch]$AsRoot,
        [string]$RootPassword,
        [switch]$Raw
    )

    $exe = Resolve-MySqlClient -Config $Config -Tool mysql

    if ($AsRoot) {
        $defaults = New-MySqlDefaultsFile -Config $Config -User $Config.MySQL.RootUser -Password $RootPassword
    } else {
        $defaults = New-MySqlDefaultsFile -Config $Config
    }

    try {
        $mysqlArgs = @("--defaults-extra-file=$defaults")
        if ($Raw) { $mysqlArgs += @('--batch', '--skip-column-names') }
        if ($Database) { $mysqlArgs += $Database }

        if ($PSCmdlet.ParameterSetName -eq 'File') {
            if (-not (Test-Path -LiteralPath $File)) { throw "SQL file not found: $File" }
            $output = Get-Content -LiteralPath $File -Raw | & $exe @mysqlArgs 2>&1
        } else {
            $output = $Query | & $exe @mysqlArgs 2>&1
        }

        if ($LASTEXITCODE -ne 0) {
            throw "mysql exited with code $LASTEXITCODE`n$($output -join [Environment]::NewLine)"
        }
        return $output
    } finally {
        Remove-Item -LiteralPath $defaults -Force -ErrorAction SilentlyContinue
    }
}

function Test-MySqlConnection {
    <#
        .SYNOPSIS
        Returns $true if the configured 'wow' user can reach the server.
    #>
    param([Parameter(Mandatory)]$Config)

    try {
        Invoke-MySql -Config $Config -Query 'SELECT 1;' -Raw | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
# Core .conf file editing
# ---------------------------------------------------------------------------

function Set-ConfValue {
    <#
        .SYNOPSIS
        Sets Key = Value in a CMaNGOS/AzerothCore .conf file.

        .DESCRIPTION
        Rewrites an existing assignment in place, uncommenting it if it is
        commented out, and appends the setting if it is not present at all.
        Both cores use the same 'Key = Value' format, with '#' comments.

        Values that must be quoted in the file (connection strings, paths)
        should be passed with their quotes already included.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    if (-not (Test-Path -LiteralPath $Path)) { throw "Config file not found: $Path" }

    $lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $Path)
    $pattern = '^\s*#?\s*' + [regex]::Escape($Key) + '\s*='
    $newLine = "$Key = $Value"
    $replaced = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = $newLine
            $replaced = $true
            break   # only the first occurrence; later duplicates would override it anyway
        }
    }

    if (-not $replaced) {
        $lines.Add('')
        $lines.Add("# added by WowLab toolkit")
        $lines.Add($newLine)
    }

    if ($PSCmdlet.ShouldProcess($Path, "set $Key")) {
        Set-Content -LiteralPath $Path -Value $lines -Encoding UTF8
    }

    return $replaced
}

function Get-ConfValue {
    <#
        .SYNOPSIS
        Reads the active (uncommented) value of Key from a .conf file, or $null.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*?)\s*$'
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match $pattern) { return $Matches[1] }
    }
    return $null
}

function Initialize-ConfFromDist {
    <#
        .SYNOPSIS
        Copies a .conf.dist to its .conf name if the .conf does not exist yet.

        .DESCRIPTION
        Never overwrites an existing .conf — hand edits survive re-runs. Returns
        the destination path.
    #>
    param(
        [Parameter(Mandatory)][string]$DistPath,
        [Parameter(Mandatory)][string]$DestPath,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $DestPath) -and -not $Force) {
        Write-Info "$([System.IO.Path]::GetFileName($DestPath)) already exists — keeping it."
        return $DestPath
    }

    if (-not (Test-Path -LiteralPath $DistPath)) {
        throw "Template not found: $DistPath"
    }

    Copy-Item -LiteralPath $DistPath -Destination $DestPath -Force
    Write-Ok "Created $([System.IO.Path]::GetFileName($DestPath)) from .dist"
    return $DestPath
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------

function Resolve-ToolPath {
    <#
        .SYNOPSIS
        Finds the first of several candidate executable names under a set of directories.

        .DESCRIPTION
        Extractor binaries are named differently across cores and have been
        renamed upstream over time, so every call site passes a candidate list
        rather than one hard-coded name.
    #>
    param(
        [Parameter(Mandatory)][string[]]$Candidates,
        [Parameter(Mandatory)][string[]]$SearchDirs
    )

    foreach ($dir in $SearchDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($name in $Candidates) {
            $hit = Get-ChildItem -LiteralPath $dir -Filter $name -Recurse -File -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    return $null
}

function Test-PortListening {
    <#
        .SYNOPSIS
        Returns $true if something is listening on the given local TCP port.
    #>
    param([Parameter(Mandatory)][int]$Port)

    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    return [bool]$listener
}

function Assert-Administrator {
    <#
        .SYNOPSIS
        Throws unless the current session is elevated.
    #>
    param([string]$Because = 'This script needs Administrator rights.')

    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "$Because Re-run this from an elevated PowerShell window."
    }
}

Export-ModuleMember -Function @(
    'Write-Step', 'Write-Ok', 'Write-Info', 'Write-Warn', 'Write-Fail'
    'Get-WowLabEra', 'Get-WowLabConfig'
    'Get-WowLabInstallDir', 'Get-WowLabSourceDir', 'Get-WowLabClientDir'
    'Resolve-MySqlClient', 'Invoke-MySql', 'Test-MySqlConnection'
    'Set-ConfValue', 'Get-ConfValue', 'Initialize-ConfFromDist'
    'Resolve-ToolPath', 'Test-PortListening', 'Assert-Administrator'
)
