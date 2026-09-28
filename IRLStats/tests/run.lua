-- Plain Lua 5.1 tests for the addon's pure logic (the Gymlocke rules engine,
-- saved data, flags). Run from the addon folder:
--   lua5.1 tests/run.lua
-- WoW-only files are exercised by tests/smoke.lua and in game.
date, time = os.date, os.time -- WoW exposes these as globals

local IRL = {}
local function load(path) assert(loadfile(path))("IRLStats", IRL) end
for _, f in ipairs({
  "Init.lua", "Data/Rulebook.lua", "Data/Tests.lua",
  "Core/Units.lua", "Core/Rules.lua", "Core/DB.lua", "Detect/Flags.lua",
}) do load(f) end

-- Minimal WoW stubs
local clock, level = 1000, 90
function GetTime() return clock end
function GetRealZoneText() return "Dornogal" end
function UnitAffectingCombat() return true end
function InCombatLockdown() return true end
function UnitLevel() return level end

local now = os.time({ year = 2026, month = 9, day = 28, hour = 18 })
IRL.Now = function() return now end
local function advanceDays(n) now = now + n * 86400 end

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed = failed + 1; print("FAIL " .. name .. "\n     " .. tostring(err)) end
end
local function eq(a, b, msg)
  if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end
end

local function fresh()
  IRLStatsDB, IRLStatsCharDB = nil, nil
  IRL.state, IRL.nodeMeta, IRL.lastFlagAt = nil, {}, {}
  level = 90
  IRL.InitDB()
  IRL.Recompute()
end

-- Log the same tier in every discipline, or a table { pull = 2, ... }.
local function testDay(tiers)
  for _, key in ipairs(IRL.DisciplineOrder) do
    IRL.LogDiscipline(key, type(tiers) == "table" and (tiers[key] or 0) or tiers)
  end
end

local function node(name, extra)
  local m = { name = name }
  for k, v in pairs(extra or {}) do m[k] = v end
  return IRL.Rules.Evaluate(IRL.state.ctx, m)
end

------------------------------------------------------------------------
test("before Test Day nothing is open", function()
  fresh()
  eq(IRL.state.open[0], false)
  eq(node("Tiger Palm", { section = 1 }).unlocked, false)
  eq(IRL.state.rank, 1)
end)

test("Gate 0: filming all six opens the top section, even at tier None", function()
  fresh()
  testDay(0)
  eq(IRL.state.open[0], true)
  eq(IRL.state.open[1], false)
  eq(node("Tiger Palm", { section = 1 }).unlocked, true)
  eq(node("Some builder", { section = 2 }).unlocked, false)
end)

test("Gate 1: Bronze in all six opens the middle section", function()
  fresh()
  testDay(1)
  eq(IRL.state.open[1], true)
  eq(node("Some builder", { section = 2 }).unlocked, true)
  eq(node("Some finisher", { section = 3 }).unlocked, false)
end)

test("keyed talent needs its gate and its key", function()
  fresh()
  testDay(1)
  local fof = IRL.FindGate("Fists of Fury")
  eq(fof.unlocked, false)
  eq(fof.missing[1], "Key: Push Silver (35 push-ups)")
  IRL.LogDiscipline("push", 2)
  eq(IRL.FindGate("Fists of Fury").unlocked, true)
end)

test("key follows the talent, whatever section Midnight put it in", function()
  fresh()
  testDay({ pull = 2, push = 1, press = 1, legs = 1, core = 1, flex = 1 })
  eq(node("Strike of the Windlord", { section = 3 }).unlocked, true, "opens at Gate 1 regardless of section")
end)

test("Gate 2: Silver in 2 opens major cooldowns; Xuen also needs Core Gold", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 1, legs = 1, core = 1, flex = 1 })
  eq(IRL.state.open[2], true)
  eq(IRL.FindGate("Zenith").unlocked, true)
  eq(IRL.FindGate("Invoke Xuen, the White Tiger").unlocked, false)
  IRL.LogDiscipline("core", 3)
  eq(IRL.FindGate("Invoke Xuen, the White Tiger").unlocked, true)
