# PC Setup — Three Server Cores with Bots

Everything in this document happens on the living room PC. None of it puts anything on screen once running.

---

## Prerequisites (install once)

| Software | Notes |
|---|---|
| **Visual Studio 2022** | Community edition. Select "Desktop development with C++" workload only. |
| **CMake** | 3.22+. Add to PATH during install. |
| **Git** | Needed for cloning with submodules. |
| **MySQL 8.0** | One instance serves all three cores. Set a root password you'll remember. |
| **HeidiSQL** or MySQL Workbench | For importing SQL and editing the realmlist table. |
| **Boost 1.78+** | CMaNGOS needs this. Prebuilt Windows binaries are fine. |
| **OpenSSL 3.x** | Win64 build. |
| **7-Zip** | For the client archives. |

You also need a **PC copy of each client** (1.12.1, 2.4.3, 3.3.5a). These are used for map extraction — the extractors read the client's MPQ/data files to build the server's navigation data. You can delete the PC copies afterward if space is tight, but keep them if you might rebuild.

---

## Step 1 — MySQL and database layout

One MySQL instance, nine databases. Keep the naming obvious:

```sql
-- Vanilla (CMaNGOS-classic)
CREATE DATABASE classicmangos     DEFAULT CHARSET utf8mb4;
CREATE DATABASE classiccharacters DEFAULT CHARSET utf8mb4;
CREATE DATABASE classicrealmd     DEFAULT CHARSET utf8mb4;

-- TBC (CMaNGOS-tbc)
CREATE DATABASE tbcmangos     DEFAULT CHARSET utf8mb4;
CREATE DATABASE tbccharacters DEFAULT CHARSET utf8mb4;
CREATE DATABASE tbcrealmd     DEFAULT CHARSET utf8mb4;

-- WotLK (AzerothCore)
CREATE DATABASE acore_world      DEFAULT CHARSET utf8mb4;
CREATE DATABASE acore_characters DEFAULT CHARSET utf8mb4;
CREATE DATABASE acore_auth       DEFAULT CHARSET utf8mb4;
```

Create a dedicated user rather than using root:

```sql
CREATE USER 'wow'@'localhost' IDENTIFIED BY 'pick-something';
GRANT ALL PRIVILEGES ON *.* TO 'wow'@'localhost';
FLUSH PRIVILEGES;
```

---

## Step 2 — Vanilla: CMaNGOS-classic with playerbots

### Clone

```bash
git clone https://github.com/cmangos/mangos-classic.git
cd mangos-classic
git clone https://github.com/cmangos/playerbots.git src/modules/Bots
```

### Build

Open CMake GUI. Source = the repo, build = a `build` subfolder.

**Critical:** tick `BUILD_PLAYERBOTS` before configuring. This is the single most commonly missed step — without it you get a working server with no bots and no obvious error explaining why.

Configure → Generate → open the generated solution in Visual Studio → build **Release** → x64.

### Database

CMaNGOS provides an installer script that handles the world DB, character DB, realm DB, and the playerbots DB in one pass. Run it once to generate its config file, then edit that config and add:

```
PLAYERBOTS_DB="YES"
```

Then run it again and choose **Full installation**. It will populate everything including the bot tables.

If you're doing it manually instead: apply the SQL from `src/modules/Bots/sql/characters/` to your characters DB and `src/modules/Bots/sql/world/` to your world DB. Note that some `.sql` files live in `vanilla`, `tbc`, or `wotlk` subfolders — **only apply the ones matching your core's expansion.** Applying the wrong set produces bots that behave bizarrely rather than a clean error.

### Config

Copy from the build output and rename, dropping `.dist`:

- `mangosd.conf.dist` → `mangosd.conf`
- `realmd.conf.dist` → `realmd.conf`
- `src/modules/Bots/playerbot/aiplayerbotvanilla.conf.dist` → `aiplayerbot.conf`

Put all three in the same folder as the compiled binaries.

In `mangosd.conf`:
```
LoginDatabaseInfo     = "127.0.0.1;3306;wow;yourpassword;classicrealmd"
WorldDatabaseInfo     = "127.0.0.1;3306;wow;yourpassword;classicmangos"
CharacterDatabaseInfo = "127.0.0.1;3306;wow;yourpassword;classiccharacters"
WorldServerPort       = 8085
```

In `realmd.conf`:
```
LoginDatabaseInfo = "127.0.0.1;3306;wow;yourpassword;classicrealmd"
RealmServerPort   = 3724
```

In `aiplayerbot.conf`, the settings that matter most at the start:
```
AiPlayerbot.Enabled = 1
AiPlayerbot.MinRandomBots = 50
AiPlayerbot.MaxRandomBots = 100
AiPlayerbot.RandomBotAutologin = 1
```
Start at 50. Raise once you know the PC handles it.

### Extract map data

Copy the extractor executables from the build output into your **PC copy of the 1.12.1 client folder** and run in this order:

1. `map-extractor.exe` — 10–20 min
2. `vmap-extractor.exe` — 20–40 min
3. `vmap-assembler.exe` — 10 min
4. `mmap-generator.exe` — **2–6 hours**

Start the mmap generator before bed. Bots need mmaps to pathfind; without them they stand still and look broken.

Move the resulting `maps`, `vmaps`, `mmaps`, `dbc` folders next to `mangosd.exe`.

### Realmlist — the step everyone gets wrong

In the `classicrealmd` database, `realmlist` table, set `address` to your PC's **LAN IP**, not `127.0.0.1`:

```sql
UPDATE realmlist SET address = '192.168.1.50', port = 8085 WHERE id = 1;
```

With `127.0.0.1` there, the phone authenticates successfully and then tries to connect to *itself* for the world server. You get "world server is down" with no clue why.

---

## Step 3 — TBC: CMaNGOS-tbc

Identical process. Differences only:

- Repo: `https://github.com/cmangos/mangos-tbc.git`
- Config file: `aiplayerbottbc.conf.dist`
- SQL: use the `tbc` subfolders
- Databases: `tbcmangos` / `tbccharacters` / `tbcrealmd`
- Ports: realm **3725**, world **8086**
- Extract from your 2.4.3 client

This goes much faster the second time. Budget 2–3 hours, most of it extraction.

---

## Step 4 — WotLK: AzerothCore with mod-playerbots

**Important:** `mod-playerbots` does not work with mainline AzerothCore. It requires a custom fork — the `Playerbot` branch of `mod-playerbots/azerothcore-wotlk`. Cloning stock AzerothCore and adding the module will fail to build.

```bash
git clone --branch Playerbot https://github.com/mod-playerbots/azerothcore-wotlk.git
cd azerothcore-wotlk/modules
git clone https://github.com/mod-playerbots/mod-playerbots.git
```

Build with CMake as usual (AzerothCore's own install guide covers this well). Then:

- Run the DB auto-updater on first `worldserver.exe` launch
- Configs: `worldserver.conf`, `authserver.conf`, `playerbots.conf` — all in `configs/`, drop the `.dist`
- Ports: auth **3726**, world **8087**
- Extract maps from the 3.3.5a client using AzerothCore's extractors (same four-stage process, mmaps again the long pole)

Update the realm address in `acore_auth.realmlist` the same way as above.

The Playerbots wiki is genuinely good — it documents the chat commands, raid strategies, and recommended performance configs. Worth reading before tuning bot counts, since the config surface is large.

---

## Step 5 — Firewall

One rule, all six ports:

```powershell
New-NetFirewallRule -DisplayName "WoW Private Servers" -Direction Inbound `
  -Protocol TCP -LocalPort 3724,3725,3726,8085,8086,8087 -Action Allow `
  -Profile Private
```

Note `-Profile Private` — this opens the ports on your home network only, not on public Wi-Fi.

Also give the PC a **DHCP reservation** in your new router so its IP never changes. If it changes, every realmlist entry and every phone client breaks at once.

---

## Step 6 — Make it invisible

Three options, increasing discretion:

**Minimized console** — simplest. Six console windows, minimized. Works, slightly untidy.

**Batch launcher with hidden windows** — one script starts everything:
```batch
@echo off
start "" /min "C:\wow\classic\realmd.exe"
timeout /t 3
start "" /min "C:\wow\classic\mangosd.exe"
start "" /min "C:\wow\tbc\realmd.exe"
timeout /t 3
start "" /min "C:\wow\tbc\mangosd.exe"
start "" /min "C:\wow\wotlk\authserver.exe"
timeout /t 3
start "" /min "C:\wow\wotlk\worldserver.exe"
```

**Windows services via NSSM** — fully invisible, starts at boot, no windows at all. `nssm install WoWClassicWorld "C:\wow\classic\mangosd.exe"`. This is the right answer if the servers are staying up permanently.

The world servers accept console commands, so if you run them as services you'll want an in-game GM account instead. Create one before converting:
```
account create youraccount yourpassword
account set gmlevel youraccount 3 -1
```

---

## Step 7 — Backups

Characters live in MySQL. One scheduled task, weekly:

```batch
mysqldump -u wow -pyourpassword --databases classiccharacters tbccharacters acore_characters > D:\backups\wow-chars-%date%.sql
```

World databases are reproducible from the repos; character databases are not.

---

## Verification checklist

Before touching the phone, confirm on the PC:

- [ ] All three auth servers listening (`netstat -an | findstr "3724 3725 3726"`)
- [ ] Local client connects to each realm
- [ ] Account created, character created, world loads
- [ ] `.bot add <name>` produces a bot that *moves*
- [ ] Random bots are visible in the world after a few minutes
- [ ] `realmlist` table shows LAN IP, not 127.0.0.1
- [ ] Another device on the LAN can reach the ports

If bots spawn but stand motionless, your mmaps are missing or in the wrong folder. That's the single most common bot failure.
