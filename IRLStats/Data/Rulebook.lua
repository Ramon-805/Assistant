-- Gymlocke rulebooks: one per spec (Windwalker from the Sep 27, 2026
-- rulebook; Brewmaster designed with Ray, Sep 30, 2026). Everything the rules
-- engine (Core/Rules.lua) needs lives here; nothing else hard-codes the
-- rules. Each spec has its own six disciplines, gates and rank. The mile and
-- reaction time are shared supporting tests.
local _, IRL = ...

-- Tier 0 = not yet Bronze.
IRL.Tiers = { "Bronze", "Silver", "Gold", "Legendary" }
IRL.TierColors = {
  [0] = "ff999999", [1] = "ffcd7f32", [2] = "ffc0c0c0", [3] = "ffffd100", [4] = "ffff8000",
}

--------------------------------------------------------------------------
-- Measured (percent-over-baseline) scales. Bronze matches your baseline;
-- each tier after is a set percent better. Targets round up to the next
-- whole unit (rep, second, millisecond). Higher-is-better tests use
-- PercentTiers; lower-is-better times use SupportTierPercent.
--------------------------------------------------------------------------
IRL.PercentTiers = { 0, 0.15, 0.30, 0.50 }
IRL.SupportTierPercent = { 0, 0.05, 0.10, 0.15 }

--------------------------------------------------------------------------
-- Supporting tests, shared by every spec. They don't count toward rank;
-- they only key some talents (and flying).
--------------------------------------------------------------------------
IRL.SupportOrder = { "mile", "reaction" }
IRL.Supports = {
  mile     = { label = "Mile run", test = "mile", lower = true, percents = IRL.SupportTierPercent },
  reaction = { label = "Reaction time", test = "reaction", lower = true, percents = IRL.SupportTierPercent },
}

--------------------------------------------------------------------------
-- Retests: every discipline monthly; a failed retest drops the tier at once
-- and allows one re-attempt within 7 days.
--------------------------------------------------------------------------
IRL.RetestDays = 30
IRL.RetryDays = 7

--------------------------------------------------------------------------
-- Rules shared by every spec
--------------------------------------------------------------------------
IRL.GateCount = 5

-- Tree section (1 = top, 2 = middle, 3 = bottom) -> gate that opens it.
IRL.SectionGate = { 0, 1, 3 }

-- Bottom row of the spec tree (apex excluded): Gate 3 + Gold in any one.
IRL.CapstoneRule = { gate = 3, need = { 3, 1 } }

-- Hero talents: Gate 4; the final (bottom) node of the hero tree needs Gold in 2.
IRL.HeroRule = { gate = 4, finalNeed = { 3, 2 } }

-- Apex (Gate 5). Rank r needs the entry with the highest minRank <= r.
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

-- Keys on supporting tests, so they hold on every spec.
local sharedKeys = {
  ["Ring of Peace"]  = { gate = 2, key = { "reaction", 2 } },
  ["Paralysis"]      = { gate = 2, key = { "reaction", 2 } },
  ["Transcendence"]  = { gate = 2, key = { "mile", 2 } },
}

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
-- Rulebooks
--   disciplines[key]  landmark (default): tier = highest landmark on camera
--                     scale = "percent": tier from your Test Day baseline
--   keys[name]        { gate, key = { discipline or support, tier } }; "Opens
--                     at" overrides the tree section, so a key follows its talent
--   patternKeys       talents matched by name: contains `pattern` (and isn't in
--                     `except`), or is listed in `extra`; `label` names the group
--   majorCooldowns    Gate 2 nodes with no key
--   heroKey           the discipline (and tier) Gate 4 needs, with level 71
--------------------------------------------------------------------------
IRL.Rulebooks = {}
IRL.RulebookOrder = { "windwalker", "brewmaster" }
IRL.SpecRulebook = { [269] = "windwalker", [268] = "brewmaster" }
IRL.SpellIDHints = {}

local function Merge(...)
  local out = {}
  for _, t in ipairs({ ... }) do for k, v in pairs(t) do out[k] = v end end
  return out
end

