# Triple-Era WoW with Bots — PC Server, Phone Client

Play Classic (1.12.1), TBC (2.4.3) and WotLK (3.3.5a) on a Galaxy Z Fold, with AI
bots populating the world, against private servers on a home PC. The PC stays
usable by other people and shows nothing on the living room monitor.

The plan lives in [`docs/`](docs/). This repo is the toolkit that carries it out:
PowerShell scripts that automate the fiddly, repeat-three-times parts and refuse
to make the mistakes the docs warn about.

---

## Start here

**Phase 0 happens on the phone and needs nothing from this repo.** Install
Winlator, copy the 1.12.1 client over, get to the login screen. If that fails,
nothing else matters — and you've spent an evening instead of a weekend finding
out. See [`docs/02-zfold-client-setup.md`](docs/02-zfold-client-setup.md).

Once the client renders, the PC work begins:

```powershell
# One-time
Copy-Item config\settings.example.psd1 config\settings.psd1
notepad config\settings.psd1        # LAN IP, MySQL password, paths

cd scripts\pc
.\00-Check-Prereqs.ps1              # verifies the build environment
.\01-Create-Databases.ps1           # nine databases + the 'wow' user

# Per era — classic first, all the way through, before starting the next
.\02-Clone-Sources.ps1     -Era classic
.\03-Build-Core.ps1        -Era classic     # 20-60 min
#   ... import the world database (see "What you still do by hand")
.\04-Write-Configs.ps1     -Era classic
.\05-Extract-MapData.ps1   -Era classic     # 3-7 HOURS, start before bed
.\06-Set-RealmlistAddress.ps1 -Era classic
.\07-Open-Firewall.ps1                      # elevated; once, covers all six ports

.\Start-Servers.ps1 -Era classic
.\Test-Deployment.ps1 -Era classic          # the pre-phone checklist, runnable

# Then the phone
..\phone\Write-Realmlist.ps1 -Era classic
```

Repeat `02` → `06` for `tbc`, then `wotlk`. Do not start TBC before vanilla works
end to end; adding all three at once is how a weekend disappears.

---

## What the scripts do

| Script | What it handles |
|---|---|
| `00-Check-Prereqs.ps1` | Visual Studio C++ workload, CMake 3.22+, Git, MySQL, Boost/OpenSSL, disk space, clients present. Reports only. |
| `01-Create-Databases.ps1` | The nine databases and the `wow` user. Prompts for the root password instead of storing it. |
| `02-Clone-Sources.ps1` | Clones the core **and** its playerbots module to the exact path the build expects. For WotLK, pins the `Playerbot` branch of the fork. |
| `03-Build-Core.ps1` | CMake configure + build + install, always with `BUILD_PLAYERBOTS=ON`, then verifies the flag landed in the CMake cache. |
| `04-Write-Configs.ps1` | Creates `.conf` files from `.dist`, fills in databases, ports, `DataDir`, and turns on mmap pathfinding. Never clobbers hand edits. |
| `05-Extract-MapData.ps1` | The four-stage extraction, in order, resumable, logged, then moves `dbc/maps/vmaps/mmaps` next to the binaries. |
| `06-Set-RealmlistAddress.ps1` | Sets the realm address to your LAN IP. Refuses `127.0.0.1` outright. |
| `07-Open-Firewall.ps1` | One rule, six ports, Private profile only. |
| `08-Install-Services.ps1` | NSSM services so nothing shows on screen and everything starts at boot. |
| `09-Backup-Characters.ps1` | Dumps the character and auth databases — the parts you cannot rebuild from a repo. `-RegisterScheduledTask` for weekly. |
| `Start-Servers.ps1` / `Stop-Servers.ps1` | Auth first then world on the way up, the reverse on the way down, so characters flush to MySQL cleanly. |
| `Test-Deployment.ps1` | Runs the doc's whole "before touching the phone" checklist and names the fix for every failure. |
| `phone\Write-Realmlist.ps1` | Writes `realmlist.wtf` / `Config.wtf` lines, home and away (Tailscale) variants. |

Everything reads from `config/settings.psd1`, so your LAN IP and password are
written down exactly once.

---

## The mistakes this encodes

The docs flag several failures that cost an evening each. The scripts make them
hard to hit:

- **Building CMaNGOS without `BUILD_PLAYERBOTS`** gives a working server, no
  bots, and no error saying why. `03-Build-Core.ps1` always passes it and then
  greps `CMakeCache.txt` to confirm it stuck.
- **`127.0.0.1` in the realmlist table** lets the phone authenticate and then
  sends it to connect to *itself*. `06-Set-RealmlistAddress.ps1` throws rather
  than write a loopback address, and `Test-Deployment.ps1` fails on one.
- **Missing mmaps** make bots spawn and stand motionless. Extraction refuses to
  silently skip stage 4, and both `04-Write-Configs.ps1` and `Test-Deployment.ps1`
  check that pathfinding is switched on in the config.
- **Mainline AzerothCore + mod-playerbots** does not build. The WotLK repo and
  branch are pinned in the era table, not left to a copy-paste.
- **Applying the wrong expansion's bot SQL** produces bizarre behaviour rather
  than a clean error. Each era's database names are fixed in one place.

Two deliberate departures from the docs, both narrowing rather than widening:

- The `wow` MySQL user is granted on the nine project databases only, not
  `*.*` — the servers never need more, and a leaked server config then cannot
  own the whole instance.
- MySQL passwords go through a temporary defaults file rather than
  `-p` on the command line, where anyone listing processes can read them.

---

## What you still do by hand

Automating these would mean guessing at interactive tools or at your intent:

- **Installing** Visual Studio, MySQL, Git, CMake, Boost, OpenSSL. `00-Check-Prereqs.ps1`
  tells you which are missing.
- **Obtaining the game clients.** You need your own legally-obtained copies, kept
  entirely separate from any Battle.net-linked install.
- **Importing the world databases.** CMaNGOS ships an interactive installer
  script — run it once to generate its config, set `PLAYERBOTS_DB="YES"`, run it
  again and choose Full installation. AzerothCore's auto-updater does it on the
  first `worldserver.exe` launch. Both are documented in
  [`docs/01-pc-server-setup.md`](docs/01-pc-server-setup.md).
- **Everything on the phone.** Winlator containers, graphics driver choice,
  thermal settings, controls. See [`docs/02-zfold-client-setup.md`](docs/02-zfold-client-setup.md)
  and `scripts/phone/ingame-tuning.txt`.

---

## Testing

```powershell
pwsh -File tests\Test-WowLab.ps1
```

Covers the era table (ports, databases and build numbers must not collide or
drift) and the `.conf` patcher, which is the piece most likely to quietly
corrupt a config file. Runs on any platform — no Windows or server rebuild
needed to check a change.

---

## Layout

```
docs/           the three planning documents
config/         settings.example.psd1 -> copy to settings.psd1 (gitignored)
sql/            database creation
scripts/pc/     numbered setup steps, plus start/stop/verify
scripts/pc/lib/ WowLab.psm1 — era table, config loading, MySQL, .conf patching
scripts/phone/  realmlist generation and in-game tuning commands
tests/          platform-independent tests
logs/, out/     generated at runtime (gitignored)
```

Progress tracking: [`PROGRESS.md`](PROGRESS.md).
