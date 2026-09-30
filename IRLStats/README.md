# Gymlocke (IRL Stats addon): Windwalker and Brewmaster Monk

A retail WoW (Midnight 12.1) addon that runs the **Gymlocke Rulebook** for
monks. Your talents, cooldowns and flying unlock as you pass real fitness
tests that need only a pull-up bar, a wall, a chair and the floor. Addons
can't block anything, so it watches your casts, talent loadout and flights,
and flags anything you use before you've earned it.

Each spec has its own rulebook and its own ladder:

- **Windwalker** trains calisthenics skills (pull, push, press, legs, core,
  flexibility) against fixed landmarks.
- **Brewmaster** trains endurance, bracing and balance (burpees, wall sit,
  dead hang, squat jumps, deep squat, single-leg stand), measured against
  your own Test Day baseline.

Switching spec switches rulebooks. Each spec has its own Test Day, gates and
rank, so a Brewmaster starts at Solo Only even if your Windwalker is Adept.
The mile run and reaction time are shared supporting tests.

## Install

Copy this `IRLStats` folder into
`World of Warcraft/_retail_/Interface/AddOns/`, then restart or `/reload`.
The `tests/` folder can stay; WoW only loads files listed in `IRLStats.toc`.
If the client says the addon is out of date, tick **Load out of date
AddOns** or bump `## Interface` in the TOC.

## Using it

- **Test Day** opens on first login for your current spec (`/irl testday`
  any time). It shows the protocol, then one page per discipline, then
  reaction time and the mile (either can wait). Windwalker pages ask for the
  highest tier you passed; Brewmaster pages ask for your result (reps or
  time). You must tick the video box: no video, no credit.
- **Retests:** run Test Day again every month, or log a single discipline
  from the Disciplines tab. A lower result takes effect at once, and the
  tab shows your 7-day retry window.
- **`/irl`** or the minimap button opens the Gymlocke sheet. The
  **Showing:** button switches which spec's ladder you're looking at, so
  you can log Brewmaster tests while playing Windwalker.
  - **Rank:** the spec's rank, its gate map (what each gate needs, your
    progress, what it opens) and the rank ceilings table.
  - **Disciplines:** your tier in each discipline and supporting test, the
    next target, what it keys, and retest/retry countdowns. Log tests here.
  - **Flags:** this character's flag log and anything locked in your
    current loadout.
- Hover any talent or spell: the tooltip lists each requirement in green
  (done) or red (needed). Locked talents are tinted red in the talent frame,
  including unselected ones, so closed tree sections are visible at a glance.
- `/irl verify` checks your current spec's talent names against the live client.

## Shared rules (both specs)

| Rule | Addon |
|---|---|
| Gates 0-5 | Test Day; Bronze in all six; Silver in 2; Silver in 4; level 71 + the spec's hero key; level 81. Sequential: each gate also needs the one before. Gates 4 and 5 use this character's level. |
| "Each gate opens a section of the tree" | Each node's section (top, middle, bottom) comes from the talent tree's own point gates. Top = Gate 0, middle = Gate 1, bottom = Gate 3. |
| Discipline keys | Keyed talents need their listed gate and their key, wherever the node sits in the tree ("the key follows the talent"). |
| Spec capstone nodes | The bottom row of the spec tree, apex excluded: Gate 3 + Gold in any one. |
| Hero talents | Gate 4. The hero tree's bottom row also needs Gold in 2. |
| Apex | Gate 5 (level 81). Rank 1 = Keystone (Gold in 1), ranks 2-3 = Middle node (Gold in 2), rank 4 = Capstone (Legendary in 1). |
| Mile run, reaction time | Shared by both specs. First result is the baseline; Bronze matches it; Silver, Gold and Legendary are 5%, 10% and 15% faster. Keys: Transcendence (Mile Silver), Ring of Peace and Paralysis (Reaction Silver). |
| Flying / Skyriding | Mile Silver, on any spec. Each take-off before that is flagged. |
| Ranks | Solo Only, Adept (Gate 3), Master (Adept + Gold in 2), Grandmaster (Adept + Legendary in 1). Per spec. |
| Retests | Due 30 days after a discipline's last test. A failed retest drops the tier at once and starts a 7-day retry window; passing at the old tier again clears it. |

Baseline abilities (spells not in the talent tree) are never gated. Gate 0
only covers the top of the tree.

## Windwalker

Landmark tiers: your tier is the highest landmark you have on camera.

| Discipline | Bronze | Silver | Gold | Legendary |
|---|---|---|---|---|
| Pull | 5 strict pull-ups | 10 | 15 | 3 strict muscle-ups |
| Push | 20 push-ups | 35 | 50 | 1 one-arm push-up per side |
| Press | 10 pike push-ups | 30 s chest-to-wall handstand | 5 wall HSPU | 10 wall HSPU |
| Legs | Single-leg sit-to-stand, 3/leg | Pistol to low box, 3/leg | Full pistol, 1/leg | Full pistol, 5/leg |
| Core | 60 s plank | 30 s hollow hold | 15 s L-sit | 5 dragon flags |
| Flexibility | Pike to mid-shin | Fingertips to toes | Hands around soles | Chest flat to thighs |

