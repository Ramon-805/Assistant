<#
    Copy this file to config\settings.psd1 and fill it in.

    settings.psd1 is gitignored because it holds your MySQL password.
    Everything in the toolkit reads from it, so the values below are the only
    place your LAN IP and credentials are written down.
#>
@{
    # Your PC's LAN IP. Give the PC a DHCP reservation in the router first —
    # if this changes, every realmlist entry and every phone client breaks at once.
    LanIP = '192.168.1.50'

    # Tailscale address (100.x.x.x) for playing away from home. Leave empty
    # until Tailscale is installed; scripts/phone/Write-Realmlist.ps1 uses it
    # to emit the '-away' realmlist variants.
    TailscaleIP = ''

    MySQL = @{
        Host     = '127.0.0.1'
        Port     = 3306
        User     = 'wow'
        Password = 'CHANGE-ME'

        # Only used by 01-Create-Databases.ps1, which prompts for the root
        # password rather than storing it here.
        RootUser = 'root'

        # Leave empty to auto-detect from PATH and C:\Program Files\MySQL.
        ClientPath = ''
        DumpPath   = ''
    }

    Paths = @{
        # Compiled servers land in <Root>\classic, <Root>\tbc, <Root>\wotlk.
        Root    = 'C:\wow'

        # Source checkouts.
        Sources = 'C:\wow\src'

        # Weekly character-database dumps.
        Backups = 'D:\backups\wow'

        # PC copies of the game clients, used for map/vmap/mmap extraction.
        # These can be deleted after extraction if space is tight.
        Clients = @{
            classic = 'C:\wow\clients\1.12.1'
            tbc     = 'C:\wow\clients\2.4.3'
            wotlk   = 'C:\wow\clients\3.3.5a'
        }

        # nssm.exe, for installing the servers as Windows services (Step 6).
        # Leave empty if you are using the batch launcher instead.
        Nssm = ''
    }

    Bots = @{
        # Start at 50 and raise once you know the PC handles it.
        MinRandomBots = 50
        MaxRandomBots = 100
    }
}