end)

test("Gate 3: Silver in 4 opens the bottom section and Adept rank", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 1 })
  eq(IRL.state.open[3], true)
  eq(IRL.state.rank, 2)
  eq(node("Bottom talent", { section = 3 }).unlocked, true)
end)

test("capstones need Gate 3 and Gold in any one", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 1 })
  eq(node("Capstone", { section = 3, isCapstone = true }).unlocked, false)
  IRL.LogDiscipline("pull", 3)
  eq(node("Capstone", { section = 3, isCapstone = true }).unlocked, true)
end)

test("Fortifying Brew upgrades need Gate 3 and Core Silver", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 1 })
  eq(node("Fortifying Brew: Determination", { section = 1 }).unlocked, false)
  eq(node("Fortifying Brew", { section = 1 }).unlocked, true, "the base spell is not an upgrade")
  IRL.LogDiscipline("core", 2)
  eq(node("Fortifying Brew: Determination", { section = 1 }).unlocked, true)
end)

test("Gate 4: hero talents need level 71 and Flexibility Silver; final node Gold in 2", function()
  fresh()
  level = 70
  testDay({ pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 2 })
  eq(IRL.state.open[4], false, "level 70")
  level = 71; IRL.Recompute()
  eq(IRL.state.open[4], true)
  eq(node("Hero node", { heroTree = "Shado-Pan" }).unlocked, true)
  eq(node("Final", { heroTree = "Shado-Pan", isHeroFinal = true }).unlocked, false)
  IRL.LogDiscipline("pull", 3); IRL.LogDiscipline("push", 3)
  eq(node("Final", { heroTree = "Shado-Pan", isHeroFinal = true }).unlocked, true)
end)

test("apex: Gate 5, then rank 1 Gold in 1, ranks 2-3 Gold in 2, rank 4 Legendary in 1", function()
  fresh()
  testDay({ pull = 3, push = 2, press = 2, legs = 2, core = 2, flex = 2 })
  eq(IRL.state.open[5], true)
  eq(node("Tigereye Brew", { isApex = true, rank = 1 }).unlocked, true)
  eq(node("Tigereye Brew", { isApex = true, rank = 3 }).unlocked, false)
  IRL.LogDiscipline("push", 3)
  eq(node("Tigereye Brew", { isApex = true, rank = 3 }).unlocked, true)
  eq(node("Tigereye Brew", { isApex = true, rank = 4 }).unlocked, false)
  IRL.LogDiscipline("pull", 4)
  eq(node("Tigereye Brew", { isApex = true, rank = 4 }).unlocked, true)
  eq(IRL.state.rank, 4, "Grandmaster")
end)

test("ranks: Master needs Gold in 2 on top of Adept", function()
  fresh()
  testDay({ pull = 3, push = 3, press = 1, legs = 1, core = 1, flex = 1 })
  eq(IRL.state.rank, 1, "Gold in 2 but no Gate 3")
  IRL.LogDiscipline("press", 2); IRL.LogDiscipline("legs", 2)
  eq(IRL.state.rank, 3)
end)

test("supporting tests: % faster than baseline, rounded up", function()
  local t = IRL.Rules.SupportTargets(480) -- 8:00 mile
  eq(t[1], 480); eq(t[2], 456); eq(t[3], 432); eq(t[4], 408)
  t = IRL.Rules.SupportTargets(250)
  eq(t[2], 238, "237.5 ms rounds up")
end)

test("mile Silver unlocks Transcendence and flying", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 1, legs = 1, core = 1, flex = 1 })
  eq(IRL.state.flying, false)
  IRL.LogSupport("mile", 480)
  eq(IRL.db.supports.mile.baseline, 480)
  eq(IRL.Rules.Tier(IRL.db, "mile"), 1, "matching baseline is Bronze")
  eq(IRL.FindGate("Transcendence").unlocked, false)
  local gained = IRL.LogSupport("mile", 455)
  eq(IRL.Rules.Tier(IRL.db, "mile"), 2)
  eq(IRL.FindGate("Transcendence").unlocked, true)
  eq(IRL.state.flying, true)
  eq(table.concat(gained, ","):find("Flying") ~= nil, true)
