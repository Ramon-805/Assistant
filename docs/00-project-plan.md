# Project: Triple-Era WoW with Bots — Phone Client, PC Server

**Goal:** Play Classic (1.12.1), TBC (2.4.3), and WotLK (3.3.5a) on a Galaxy Z Fold 8 Ultra, with AI bots populating the world, against private servers hosted on a home PC. The PC must remain usable by other people while the server runs, and nothing about the session should be visible on the living room monitor.

---

## The architecture

```
┌─────────────────────────┐         LAN / Tailscale        ┌──────────────────────┐
│  PC (living room)       │  ◄──────────────────────────►  │  Z Fold 8 Ultra      │
│                         │      game packets only          │                      │
│  MySQL 8                │      (a few KB/s)               │  Winlator            │
│  ├ Vanilla core :3724   │                                 │  ├ Container: 1.12.1 │
│  ├ TBC core     :3725   │                                 │  ├ Container: 2.4.3  │
│  └ WotLK core   :3726   │                                 │  └ Container: 3.3.5a │
│                         │                                 │                      │
│  Runs as background     │                                 │  Renders locally     │
│  console processes.     │                                 │  No streaming.       │
│  Nothing on screen.     │                                 │                      │
└─────────────────────────┘                                 └──────────────────────┘
```

The PC does **no rendering**. It runs database and world simulation only — console windows you can minimize, or Windows services with no window at all. The phone runs the actual Windows game client under Winlator (Wine + Box64 + DXVK) and does all the graphics work itself.

**Why this beats streaming:** no Moonlight latency, nothing displayed on the physical monitor, PC stays free for normal use, no session/cursor conflict.

**The tradeoff:** the phone does x86→ARM translation, which generates heat. Managed with FPS caps and resolution limits (see the Z Fold doc).

---

## Core selection

| Era | Client build | Server core | Bot solution |
|---|---|---|---|
| Vanilla | 1.12.1 (5875) | CMaNGOS-classic | `BUILD_PLAYERBOTS` (ike3 AI) |
| TBC | 2.4.3 (8606) | CMaNGOS-tbc | `BUILD_PLAYERBOTS` (ike3 AI) |
| WotLK | 3.3.5a (12340) | AzerothCore (Playerbot fork) | `mod-playerbots` |

**Why the split:** CMaNGOS has a single playerbots repo covering classic, tbc and wotlk, so the two older eras share one build process and one mental model. For WotLK, AzerothCore's `mod-playerbots` is the more mature implementation — it handles most raids and battlegrounds, has extensive per-bot configuration, and performs well even with very large bot counts. It requires a custom AzerothCore fork rather than mainline, which is why it isn't the answer for all three.

If you'd rather have one codebase for everything, CMaNGOS-wotlk with playerbots also works and is less setup. The bots are less capable. Your call — the plan below assumes the table above.

---

## Port map

Each core needs its own auth listener, because only one process can bind a port. The client specifies the port in its realmlist, so this is invisible in play.

| Era | Auth (realmd/authserver) | World |
|---|---|---|
| Vanilla | 3724 | 8085 |
| TBC | 3725 | 8086 |
| WotLK | 3726 | 8087 |

All three can run simultaneously. They use separate databases and never touch each other.

---

## Phases

Do these in order. Each one is independently verifiable, so when something breaks you know exactly which piece broke.

### Phase 0 — Prove the client works (phone only, ~1 evening)
Install Winlator, get the 1.12.1 client to the character-select screen. **No server needed** — the login screen renders fine without one. If this fails, nothing else matters, and you've spent one evening instead of one weekend finding out.

**Exit criteria:** login screen, music playing, stable for 10 minutes, phone not uncomfortably hot.

### Phase 1 — Vanilla server (PC, ~half a day)
MySQL, CMaNGOS-classic build, map/vmap/mmap extraction, playerbots DB. Connect from the *PC* first with a local client to isolate server problems from Winlator problems.

**Exit criteria:** character created, logged in, `.bot add` spawns a working bot.

### Phase 2 — Connect the phone to vanilla (~1 hour)
Edit realmlist, open firewall ports, log in over Wi-Fi.

**Exit criteria:** questing on the phone with bots in the party.

### Phase 3 — TBC (~2–3 hours)
Same CMaNGOS process, different branch and client. Much faster the second time.

### Phase 4 — WotLK (~half a day)
Different core, different build process, largest client. Save this for last — it's the heaviest on the phone and the most involved on the PC.

### Phase 5 — Polish
Launcher shortcuts, bot control addons, XP rate tuning, backup script, remote access via Tailscale.

---

## Realistic effort estimate

- **Phase 0–2 (vanilla, end to end):** one weekend, most of it waiting on mmap extraction
- **All three eras:** two to three weekends
- **The genuinely slow parts:** mmaps extraction (2–6 hours per client, unattended), and the first CMaNGOS compile

Repacks can collapse Phases 1 and 3–4 to under an hour each, at the cost of running someone else's binaries and being stuck on whatever version they packaged. Reasonable shortcut for testing the concept; build from source for anything you plan to keep.

---

## Disk budget

| Item | Size |
|---|---|
| Vanilla client (PC + phone copies) | ~5 GB each |
| TBC client | ~10 GB each |
| WotLK client | ~15 GB each |
| Extracted maps/vmaps/mmaps (per era, PC only) | 10–20 GB |
| MySQL data, all three | ~15 GB |
| **PC total** | ~110 GB |
| **Phone total** | ~30 GB (all three clients) |

Your 1TB Fold handles this fine. Consider keeping only the era you're actively playing on the phone if you took a smaller storage tier.

---

## Things to decide before starting

- **Bot density.** Hundreds of world bots make the world feel alive but cost server CPU. Start at 50 and raise it.
- **XP rates.** You control this. Given sessions are constrained by phone thermals, 2x–3x means a 30-minute session accomplishes something real instead of one-third of a Deadmines run.
- **Remote play.** Tailscale on both devices if you want to play outside the house. Easier than port forwarding and doesn't expose the server publicly.

---

## Legal note

CMaNGOS and AzerothCore are open-source projects and legitimate software. Running a private server for personal use is low-risk; Blizzard's enforcement targets large public servers. You do need your own legally-obtained game clients. Don't log a Battle.net-linked installation into a private realm — keep the private-server client folders entirely separate from any live install.

---

## Companion documents

- `01-pc-server-setup.md` — everything that happens on the PC
- `02-zfold-client-setup.md` — everything that happens on the phone