local function Register(rb)
  rb.keys = Merge(sharedKeys, rb.keys)
  rb.patternKeys = rb.patternKeys or {}
  rb.majorCooldowns = rb.majorCooldowns or {}
  rb.gateDefs = {
    [0] = { name = "Test Day", requirement = "All six disciplines filmed", testDay = true,
            opens = "Top of class and spec trees, baseline abilities" },
    [1] = { name = "Wave 2", requirement = "Bronze in all six", need = { 1, 6 },
            opens = "Middle of both trees: builders and spenders" },
    [2] = { name = "Wave 3", requirement = "Silver in 2", need = { 2, 2 },
            opens = "Major cooldowns" },
    [3] = { name = "Wave 4", requirement = "Silver in 4", need = { 2, 4 },
            opens = "Bottom of both trees + group content" },
    [4] = { name = "Hero talents",
            requirement = "Level 71 + " .. rb.disciplines[rb.heroKey[1]].label .. " Silver",
            level = 71, key = rb.heroKey, opens = rb.heroText },
    [5] = { name = "Apex", requirement = "Level 81", level = 81, opens = "Apex talent" },
  }
  for name, id in pairs(rb.spellIDHints or {}) do IRL.SpellIDHints[name] = id end
  IRL.Rulebooks[rb.key] = rb
end

--------------------------------------------------------------------------
-- Windwalker (calisthenics skills)
--------------------------------------------------------------------------
Register({
  key = "windwalker", label = "Windwalker", specID = 269,
  heroKey = { "flex", 2 },
  heroText = "Shado-Pan or Conduit of the Celestials",
  heroTrees = { "Shado-Pan", "Conduit of the Celestials" },
  dayOne = "Flexibility, Press, Pull, Push, Legs, Core, reaction time",
  disciplineOrder = { "pull", "push", "press", "legs", "core", "flex" },
  disciplines = {
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
  },
  keys = {
    ["Fists of Fury"]                = { gate = 1, key = { "push", 2 } },
    ["Strike of the Windlord"]       = { gate = 1, key = { "pull", 2 } },
    ["Tiger's Lust"]                 = { gate = 1, key = { "legs", 2 } },
    ["Chi Torpedo"]                  = { gate = 1, key = { "flex", 2 } },
    ["Celerity"]                     = { gate = 1, key = { "flex", 2 } },
    ["Invoke Xuen, the White Tiger"] = { gate = 2, key = { "core", 3 } },
    ["Whirling Dragon Punch"]        = { gate = 2, key = { "press", 2 } },
    ["Diffuse Magic"]                = { gate = 3, key = { "flex", 3 } },
    ["Dampen Harm"]                  = { gate = 3, key = { "flex", 3 } },
  },
  -- Gate 2 "major cooldowns" that carry no key. Check these names in game.
  majorCooldowns = { "Zenith", "Touch of Karma", "Storm, Earth, and Fire" },
  -- Fortifying Brew upgrades: Gate 3 + Core Silver.
  patternKeys = {
    { label = "Fortifying Brew upgrades", pattern = "fortif", except = { "fortifying brew" },
      extra = { "Ironshell Brew" }, gate = 3, key = { "core", 2 } },
  },
  apexNames = { "Tigereye Brew" }, -- any 4-rank spec node also counts
  spellIDHints = {
    ["Fists of Fury"] = 113656, ["Strike of the Windlord"] = 392983, ["Tiger's Lust"] = 116841,
    ["Chi Torpedo"] = 115008, ["Celerity"] = 115173, ["Invoke Xuen, the White Tiger"] = 123904,
    ["Whirling Dragon Punch"] = 152175, ["Ring of Peace"] = 116844, ["Paralysis"] = 115078,
    ["Transcendence"] = 101643, ["Diffuse Magic"] = 122783, ["Dampen Harm"] = 122278,
    ["Touch of Karma"] = 122470, ["Storm, Earth, and Fire"] = 137639, ["Fortifying Brew"] = 115203,
  },
})