end)

test("reaction Silver unlocks Ring of Peace and Paralysis at Gate 2", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 1, legs = 1, core = 1, flex = 1 })
  IRL.LogSupport("reaction", 250); IRL.LogSupport("reaction", 235)
  eq(IRL.FindGate("Ring of Peace").unlocked, true)
  eq(IRL.FindGate("Paralysis").unlocked, true)
end)

test("failed retest drops the tier at once and opens a 7-day retry", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 1, legs = 1, core = 1, flex = 1 })
  eq(IRL.FindGate("Strike of the Windlord").unlocked, true)
  advanceDays(30)
  local _, lost = IRL.LogDiscipline("pull", 1)
  eq(IRL.FindGate("Strike of the Windlord").unlocked, false)
  eq(IRL.state.open[2], false, "back below Silver in 2")
  local e = IRL.db.disciplines.pull
  eq(e.lostTier, 2)
  eq(IRL.Rules.RetryLeft(e, IRL.Today()), 7)
  eq(table.concat(lost, ","):find("Strike of the Windlord") ~= nil, true)
  advanceDays(3)
  IRL.LogDiscipline("pull", 2)
  eq(e.lostTier, nil, "retry passed clears the window")
  eq(IRL.FindGate("Strike of the Windlord").unlocked, true)
end)

test("dropping below Gate 3 sends you back to Solo Only", function()
  fresh()
  testDay({ pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 1 })
  eq(IRL.state.rank, 2)
  IRL.LogDiscipline("legs", 1)
  eq(IRL.state.rank, 1)
end)

test("retest due 30 days after the last test", function()
  fresh()
  testDay(1)
  advanceDays(25)
  eq(IRL.Rules.RetestDue(IRL.db.disciplines.pull, IRL.Today()), 5)
  advanceDays(10)
  eq(IRL.Rules.RetestDue(IRL.db.disciplines.pull, IRL.Today()), -5)
end)

test("v1 saved data is archived, not lost", function()
  IRLStatsDB = { version = 1, categories = { grip = { pr = 40 } }, streaks = {}, habit = {}, setupDone = true }
  IRLStatsCharDB = nil
  IRL.InitDB()
  eq(IRLStatsDB.version, 2)
  eq(IRLStatsDB.legacyV1.categories.grip.pr, 40)
  eq(IRLStatsDB.categories, nil)
  eq(IRLStatsDB.disciplines.pull.tier, 0)
end)

test("tiers are account-wide; flags are per character", function()
  fresh()
  testDay(1)
  IRL.AddFlag("Fists of Fury", "cast")
  IRLStatsCharDB = nil
  IRL.InitDB()
  eq(IRL.db.disciplines.push.tier, 1)
  eq(#IRL.char.flags, 0)
end)

test("flags: same locked cast flags at most once per 60 s", function()
  fresh()
  eq(IRL.AddFlag("Tiger's Lust", "cast"), true)
  clock = clock + 30
  eq(IRL.AddFlag("Tiger's Lust", "cast"), false)
  clock = clock + 31
  eq(IRL.AddFlag("Tiger's Lust", "cast"), true)
  eq(IRL.char.flags[1].combat, true)
end)

test("locked message names the first missing requirement", function()
  fresh()
  testDay(1)
  eq(IRL.LockedMessage(IRL.FindGate("Fists of Fury")), "Locked: Fists of Fury - needs Key: Push Silver (35 push-ups)")
end)

test("tree meta overrides rule-only judgement for the same name", function()
  fresh()
  testDay(1)
  IRL.nodeMeta["some capstone"] = { name = "Some Capstone", section = 3, isCapstone = true }
  IRL.Recompute("loadout")
  local g = IRL.FindGate("Some Capstone")
  eq(g.unlocked, false)
  eq(g.kind, "talent")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
