-- Plain Lua 5.1 tests for the addon's pure logic. Run from the addon folder:
--   lua5.1 tests/run.lua
-- WoW-only files (Detect/Casts, Detect/Talents, UI/*) are exercised in game.
package.path = "./?.lua;" .. package.path

-- WoW exposes these as globals.
date, time = os.date, os.time

local IRL = {}
local function load(path)
  local chunk = assert(loadfile(path))
  chunk("IRLStats", IRL)
end

for _, f in ipairs({
  "Init.lua", "Data/Tests.lua", "Data/Gates.lua", "Data/Norms.lua",
  "Core/Units.lua", "Core/Milestones.lua", "Core/Streaks.lua", "Core/Gates.lua", "Core/DB.lua",
  "Detect/Flags.lua",
}) do load(f) end

-- Minimal WoW stubs used by Detect/Flags.lua
local clock = 1000
function GetTime() return clock end
function GetRealZoneText() return "Dornogal" end
function UnitAffectingCombat() return true end
function InCombatLockdown() return true end

-- Controllable wall clock: start at 2026-09-25 21:00 local.
local now = os.time({ year = 2026, month = 9, day = 25, hour = 21 })
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
local function near(a, b, msg) if math.abs(a - b) > 1e-6 then eq(a, b, msg) end end

local function fresh()
  IRLStatsDB, IRLStatsCharDB = nil, nil
  IRL.state = nil
  IRL.lastFlagAt = {}
  IRL.InitDB()
  IRL.Recompute()
end

------------------------------------------------------------------------
test("units: imperial jump formatting and parsing", function()
  fresh()
  eq(IRL.Units.Format("broadjump", 90 * 2.54), "7 ft 6 in")
  near(IRL.Units.Parse("broadjump", "7'6"), 90 * 2.54)
  near(IRL.Units.Parse("broadjump", "7 ft 6 in"), 90 * 2.54)
  near(IRL.Units.Parse("broadjump", "90"), 90 * 2.54)
  eq(IRL.Units.Phrase("broadjump", 90 * 2.54), "a 7 ft 6 in broad jump")
end)

test("units: times, m:ss and metric", function()
  fresh()
  eq(IRL.Units.Format("dash40", 4.95), "4.95 s")
  near(IRL.Units.Parse("row2k", "7:05.3"), 425.3)
  eq(IRL.Units.Format("row2k", 425.3), "7:05.3")
  IRL.db.profile.units = "metric"
  eq(IRL.Units.Format("broadjump", 229), "229 cm")
  near(IRL.Units.Parse("grip", "50"), 50)
  IRL.db.profile.units = "imperial"
  near(IRL.Units.Parse("grip", "110"), 110 / 2.20462)
  eq(select(2, IRL.Units.Parse("grip", "abc")) ~= nil, true)
end)

test("milestones: higher-is-better steps +5% and ends at goal", function()
  local r = IRL.Milestones.Build("broadjump", 200, 229, 0.05, false, 30)
  eq(r[1], 210); eq(r[2], 220); eq(r[#r], 229); eq(#r, 3)
end)

test("milestones: lower-is-better steps subtract", function()
  local r = IRL.Milestones.Build("dash40", 5.20, 4.80, 0.015, false, 30)
  near(r[1], 5.12); near(r[2], 5.04)
  eq(r[#r], 4.80)
  for i = 2, #r do eq(r[i] < r[i - 1], true, "strictly faster") end
end)

test("milestones: rounding never stalls (reps)", function()
  local r = IRL.Milestones.Build("pullups", 3, 8, 0.10, false, 30)
  eq(r[1], 4); eq(r[#r], 8)
  for i = 2, #r do eq(r[i] > r[i - 1], true) end
end)

test("milestones: skill ladders step one level", function()
  local r = IRL.Milestones.Build("planche", 1, 8, 1, true, 30)
  eq(#r, 7); eq(r[1], 2); eq(r[7], 8)
end)

test("milestones: goal already met gives one rung", function()
  local r = IRL.Milestones.Build("broadjump", 240, 229, 0.05, false, 30)
  eq(#r, 1); eq(r[1], 229)
end)

test("placement: gates spread below top three, apex on last three", function()
  local g, a = IRL.Milestones.Place(7, 2, true, 3)
  eq(g[1], 1); eq(g[2], 4); eq(a[1], 5); eq(a[2], 6); eq(a[3], 7)
  g = IRL.Milestones.Place(10, 4, false, 3)
  eq(g[1], 1); eq(g[2], 3); eq(g[3], 5); eq(g[4], 7)
  g, a = IRL.Milestones.Place(2, 2, true, 3)
  eq(g[1], 1); eq(g[2], 1); eq(a[1], 1); eq(a[2], 1); eq(a[3], 2)
end)

test("gates: everything locked before setup", function()
  fresh()
  eq(IRL.FindGate("Roll").unlocked, false)
  eq(IRL.FindGate("Roll").kind, "unset")
  eq(IRL.FindGate("fortifying brew").unlocked, false, "case-insensitive lookup")
end)

test("gates: logging a PR that passes a milestone unlocks and toasts", function()
  fresh()
  IRL.SetTest("power", "broadjump")
  IRL.LogPR("power", 200)
  IRL.SetGoal("power", 280)            -- rungs 210..280: gates on rungs 1 and 5
  eq(IRL.FindGate("Flying Serpent Kick").unlocked, false)
  local improved, gained = IRL.LogPR("power", 212)
  eq(improved, true)
  eq(IRL.FindGate("Flying Serpent Kick").unlocked, true)
  eq(gained[1], "Flying Serpent Kick")
  eq(IRL.FindGate("Strike of the Windlord").unlocked, false)
  -- A worse result is logged but doesn't lower the PR or relock.
  improved = IRL.LogPR("power", 190)
  eq(improved, false)
  eq(IRL.db.categories.power.pr, 212)
  eq(#IRL.db.categories.power.history, 3)
  eq(IRL.FindGate("Flying Serpent Kick").unlocked, true)
end)

test("gates: requirement text matches the spec's style", function()
  fresh()
  IRL.SetTest("power", "broadjump")
  IRL.LogPR("power", 80 * 2.54)
  IRL.SetGoal("power", 96 * 2.54)
  local req = IRL.FindGate("Flying Serpent Kick").requirement
  eq(req:match("^Unlocks at a %d+ ft %d+ in broad jump$") ~= nil, true, req)
end)

test("gates: apex ranks on the last three rungs; rank 3 grants Zenith Stomp", function()
  fresh()
  IRL.SetTest("body", "planche")
  IRL.LogPR("body", 1)
  IRL.SetGoal("body", 8)  -- rungs 2..8 (7 rungs): gates 1,4; apex 5,6,7
  eq(IRL.state.apex["Tigereye Brew"].unlockedRanks, 0)
  IRL.LogPR("body", 6)    -- rung 5
  eq(IRL.state.apex["Tigereye Brew"].unlockedRanks, 1)
  eq(IRL.FindGate("Zenith").unlocked, true)
  eq(IRL.FindGate("Zenith Stomp").unlocked, false)
  local _, gained = IRL.LogPR("body", 8)
  eq(IRL.state.apex["Tigereye Brew"].unlockedRanks, 3)
  eq(IRL.FindGate("Zenith Stomp").unlocked, true)
  local s = table.concat(gained, ",")
  eq(s:find("Tigereye Brew rank 3") ~= nil, true, s)
end)

test("habit: Fortifying Brew unlocks on check-in and relocks next day", function()
  fresh()
  eq(IRL.FindGate("Fortifying Brew").unlocked, false)
  eq(IRL.CheckIn(), true)
  eq(IRL.CheckIn(), false, "second check-in same day is a no-op")
  eq(IRL.FindGate("Fortifying Brew").unlocked, true)
  advanceDays(1)
  IRL.CheckDayRollover()
  eq(IRL.FindGate("Fortifying Brew").unlocked, false)
end)

test("habit: 11 pm check-in counts for that calendar day", function()
  fresh()
  local d = os.date("*t", now)
  now = os.time({ year = d.year, month = d.month, day = d.day, hour = 23, min = 30 })
  IRL.CheckIn()
  eq(IRL.db.habit.last, os.date("%Y-%m-%d", now))
  now = now + 45 * 60  -- 00:15 next day
  IRL.CheckDayRollover()
  eq(IRL.FindGate("Fortifying Brew").unlocked, false)
end)

test("pt streak: three missed days lock; one session revives; best unchanged", function()
  fresh()
  eq(IRL.FindGate("Vivify").unlocked, false, "no streak yet")
  for i = 1, 5 do IRL.LogSession("pt"); advanceDays(1) end
  -- sessions on 5 consecutive days; now on day 6 with nothing logged yet
  eq(IRL.db.streaks.pt.best, 5)
  IRL.CheckDayRollover()
  eq(IRL.FindGate("Vivify").unlocked, true)
  advanceDays(3) -- sessions days 0-4; days 5, 6, 7 missed; now day 8
  IRL.CheckDayRollover()
  local alive, cur, strikes = IRL.StreakStatus("pt")
  eq(alive, false); eq(strikes, 3)
  eq(IRL.FindGate("Vivify").unlocked, false)
  eq(IRL.FindGate("Expel Harm").unlocked, false)
  IRL.LogSession("pt")
  alive, cur, strikes = IRL.StreakStatus("pt")
  eq(alive, true); eq(cur, 1); eq(strikes, 0)
  eq(IRL.FindGate("Vivify").unlocked, true)
  eq(IRL.db.streaks.pt.best, 5)
end)

test("pt streak: strikes are used up over a streak's life", function()
  fresh()
  IRL.LogSession("pt")          -- day 0
  advanceDays(2); IRL.LogSession("pt")  -- missed 1 day
  advanceDays(2); IRL.LogSession("pt")  -- missed 1 more
  local alive, cur, strikes = IRL.StreakStatus("pt")
  eq(alive, true); eq(cur, 3); eq(strikes, 2)
  advanceDays(2)                -- third miss
  alive = IRL.StreakStatus("pt")
  eq(alive, false)
end)

test("training streak gates Shado-Pan", function()
  fresh()
  eq(IRL.state.heroTrees["Shado-Pan"].unlocked, false)
  IRL.LogSession("training")
  eq(IRL.state.heroTrees["Shado-Pan"].unlocked, true)
end)

test("balance: Conduit needs a milestone in speed, grip, mobility and power", function()
  fresh()
  local function setup(cat, test, pr, goal)
    IRL.SetTest(cat, test); IRL.LogPR(cat, pr); IRL.SetGoal(cat, goal)
  end
  setup("speed", "dash40", 5.2, 4.8)
  setup("grip", "grip", 40, 50)
  setup("mobility", "frontsplit", 1, 5)
  setup("power", "broadjump", 200, 240)
  eq(IRL.state.heroTrees["Conduit of the Celestials"].unlocked, false)
  IRL.LogPR("speed", 5.1); IRL.LogPR("grip", 44); IRL.LogPR("mobility", 2)
  eq(IRL.state.heroTrees["Conduit of the Celestials"].unlocked, false)
  IRL.LogPR("power", 210)
  eq(IRL.state.heroTrees["Conduit of the Celestials"].unlocked, true)
end)

test("goals and PRs are account-wide; flags are per character", function()
  fresh()
  IRL.SetTest("grip", "grip"); IRL.LogPR("grip", 40); IRL.SetGoal("grip", 50)
  IRL.AddFlag("Roll", "cast")
  -- Log in on a second character: account DB persists, char DB is new.
  local account = IRLStatsDB
  IRLStatsCharDB = nil
  IRL.InitDB()
  eq(IRLStatsDB, account)
  eq(IRL.db.categories.grip.pr, 40)
  eq(#IRL.char.flags, 0)
end)

test("flags: same locked cast flags at most once per 60 s", function()
  fresh()
  eq(IRL.AddFlag("Tiger's Lust", "cast"), true)
  clock = clock + 30
  eq(IRL.AddFlag("Tiger's Lust", "cast"), false)
  eq(IRL.AddFlag("Roll", "cast"), true, "other spells unaffected")
  clock = clock + 31
  eq(IRL.AddFlag("Tiger's Lust", "cast"), true)
  eq(#IRL.char.flags, 3)
  eq(IRL.char.flags[1].zone, "Dornogal")
  eq(IRL.char.flags[1].combat, true)
end)

test("locked message names the next milestone", function()
  fresh()
  IRL.SetTest("speed", "dash40"); IRL.LogPR("speed", 5.02); IRL.SetGoal("speed", 4.6)
  local msg = IRL.LockedMessage(IRL.FindGate("Tiger's Lust"))
  eq(msg, "Locked: Tiger's Lust - next milestone 4.94 s 40-yard dash")
end)

test("norms: 90th percentile pre-fill by age and sex", function()
  near(IRL.NormFor("vo2max", 34, "male"), 56.5)
  near(IRL.NormFor("grip", 34, "female"), 38)
  eq(IRL.NormFor("vertjump", 75, "male"), nil, "outside CHMS ages")
  eq(IRL.NormFor("broadjump", 34, "male"), nil, "no norm for this test")
  eq(IRL.NormFor("grip", 34, nil), nil)
end)

test("rebaseline restarts the ladder from the current PR", function()
  fresh()
  IRL.SetTest("grip", "grip"); IRL.LogPR("grip", 40); IRL.SetGoal("grip", 60)
  IRL.LogPR("grip", 44)
  eq(IRL.state.categories.grip.achieved, 1)
  IRL.Rebaseline("grip")
  eq(IRL.state.categories.grip.achieved, 0)
  eq(IRL.state.categories.grip.rungs[1], 48.5)
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
