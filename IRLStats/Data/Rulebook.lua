-- Gymlocke Rulebook: Windwalker Monk (Sep 27, 2026). Everything the rules
-- engine (Core/Rules.lua) needs, transcribed from the rulebook. Edit here to
-- change the rules; nothing else hard-codes them.
local _, IRL = ...

-- Tier 0 = not yet Bronze.
IRL.Tiers = { "Bronze", "Silver", "Gold", "Legendary" }
IRL.TierColors = {
  [0] = "ff999999", [1] = "ffcd7f32", [2] = "ffc0c0c0", [3] = "ffffd100", [4] = "ffff8000",
}

--------------------------------------------------------------------------
-- The six disciplines (count toward rank). Tier = the highest landmark you
-- have on camera.
--------------------------------------------------------------------------
IRL.DisciplineOrder = { "pull", "push", "press", "legs", "core", "flex" }
IRL.Disciplines = {
  pull = {
    label = "Pull", equipment = "Pull-up bar",
    tiers = { "5 strict pull-ups", "10 strict pull-ups", "15 strict pull-ups", "3 strict muscle-ups" },
    form = "Dead hang start, chin over the bar, no kipping.",
  },
  push = {
    label = "Push", equipment = "Floor",
    tiers = { "20 push-ups", "35 push-ups", "50 push-ups", "1 one-arm push-up per side" },
    form = "Chest reaches a fist's height from the floor; body stays in a straight line.",
  },
  press = {
    label = "Press", equipment = "Wall",
    tiers = { "10 pike push-ups", "30 s chest-to-wall handstand hold", "5 wall handstand push-ups",
              "10 wall handstand push-ups" },
    form = "Handstand push-ups: head touches the floor or a folded towel; full lockout at the top.",
  },
  legs = {
    label = "Legs", equipment = "Chair or step",
    tiers = { "Single-leg sit-to-stand, 3 per leg", "Pistol to low box, 3 per leg", "Full pistol, 1 per leg",
              "Full pistol, 5 per leg" },
    form = "The weaker leg sets your tier. Hands touch nothing and the free heel never touches the floor.",
  },
  core = {
    label = "Core", equipment = "Floor, two chairs",
    tiers = { "60 s plank", "30 s hollow body hold", "15 s L-sit", "5 dragon flags" },
    form = "Timer visible in frame. The attempt ends the moment form breaks.",
  },
  flex = {
    label = "Flexibility", equipment = "Floor",
    tiers = { "Seated pike: fingertips to mid-shin", "Fingertips to toes", "Hands around soles",
              "Chest flat to thighs" },
    form = "Legs straight and together, knees locked, toes not pointed. Hold 3 s, filmed from the side.",
  },
}

--------------------------------------------------------------------------
-- Supporting tests: don't count toward rank; only keys for some talents.
-- Tiers are a percentage faster than your baseline: Bronze matches it.
-- Targets round up to the next whole unit (second, millisecond).
--------------------------------------------------------------------------
IRL.SupportOrder = { "mile", "reaction" }
IRL.Supports = {
  mile     = { label = "Mile run", test = "mile" },
  reaction = { label = "Reaction time", test = "reaction" },
}
IRL.SupportTierPercent = { 0, 0.05, 0.10, 0.15 }

--------------------------------------------------------------------------
-- Retests: every discipline monthly; a failed retest drops the tier at once
-- and allows one re-attempt within 7 days.
--------------------------------------------------------------------------
IRL.RetestDays = 30
IRL.RetryDays = 7

--------------------------------------------------------------------------
-- Gates. need = { tier, count } means "tier or better in count of the six";
-- level = minimum character level; key = { discipline, tier }.
--------------------------------------------------------------------------
IRL.GateDefs = {
  [0] = { name = "Test Day", requirement = "All six disciplines filmed", testDay = true,
          opens = "Top of class and spec trees, baseline abilities" },
  [1] = { name = "Wave 2", requirement = "Bronze in all six", need = { 1, 6 },
          opens = "Middle of both trees: builders and spenders" },
  [2] = { name = "Wave 3", requirement = "Silver in 2", need = { 2, 2 },
          opens = "Major cooldowns" },
  [3] = { name = "Wave 4", requirement = "Silver in 4", need = { 2, 4 },
          opens = "Bottom of both trees + group content" },
  [4] = { name = "Hero talents", requirement = "Level 71 + Flexibility Silver", level = 71, key = { "flex", 2 },
          opens = "Shado-Pan or Conduit of the Celestials" },
  [5] = { name = "Apex", requirement = "Level 81", level = 81,
          opens = "Apex talent" },
}
IRL.GateCount = 5

-- Tree section (1 = top, 2 = middle, 3 = bottom) -> gate that opens it.
IRL.SectionGate = { 0, 1, 3 }

