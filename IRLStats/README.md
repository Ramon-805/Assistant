# Gymlocke (IRL Stats addon): Windwalker Monk

A retail WoW (Midnight 12.1) addon that runs the **Gymlocke Rulebook** for
Windwalker monks. Your talents, cooldowns and flying unlock as you pass
calisthenics tests that need only a pull-up bar, a wall, a chair and the
floor. Addons can't block anything, so it watches your casts, talent
loadout and flights, and flags anything you use before you've earned it.

## Install

Copy this `IRLStats` folder into
`World of Warcraft/_retail_/Interface/AddOns/`, then restart or `/reload`.
The `tests/` folder can stay; WoW only loads files listed in `IRLStats.toc`.
If the client says the addon is out of date, tick **Load out of date
AddOns** or bump `## Interface` in the TOC.

## Using it

- **Test Day** opens on first login (`/irl testday` any time). It shows the
  protocol, then one page per discipline where you pick the highest tier
  you passed on camera, then reaction time and the mile (either can wait).
  You must tick the video box: no video, no credit.
- **Retests:** run Test Day again every month, or log a single discipline
  from the Disciplines tab. A lower result takes effect at once, and the
  tab shows your 7-day retry window.
- **`/irl`** or the minimap button opens the Gymlocke sheet:
  - **Rank:** your rank, the gate map (what each gate needs, your progress,
    what it opens) and the rank ceilings table.
  - **Disciplines:** your tier in each discipline and supporting test, the
    next landmark, what it keys, and retest/retry countdowns. Log tests here.
  - **Flags:** this character's flag log and anything locked in your
    current loadout.
- Hover any talent or spell: the tooltip lists each requirement in green
  (done) or red (needed). Locked talents are tinted red in the talent frame,
  including unselected ones, so closed tree sections are visible at a glance.
- `/irl verify` checks the rulebook's talent names against the live client.

## How the rulebook maps to the addon

| Rulebook | Addon |
|---|---|
| Six disciplines, Bronze to Legendary | Tier = the highest landmark you last logged. Account-wide. |
| Mile run, reaction time | First result is the baseline. Bronze matches it; Silver, Gold and Legendary are 5%, 10% and 15% faster, rounded up to the whole second or millisecond. |
| Gates 0-5 | Sequential: each gate also needs the one before. Gates 4 and 5 use this character's level. |
| "Each gate opens a section of the tree" | Each node's section (top, middle, bottom) comes from the talent tree's own point gates. Top = Gate 0, middle = Gate 1, bottom = Gate 3. |
| Discipline keys | Keyed talents need their listed gate and their key, wherever the node sits in the tree ("the key follows the talent"). |
| Gate 2 major cooldowns | `IRL.MajorCooldowns` in `Data/Rulebook.lua` (Zenith, Touch of Karma, Storm, Earth, and Fire), plus the keyed Invoke Xuen and Whirling Dragon Punch. |
| Spec capstone nodes | The bottom row of the spec tree, apex excluded: Gate 3 + Gold in any one. |
| Fortifying Brew upgrades | Talents whose name contains "Fortif" (except Fortifying Brew itself), plus Ironshell Brew: Gate 3 + Core Silver. |
| Hero talents | Gate 4 (level 71 + Flexibility Silver). The hero tree's bottom row also needs Gold in 2. |
| Apex | Gate 5 (level 81). Rank 1 = Keystone (Gold in 1), ranks 2-3 = Middle node (Gold in 2), rank 4 = Capstone (Legendary in 1). |
| Flying / Skyriding | Mile Silver. Each take-off before that is flagged. |
| Ranks | Solo Only, Adept (Gate 3), Master (Adept + Gold in 2), Grandmaster (Adept + Legendary in 1). |
| Retests | Due 30 days after a discipline's last test. A failed retest drops the tier at once and starts a 7-day retry window; passing at the old tier again clears it. |

Baseline abilities (spells not in the talent tree) are never gated. Gate 0
only covers the top of the tree.

## Not enforced yet

- **Content and gear ceilings.** The rank table is shown on the Rank tab.
  Flagging locked raid difficulties, Mythic+ levels, rated PvP, delve tiers
  and gear above your upgrade track comes in the next update.
- **Overdue retests.** The rulebook doesn't say what happens if you skip a
  monthly retest, so the addon only shows "Retest overdue" in red.
- **Video.** The addon can't check your footage; the checkbox is your word.

## Check in game

- `/irl verify` and look for names reported as not found. The Gate 2
  cooldown list, the Fortifying Brew upgrade names and the apex name
  (Tigereye Brew) are my best reading of the Midnight tree. Fix any
  mismatches in `Data/Rulebook.lua`.
- Open the talent frame. The red tint should follow the tree's own section
  lines: top untinted after Test Day, middle after Bronze in all six, bottom
  after Silver in 4.
- The Blizzard frame internals used (`PlayerSpellsFrame.TalentsFrame:EnumerateAllTalentButtons()`,
  talent buttons' `GetNodeInfo`/`GetNodeID`, `C_Traits.GetTreeInfo` gates)
  are called defensively, so if one has changed the feature fails quietly
  instead of throwing.

## Saved data

Tiers and history live in `IRLStatsDB` (account-wide). Flags live in
`IRLStatsCharDB` (per character). Data from the pre-rulebook build is kept
under `IRLStatsDB.legacyV1` and not used.

## Tests

From this folder, with Lua 5.1 (WoW's Lua version):

```
lua5.1 tests/run.lua     # rules engine: gates, keys, sections, capstone, hero, apex, ranks,
                         # supporting-test %, retests, migration, flags (23 tests)
lua5.1 tests/smoke.lua   # every TOC file against a mocked WoW API: tree reading, Test Day
                         # wizard, casts, failed retest, flying, tabs, tooltips, slash commands
```

These catch logic and wiring errors, but the real client is the final test.
