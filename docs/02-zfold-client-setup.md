# Z Fold 8 Ultra Setup — Winlator Clients

Everything in this document happens on the phone. Do **Phase 0** before your PC does any server work.

---

## Your hardware

Snapdragon 8 Elite Gen 5 for Galaxy, Adreno GPU, 12–16GB RAM, 8-inch 2256×2504 inner display. This is the best-case profile for Winlator — Snapdragon with Adreno running the Turnip driver is the well-trodden path, and this chip is several generations past the phones people were already getting 60fps WoW out of.

Your real constraint is **thermal, not performance**. The Fold is 4.1mm thin unfolded with limited mass to absorb heat. Everything below is tuned around that.

---

## Phase 0 — Prove it works before anything else

The client renders its login screen without a server. Get there first.

1. Install **Winlator** (winlator.com, or the community `afeimod` fork — both work; the fork often has newer driver options).
2. Copy the **1.12.1 client folder** from PC to phone via USB. `Internal Storage/Download/wow-vanilla/`.
3. Create a container (settings below).
4. Add a shortcut pointing at `WoW.exe`.
5. Launch.

**Success looks like:** the login screen, the vanilla music, no crash for 10 minutes, phone warm but not hot.

If this fails, everything else is moot — and you've spent an evening, not a weekend.

---

## Container settings

Create **one container per era.** Don't try to share; they want different tuning and it's easier to debug when they're isolated.

| Setting | Value | Why |
|---|---|---|
| **Graphics driver** | Turnip (Adreno) | Your GPU's correct path. Try `Turnip + Zink` if plain Turnip misbehaves. |
| **DX Wrapper** | DXVK | Vanilla can also use WineD3D — worth testing both, DXVK usually wins. |
| **Screen size** | 1600×900 or 1280×720 | **Do not use native 2256×2504.** Massive wasted work for no visible gain on an 8" panel. |
| **Box64 preset** | Performance | Drop to Stability only if you get crashes. |
| **RAM** | 4096 MB | More doesn't help; WoW 1.12 is 32-bit. |
| **Video memory** | 2048 MB | |
| **Wine version** | Latest available | |

**Per-era adjustments:**
- **Vanilla (1.12.1):** as above. Also try launching with `-opengl` — vanilla has a native OpenGL renderer that sometimes outperforms the DXVK path.
- **TBC (2.4.3):** same settings. Slightly heavier, still comfortable.
- **WotLK (3.3.5a):** consider dropping to 1280×720 and raising video memory to 3072. This is the hot one.

---

## Thermal configuration — do this, it matters

The heat comes from **Box64 translating x86 CPU instructions**, not from the GPU. WoW's graphics are ancient; its CPU demands are not trivial. So lowering graphics settings helps less than you'd expect, and these do more:

1. **Cap FPS at 30.** Biggest single win. In-game: `/console maxfps 30`. Uncapped it will chase 100+ and cook the phone for no benefit on a 120Hz panel you're not going to notice.
2. **Render at 720p–900p**, not native (set in the container, above).
3. **Disable 120Hz system-wide** while playing. Display settings → Motion smoothness → Standard.
4. **Never play while charging.** Charging heat plus SoC heat is what triggers hard throttling.
5. **Airplane mode + Wi-Fi** if you don't need cellular. Modem heat is real.

In-game graphics (secondary, but free):
```
/console shadowLOD 0
/console farclip 177
/console particleDensity 0.3
/console groundEffectDensity 16
/console SetEnvironmentDetail 0.5
```

**Expectation:** 30–60 minutes of questing at a stable 30fps, phone noticeably warm. Longer sessions want a clip-on cooler — a $15 Peltier pad removes the problem entirely.

---

## Connecting to your servers

Each client folder needs its own realmlist entry pointing at the right port.

**Vanilla and TBC** — edit `realmlist.wtf` in the client root:
```
set realmlist 192.168.1.50:3724     ← vanilla
set realmlist 192.168.1.50:3725     ← TBC
```

**WotLK** — edit `WTF/Config.wtf`:
```
SET realmList "192.168.1.50:3726"
```

Replace `192.168.1.50` with your PC's reserved LAN IP.

**Make the file read-only** after editing. Some client versions rewrite realmlist on exit and helpfully reset it.

### Build numbers must match exactly

| Era | Build | Client version string |
|---|---|---|
| Vanilla | 5875 | 1.12.1 |
| TBC | 8606 | 2.4.3 |
| WotLK | 12340 | 3.3.5a |

A mismatched build fails at login with an unhelpful generic error. If login fails and the server logs show nothing, check the build first.

---

## Controls

This is what actually determines whether the setup is fun or miserable. WoW is a keyboard game and touch is genuinely bad for it.

**Best: Bluetooth keyboard + mouse.** A compact folding keyboard plus a small travel mouse fits in a jacket pocket and gives you the real game. The Fold's 8-inch screen makes this feel like a tiny laptop.

**Good: controller + gamepad addon.** A clip-on controller (Backbone, GameSir) plus **ConsolePort**, which reworks the entire UI for gamepad input. Versions exist for Classic-era clients. Setup effort is real but one-time.

**Workable: Winlator's touch mapping.** Overlay virtual keys onto the touchscreen. Fine for questing, painful for anything with a GCD you care about.

**Also install a bot control addon.** Commanding bots via chat commands gets tedious fast with a party of four. The playerbots communities have built client addons that expose bot control through the in-game UI — check the AddOns page in the Playerbots wiki. On a touchscreen this is the difference between usable and not.

---

## Storage

| Client | Phone footprint |
|---|---|
| Vanilla 1.12.1 | ~5 GB |
| TBC 2.4.3 | ~10 GB |
| WotLK 3.3.5a | ~15 GB |
| **All three** | **~30 GB** |

Keep clients in internal storage, not on any adopted external media — Winlator's I/O gets noticeably worse otherwise.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Black screen on launch | Wrong graphics driver | Switch Turnip ↔ Turnip+Zink ↔ VirGL |
| Crash at character select | Box64 preset too aggressive | Drop from Performance to Stability |
| "Unable to connect" | Firewall, or wrong port | Check PC firewall rule and realmlist port |
| Authenticates, then "world server down" | realmlist table has 127.0.0.1 | Fix on the **PC** side — see PC doc, Step 2 |
| Generic login failure, server logs empty | Client build mismatch | Verify build number |
| Bots visible but frozen | Missing mmaps | PC-side problem, not phone |
| Runs great for 20 min then stutters | Thermal throttling | Cap FPS at 30, drop resolution, use a cooler |
| Realmlist resets itself | Client rewrites on exit | Set the file read-only |

---

## Order of operations

1. **Phase 0:** vanilla client → login screen. Nothing else until this passes.
2. Wait for PC vanilla server (PC doc, Steps 1–2).
3. Edit realmlist, connect, play.
4. Only then add TBC container.
5. Only then add WotLK container.

Adding all three clients before proving one works is how a weekend disappears.

---

## Playing away from home

Install **Tailscale** on both the phone and PC, join them to the same tailnet. Then swap the realmlist IP for the PC's Tailscale address (100.x.x.x). Works from anywhere, no port forwarding, nothing exposed publicly.

Keep two realmlist files per client — `realmlist-home.wtf` and `realmlist-away.wtf` — and swap them. Latency over Tailscale is fine for questing since only game packets travel; the rendering is all local.
