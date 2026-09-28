# IRL Stats (build 1: Personal mode, Windwalker monk)

A retail WoW (Midnight 12.1) addon that gates monk abilities and talents
behind real-life fitness milestones. It can't block anything. It watches your
casts and talent loadout and flags anything you use before you've earned it.

## Install

Copy this `IRLStats` folder into
`World of Warcraft/_retail_/Interface/AddOns/`, then restart the game or
`/reload`. The `tests/` folder can stay there; WoW only loads files listed in
`IRLStats.toc`.

The TOC says `## Interface: 120100`. If the client reports the addon as
out of date, bump that number to the live build's interface version.

## Using it

- **First login:** the setup wizard opens. Enter age, sex, bodyweight and
  units, then pick a test, current PR and goal for each of the eight
  categories. Goals are pre-filled at about the 90th percentile where norms
  exist (vertical jump, grip, VO2max). You can skip a category, but its
  abilities stay locked until you set it up.
- **`/irl`** or the minimap button opens the character sheet:
  - **Goals:** test, PR, goal, next milestone with a progress bar, and what
    it unlocks. Hover the bar to see the whole ladder. Use **Log PR** to add
    a result. The **...** menu lets you change the test, set a goal, restart
    the ladder or print your history.
  - **Today:** "Took my supplements" (unlocks Fortifying Brew for the
    day), "Did mobility/PT" (keeps Vivify and Expel Harm unlocked) and
    "Trained today" (keeps the Shado-Pan hero tree unlocked). Each streak
    shows three strike pips and your best streak.
  - **Flags:** this character's flag log, newest first, plus anything
    locked in your current loadout.
- **Slash shortcuts:** `/irl checkin`, `/irl pt`, `/irl trained`,
  `/irl setup`, `/irl verify`, `/irl minimap`, `/irl help`.

## How it works under Midnight's rules

| Concern | Approach |
|---|---|
| No combat log | Casts come from `UNIT_SPELLCAST_SUCCEEDED`, registered for `player` only. |
| Secret values | Every spellID, name, action or tooltip value is checked with `issecretvalue()` before it's compared or used. |
| Talents | Read out of combat with `C_ClassTalents`/`C_Traits` on login, `TRAIT_CONFIG_UPDATED`, spec change, leaving combat, and whenever unlock state changes. |
| Combat lockdown | Action-button tints are non-secure textures. They're only created or changed out of combat; refreshes requested in combat run on `PLAYER_REGEN_ENABLED`. |
| No IDs to maintain | Gates are keyed by name. Casts, buttons, tooltips and talents resolve their spellID to a name at runtime. Run `/irl verify` to check every name against your spellbook and talent trees. |

## Decisions where the spec was ambiguous

1. **The ladder is anchored at a baseline, not the latest PR.** The spec
   says milestones run from the current PR to the goal and are recomputed
   when a PR changes. Taken literally, logging a PR would rebuild the ladder
   underneath you and you'd never pass a rung. Instead, each category stores
   the PR it had when its goal was set (`baseline`), the ladder runs from
   there, and new PRs climb it. Changing the goal rebuilds the ladder from
   the same baseline. Use "Restart ladder from current PR" in the **...**
   menu to re-anchor it, for example after a layoff.
2. **Steps are linear from the baseline.** +10% means baseline × 1.1,
   × 1.2, and so on, rounded to the test's precision. Rounding never
   produces a rung that isn't an improvement. Ladders are capped at 30 rungs.
3. **Short ladders.** When a ladder has three rungs or fewer below the
   goal, gates stack on rung 1 and apex ranks share the top rungs. The first
   gate always sits on rung 1, so the first improvement pays out.
4. **Rewards on the top three rungs.** Gates in every category sit below
   the top three rungs (rule 2), so categories without an apex have a few
   stretch rungs after the last unlock.
5. **Strikes are lives, not a rolling window.** Each missed calendar day
   uses one strike for the rest of the streak. A session doesn't refund
   strikes; the third strike ends the streak, and the next session starts a
   fresh one with no strikes used.