-- Discipline keys. "Opens at" overrides the tree section: if Midnight moved
-- a node, the gate and key follow the talent.
IRL.Keys = {
  ["Fists of Fury"]                = { gate = 1, key = { "push", 2 } },
  ["Strike of the Windlord"]       = { gate = 1, key = { "pull", 2 } },
  ["Tiger's Lust"]                 = { gate = 1, key = { "legs", 2 } },
  ["Chi Torpedo"]                  = { gate = 1, key = { "flex", 2 } },
  ["Celerity"]                     = { gate = 1, key = { "flex", 2 } },
  ["Invoke Xuen, the White Tiger"] = { gate = 2, key = { "core", 3 } },
  ["Whirling Dragon Punch"]        = { gate = 2, key = { "press", 2 } },
  ["Ring of Peace"]                = { gate = 2, key = { "reaction", 2 } },
  ["Paralysis"]                    = { gate = 2, key = { "reaction", 2 } },
  ["Transcendence"]                = { gate = 2, key = { "mile", 2 } },
  ["Diffuse Magic"]                = { gate = 3, key = { "flex", 3 } },
  ["Dampen Harm"]                  = { gate = 3, key = { "flex", 3 } },
}

-- Gate 2 "major cooldowns" that carry no key. Check these names in game;
-- add or remove to match the live Windwalker tree.
IRL.MajorCooldowns = { "Zenith", "Touch of Karma", "Storm, Earth, and Fire" }

-- Fortifying Brew upgrades: Gate 3 + Core Silver. Any talent whose name
-- contains the pattern (except Fortifying Brew itself), plus the extras.
IRL.FortifyingUpgrades = {
  gate = 3, key = { "core", 2 },
  pattern = "fortif", base = "Fortifying Brew", extra = { "Ironshell Brew" },
}

-- Bottom row of the spec tree (apex excluded): Gate 3 + Gold in any one.
IRL.CapstoneRule = { gate = 3, need = { 3, 1 } }

-- Hero talents: Gate 4; the final (bottom) node of the hero tree needs Gold in 2.
IRL.HeroRule = { gate = 4, finalNeed = { 3, 2 } }

-- Apex (Gate 5). Rank r needs the entry with the highest minRank <= r.
IRL.ApexNames = { "Tigereye Brew" } -- also detected as a 4-rank spec node
IRL.ApexRule = {
  gate = 5,
  ranks = {
    { minRank = 1, need = { 3, 1 }, label = "Keystone" },
    { minRank = 2, need = { 3, 2 }, label = "Middle node" },
    { minRank = 4, need = { 4, 1 }, label = "Capstone" },
  },
}

-- Flying / Skyriding: any time with Mile Silver.
IRL.FlyingKey = { "mile", 2 }

--------------------------------------------------------------------------
-- Ranks and content ceilings (displayed now; enforced in a later update).
-- Ranks above Adept also require Adept.
--------------------------------------------------------------------------
IRL.Ranks = {
  { name = "Solo Only",   requirement = "Before Gate 3",
    raid = "Locked", mplus = "Locked", pvp = "Unrated skirmish only", delves = "Tiers 1-5", gear = "Adventurer / Veteran" },
  { name = "Adept",       requirement = "Gate 3: Silver in 4", gate = 3,
    raid = "Normal / Heroic", mplus = "Up to +10", pvp = "Rated up to ~1800", delves = "Tiers 6-8", gear = "Champion" },
  { name = "Master",      requirement = "Gold in 2", gate = 3, need = { 3, 2 },
    raid = "Mythic", mplus = "Up to +15", pvp = "Up to ~2100", delves = "Tiers 9-11", gear = "Hero" },
  { name = "Grandmaster", requirement = "Legendary in 1", gate = 3, need = { 4, 1 },
    raid = "Cutting edge", mplus = "No cap", pvp = "No cap", delves = "Nemesis boss", gear = "Myth" },
}

--------------------------------------------------------------------------
-- Spell IDs used only by /irl verify to confirm names at any level
-- (pre-Midnight values; verify reports any that now resolve differently).
--------------------------------------------------------------------------
IRL.SpellIDHints = {
  ["Fists of Fury"] = 113656,
  ["Strike of the Windlord"] = 392983,
  ["Tiger's Lust"] = 116841,
  ["Chi Torpedo"] = 115008,
  ["Celerity"] = 115173,
  ["Invoke Xuen, the White Tiger"] = 123904,
  ["Whirling Dragon Punch"] = 152175,
  ["Ring of Peace"] = 116844,
  ["Paralysis"] = 115078,
  ["Transcendence"] = 101643,
  ["Diffuse Magic"] = 122783,
  ["Dampen Harm"] = 122278,
  ["Touch of Karma"] = 122470,
  ["Storm, Earth, and Fire"] = 137639,
  ["Fortifying Brew"] = 115203,
}