--------------------------------------------------------------------------
-- Brewmaster (endurance, bracing and balance). All six are measured against
-- your Test Day baseline, so Bronze is free and Gate 1 opens on Test Day;
-- Silver is the first real work. Talent names here come from the Midnight
-- 12.1 guides: confirm them with /irl verify.
--------------------------------------------------------------------------
Register({
  key = "brewmaster", label = "Brewmaster", specID = 268,
  heroKey = { "mobility", 2 },
  heroText = "Shado-Pan or Master of Harmony",
  heroTrees = { "Shado-Pan", "Master of Harmony" },
  dayOne = "Balance, Mobility, Hang, Power, Brace, Endurance, reaction time",
  disciplineOrder = { "endurance", "brace", "hang", "power", "mobility", "balance" },
  disciplines = {
    endurance = {
      label = "Endurance", equipment = "Floor, timer", scale = "percent", unit = "reps",
      measure = "Burpees in 5 minutes", phrase = "%s burpees in 5 minutes",
      form = "Set a 5-minute timer. Chest to the floor, then jump with hands overhead. Count full reps; the set ends when the timer does.",
    },
    brace = {
      label = "Brace", equipment = "Wall", scale = "percent", unit = "hold",
      measure = "Wall sit", phrase = "a %s wall sit",
      form = "Back flat on the wall, thighs parallel to the floor, timer visible. The attempt ends the moment your thighs rise or your hands touch your knees.",
    },
    hang = {
      label = "Hang", equipment = "Pull-up bar", scale = "percent", unit = "hold",
      measure = "Dead hang", phrase = "a %s dead hang",
      form = "Hang from the bar with straight arms, no kipping or swinging. The attempt ends when your hands leave the bar.",
    },
    power = {
      label = "Power", equipment = "Floor, timer", scale = "percent", unit = "reps",
      measure = "Squat jumps in 60 seconds", phrase = "%s squat jumps in 60 s",
      form = "Squat to at least parallel, then jump with both feet leaving the floor together. Count clean reps for 60 seconds.",
    },
    mobility = {
      label = "Mobility", equipment = "Floor", scale = "percent", unit = "hold",
      measure = "Deep squat hold", phrase = "a %s deep squat hold",
      form = "Heels flat, hips below the knees, chest up, hands off everything. The attempt ends when your heels lift or you stand.",
    },
    balance = {
      label = "Balance", equipment = "Floor", scale = "percent", unit = "hold",
      measure = "Single-leg stand, eyes closed", phrase = "a %s single-leg stand",
      form = "Stand on your weaker leg, eyes closed, arms crossed on your chest. The attempt ends when your raised foot touches down or your eyes open.",
    },
  },
  keys = {
    -- Class talents shared with Windwalker, keyed to Brewmaster's disciplines.
    ["Tiger's Lust"]                 = { gate = 1, key = { "power", 2 } },
    ["Chi Torpedo"]                  = { gate = 1, key = { "mobility", 2 } },
    ["Celerity"]                     = { gate = 1, key = { "mobility", 2 } },
    ["Diffuse Magic"]                = { gate = 3, key = { "balance", 3 } },
    ["Dampen Harm"]                  = { gate = 3, key = { "balance", 3 } },
    -- Spec talents.
    ["Elixir of Determination"]      = { gate = 1, key = { "brace", 2 } },
    ["Black Ox Brew"]                = { gate = 2, key = { "endurance", 2 } },
    ["Exploding Keg"]                = { gate = 2, key = { "power", 2 } },
    ["Invoke Niuzao, the Black Ox"]  = { gate = 2, key = { "endurance", 3 } },
  },
  patternKeys = {
    { label = "Fortifying Brew upgrades", pattern = "fortif", except = { "fortifying brew" },
      extra = { "Ironshell Brew" }, gate = 3, key = { "brace", 2 } },
    { label = "Celestial Brew upgrades", pattern = "celestial", except = { "celestial brew" }, gate = 3, key = { "brace", 2 } },
    { label = "Purifying Brew upgrades", pattern = "purif", except = { "purifying brew" }, gate = 3, key = { "hang", 2 } },
    { label = "Stagger talents", pattern = "stagger", gate = 2, key = { "hang", 2 } },
  },
  apexNames = { "Bring Me Another" },
  spellIDHints = {
    ["Invoke Niuzao, the Black Ox"] = 132578, ["Black Ox Brew"] = 115399, ["Exploding Keg"] = 325153,
    ["Tiger's Lust"] = 116841, ["Chi Torpedo"] = 115008, ["Celerity"] = 115173,
    ["Diffuse Magic"] = 122783, ["Dampen Harm"] = 122278, ["Ring of Peace"] = 116844,
    ["Paralysis"] = 115078, ["Transcendence"] = 101643, ["Fortifying Brew"] = 115203,
  },
})

-- Discipline keys must be unique across rulebooks: tests are stored as d_<key>.
do
  local seen = {}
  for _, rbKey in ipairs(IRL.RulebookOrder) do
    for _, key in ipairs(IRL.Rulebooks[rbKey].disciplineOrder) do
      assert(not seen[key] and not IRL.Supports[key], "duplicate discipline key: " .. key)
      seen[key] = true
    end
  end
end