6. **No streak yet means locked.** Vivify and Expel Harm start locked until
   your first PT session, and Shado-Pan until your first training day.
7. **A PR is your best result.** Every result is logged in the history, but
   a worse result doesn't lower the PR or relock anything.
8. **"Training day" is self-reported.** It's whatever you count when you
   tap "Trained today". That's open question 2 in the spec.
9. **Talent flags follow the loadout signature.** A locked selection is
   flagged once per distinct loadout, so changing any talent, or something
   becoming newly locked, flags it again. Re-checks of the same loadout
   never do.
10. **Apex ranks.** Tigereye Brew is flagged when its selected rank exceeds
    the ranks you've unlocked. Zenith Stomp is gated on rank 3.
11. **Enforcement scope.** Gates apply to monks except the Brewmaster and
    Mistweaver specs (`Config.exemptSpecs`). Low-level monks without a spec
    are enforced, so Roll is gated from the first minute.
12. **Action bars.** Tints cover Blizzard's default bars. Bartender, ElvUI
    and Dominos buttons aren't tinted in build 1, but casts from them are
    still flagged. Rising Sun Kick's button follows its Rushing Wind Kick
    override.
13. **Tests are chosen for solo self-testing.** Each category leads with
    tests you can run alone with a pull-up bar, the floor, a wall and a phone
    (timer, GPS or reaction app). Each one has a "How" line shown when you log
    a result. Drills that need a partner, cones or gym equipment (5-10-5,
    T-test, sprints, med ball, landmine, rower) are retired: they're hidden
    from pickers, but a category already using one keeps working. Rep counts
    and timed holds climb +10% per rung (`Config.countStep`).
14. **Skill ladders have no goal pre-fill.** Body control and mobility tests
    are skill ladders (planche, handstand, front lever, splits, squat depth,
    pike). You pick the level you're at and the level you're aiming for.

Tunables (step sizes, strikes, flag cooldown, exercises shown) live in
`IRL.Config` in `Init.lua`. The gate table is `Data/Gates.lua`, tests and
exercise lists are `Data/Tests.lua`, and norms are `Data/Norms.lua`.

**The norms in `Data/Norms.lua` are approximate and need checking against
the sources** (CHMS, the international handgrip norms, FRIEND) before you
trust the pre-fill.

## Tests

From this folder, with Lua 5.1 (WoW's Lua version):

```
lua5.1 tests/run.lua     # milestone, gate, streak, habit, flag and unit logic (27 tests)
lua5.1 tests/smoke.lua   # loads every TOC file against a mocked WoW API and drives login,
                         # casts, talent walk, overlays, tooltips, wizard, tabs and slash commands
```

These catch logic and wiring errors, but they can't prove it works in the
real client. That needs the in-game pass below.

## In-game acceptance checklist

- [ ] `/irl verify` reports every gate name found (log in at max level on a Windwalker).
- [ ] Casting a locked spell in combat writes one flag and one warning; casting it again within 60 s writes nothing.
- [ ] Selecting a locked talent out of combat writes one flag per loadout change.
- [ ] No Lua errors or taint warnings during a boss encounter or Mythic+ run (`/console scriptErrors 1`, and check `/console taintLog 1` output).
- [ ] Logging a PR that passes a milestone shows an unlock toast and removes the tint after combat.
- [ ] Fortifying Brew unlocks after the daily check-in and locks again the next calendar day.
- [ ] Three missed PT days lock Vivify and Expel Harm; one session unlocks them and starts a new streak; best streak is unchanged.
- [ ] Goals and PRs carry over to a second character on the same account.
- [ ] Talent frame shows red tints and requirement tooltips on locked talents and hero-tree nodes.

The first things to check in the live client are the Blizzard frame
internals this relies on: `PlayerSpellsFrame.TalentsFrame:EnumerateAllTalentButtons()`,
talent buttons' `GetSpellID`/`GetNodeInfo`, action buttons' `GetPagedID`/`.action`,
and the tooltip types for action and talent tooltips. Each of these is called
defensively, so if one has changed the feature fails quietly instead of throwing.