Keys: Fists of Fury (Push Silver), Strike of the Windlord (Pull Silver),
Tiger's Lust (Legs Silver), Chi Torpedo/Celerity (Flexibility Silver),
Invoke Xuen (Gate 2, Core Gold), Whirling Dragon Punch (Gate 2, Press Silver),
Diffuse Magic/Dampen Harm (Gate 3, Flexibility Gold), Fortifying Brew upgrades
(Gate 3, Core Silver). Gate 2 major cooldowns: Zenith, Touch of Karma,
Storm, Earth, and Fire. Hero key: Flexibility Silver. Apex: Tigereye Brew.

## Brewmaster

Measured tiers: your first result (Test Day) is your baseline and Bronze;
Silver, Gold and Legendary are **+15%, +30% and +50%** over it, rounded up
to the next rep or second. Because Bronze is your baseline, Gate 1 opens on
Test Day; Silver is the first real work. The baseline never resets, so test
honestly: a sandbagged baseline makes every tier easy.

| Discipline | Test | Equipment |
|---|---|---|
| Endurance | Burpees in 5 minutes | Floor, timer |
| Brace | Wall sit (thighs parallel) | Wall |
| Hang | Dead hang | Pull-up bar |
| Power | Squat jumps in 60 seconds | Floor, timer |
| Mobility | Deep squat hold (heels flat) | Floor |
| Balance | Single-leg stand, eyes closed, weaker leg | Floor |

| Talent | Opens at | Key |
|---|---|---|
| Elixir of Determination | Gate 1 | Brace Silver |
| Tiger's Lust | Gate 1 | Power Silver |
| Chi Torpedo / Celerity | Gate 1 | Mobility Silver |
| Black Ox Brew | Gate 2 | Endurance Silver |
| Exploding Keg | Gate 2 | Power Silver |
| Invoke Niuzao, the Black Ox | Gate 2 | Endurance Gold |
| Stagger talents (name contains "Stagger") | Gate 2 | Hang Silver |
| Diffuse Magic / Dampen Harm | Gate 3 | Balance Gold |
| Fortifying Brew upgrades | Gate 3 | Brace Silver |
| Celestial Brew upgrades (name contains "Celestial") | Gate 3 | Brace Silver |
| Purifying Brew upgrades (name contains "Purif") | Gate 3 | Hang Silver |

Hero key (Gate 4): Mobility Silver, for Shado-Pan or Master of Harmony.
Apex: Bring Me Another. Brewmaster talent names come from the Midnight 12.1
guides; confirm them with `/irl verify` on your Brewmaster.

## Not enforced yet

- **Content and gear ceilings.** The rank table is shown on the Rank tab.
  Flagging locked raid difficulties, Mythic+ levels, rated PvP, delve tiers
  and gear above your upgrade track comes in a later update.
- **Overdue retests.** The rulebook doesn't say what happens if you skip a
  monthly retest, so the addon only shows "Retest overdue" in red.
- **Video.** The addon can't check your footage; the checkbox is your word.
- **Mistweaver** has no rulebook yet, so it isn't enforced.

## Check in game

- `/irl verify` on each spec and look for names reported as not found. The
  Gate 2 cooldown list, the pattern groups (Fortifying, Celestial, Purifying,
  Stagger) and the apex names are my best reading of the Midnight trees.
  Fix any mismatches in `Data/Rulebook.lua`.
- Open the talent frame. The red tint should follow the tree's own section
  lines: top untinted after Test Day, middle after Bronze in all six, bottom
  after Silver in 4.
- The Blizzard frame internals used (`PlayerSpellsFrame.TalentsFrame:EnumerateAllTalentButtons()`,
  talent buttons' `GetNodeInfo`/`GetNodeID`, `C_Traits.GetTreeInfo` gates)
  are called defensively, so if one has changed the feature fails quietly
  instead of throwing.

## Saved data

`IRLStatsDB` (account-wide) holds each spec's ladder under
`specs.windwalker` and `specs.brewmaster`, plus the shared supporting tests.
Flags live in `IRLStatsCharDB` (per character). Windwalker tiers from the
single-spec version move to `specs.windwalker` automatically; data from the
pre-rulebook build is kept under `IRLStatsDB.legacyV1` and not used.

## Tests

From this folder, with Lua 5.1 (WoW's Lua version):

```
lua5.1 tests/run.lua     # rules engine for both rulebooks: gates, keys, sections, capstone,
                         # hero, apex, ranks, percent tiers, retests, migrations, flags (36 tests)
lua5.1 tests/smoke.lua   # every TOC file against a mocked WoW API: tree reading, Test Day
                         # wizard, casts, failed retest, flying, tabs, spec switch to
                         # Brewmaster, measured Test Day, spec switcher, verify
```

These catch logic and wiring errors, but the real client is the final test.
