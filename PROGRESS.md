# Progress

Tick as you go. Each phase is independently verifiable, so when something breaks
you know which piece broke.

---

## Decisions to make before starting

- [ ] **Bot density.** Starting at 50 (`Bots.MinRandomBots` in settings.psd1). Raise once the PC proves it keeps up.
- [ ] **XP rates.** Sessions are limited by phone thermals; 2x-3x means 30 minutes accomplishes something real.
- [ ] **Remote play.** Tailscale on both devices, or LAN only?

---

## Phase 0 — Prove the client works *(phone, ~1 evening)*

No server needed. If this fails, nothing else matters.

- [x] Winlator installed — 11.1 "Final", from the official GitHub releases
- [ ] 1.12.1 client copied to `Internal Storage/Download/wow-vanilla/` (internal storage, not external media)
- [ ] Container created — Turnip driver, DXVK, 1600x900, Box64 Performance, 4096 MB RAM
- [ ] Shortcut to `WoW.exe`, launches
- [ ] **Exit criteria:** login screen, music playing, 10 minutes without a crash, phone warm but not hot

---

## Phase 1 — Vanilla server *(PC, ~half a day)*

- [ ] `config\settings.psd1` filled in — LAN IP, MySQL password, client paths
- [ ] PC has a DHCP reservation in the router
- [ ] `00-Check-Prereqs.ps1` clean
- [ ] `01-Create-Databases.ps1` — nine databases, `wow` user
- [ ] `02-Clone-Sources.ps1 -Era classic`
- [ ] `03-Build-Core.ps1 -Era classic` — confirms `BUILD_PLAYERBOTS=ON`
- [ ] World/character/realm databases imported (CMaNGOS installer, `PLAYERBOTS_DB="YES"`, Full installation)
- [ ] `04-Write-Configs.ps1 -Era classic`
- [ ] `05-Extract-MapData.ps1 -Era classic` — mmaps done (the multi-hour one)
- [ ] `06-Set-RealmlistAddress.ps1 -Era classic`
- [ ] Account created, character created, world loads from a **local PC client**
- [ ] `.bot add <name>` produces a bot that *moves*
- [ ] Random bots visible in the world after a few minutes
- [ ] `Test-Deployment.ps1 -Era classic` passes
- [ ] **Exit criteria:** logged in on the PC, working bot

---

## Phase 2 — Connect the phone to vanilla *(~1 hour)*

- [ ] `07-Open-Firewall.ps1` run elevated
- [ ] `phone\Write-Realmlist.ps1 -Era classic`
- [ ] `realmlist.wtf` copied to the phone client root and set **read-only**
- [ ] Logged in over Wi-Fi
- [ ] `/console maxfps 30` and the rest of `scripts\phone\ingame-tuning.txt`
- [ ] **Exit criteria:** questing on the phone with bots in the party

---

## Phase 3 — TBC *(~2-3 hours)*

- [ ] `02-Clone-Sources.ps1 -Era tbc`
- [ ] `03-Build-Core.ps1 -Era tbc`
- [ ] Databases imported — **`tbc` SQL subfolders only**
- [ ] `04-Write-Configs.ps1 -Era tbc`
- [ ] `05-Extract-MapData.ps1 -Era tbc` (from the 2.4.3 client)
- [ ] `06-Set-RealmlistAddress.ps1 -Era tbc`
- [ ] `Test-Deployment.ps1 -Era tbc` passes
- [ ] Phone container for 2.4.3, realmlist on port 3725
- [ ] **Exit criteria:** TBC playable on the phone

---

## Phase 4 — WotLK *(~half a day)*

Heaviest on the phone, most involved on the PC. Last for a reason.

- [ ] `02-Clone-Sources.ps1 -Era wotlk` — the `Playerbot` fork branch
- [ ] `03-Build-Core.ps1 -Era wotlk`
- [ ] DB auto-updater run on first `worldserver.exe` launch
- [ ] `04-Write-Configs.ps1 -Era wotlk`
- [ ] `05-Extract-MapData.ps1 -Era wotlk` (from the 3.3.5a client)
- [ ] `06-Set-RealmlistAddress.ps1 -Era wotlk`
- [ ] `Test-Deployment.ps1 -Era wotlk` passes
- [ ] Phone container for 3.3.5a — 1280x720, video memory 3072
- [ ] `SET realmList "<ip>:3726"` in `WTF\Config.wtf`
- [ ] **Exit criteria:** WotLK playable on the phone

---

## Phase 5 — Polish

- [ ] GM account created **before** converting to services
      (`account create ...` / `account set gmlevel ... 3 -1`)
- [ ] `08-Install-Services.ps1 -Era all` — invisible, starts at boot
- [ ] `09-Backup-Characters.ps1 -RegisterScheduledTask` — weekly
- [ ] Bot control addon installed on the phone clients (see the Playerbots wiki AddOns page)
- [ ] XP rates tuned
- [ ] Bot counts raised from 50
- [ ] Bluetooth keyboard + mouse, or a controller with ConsolePort
- [ ] Tailscale on both devices; `-away` realmlist variants generated
- [ ] Clip-on cooler if sessions run past 30-60 minutes
