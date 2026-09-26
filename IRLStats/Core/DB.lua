-- SavedVariables and the actions that change real-life data. Every change
-- ends in IRL.Recompute(), which rebuilds milestones and unlock state and
-- fires STATE_CHANGED with what was gained or lost.
--
-- IRLStatsDB (account-wide; it's the same body on every character):
--   profile     { age, sex, weight (kg), units = "imperial" | "metric" }
--   categories  [cat] = { test, goal, pr, baseline, direction, history = { {value, date, t} } }
--   milestones  [cat] = { rung values }            (derived cache)
--   habit       { last = "YYYY-MM-DD", lastDay }
--   streaks     { pt = streak, training = streak }  (see Core/Streaks.lua)
--   setupDone, minimap = { angle, hide }
-- IRLStatsCharDB (per character):
--   flags       { {t, name, kind, zone, combat} }  (never pruned)
--   talentSig   last flagged loadout signature
local _, IRL = ...

local DB_VERSION = 1

local function defaults()
  local cats = {}
  for _, cat in ipairs(IRL.CategoryOrder) do cats[cat] = { history = {} } end
  return {
    version = DB_VERSION,
    profile = { units = "imperial" },
    categories = cats,
    milestones = {},
    habit = {},
    streaks = { pt = IRL.Streaks.New(), training = IRL.Streaks.New() },
    setupDone = false,
    minimap = { angle = 215, hide = false },
  }
end

local function fill(target, template)
  for k, v in pairs(template) do
    if target[k] == nil then
      target[k] = IRL.CopyTable(v)
    elseif type(v) == "table" and type(target[k]) == "table" then
      fill(target[k], v)
    end
  end
end

function IRL.InitDB()
  IRLStatsDB = IRLStatsDB or {}
  fill(IRLStatsDB, defaults())
  IRLStatsDB.version = DB_VERSION
  IRLStatsCharDB = IRLStatsCharDB or {}
  IRLStatsCharDB.flags = IRLStatsCharDB.flags or {}
  IRL.db, IRL.char = IRLStatsDB, IRLStatsCharDB
end

--------------------------------------------------------------------------
-- Recompute
--------------------------------------------------------------------------
function IRL.Recompute(reason)
  local db = IRL.db
  local today = IRL.Today()
  local old = IRL.state
  local state = IRL.GateLogic.Compute(db, today)
  for cat, cs in pairs(state.categories) do db.milestones[cat] = cs.rungs end
  IRL.state, IRL.stateDay = state, today
  local gained, lost = IRL.GateLogic.Diff(old, state)
  IRL.Fire("STATE_CHANGED", gained, lost, reason)
  return gained, lost
end

-- Call periodically; recomputes when the local calendar day rolls over so
-- the daily habit relocks and streak strikes land at midnight.
function IRL.CheckDayRollover()
  if IRL.state and IRL.stateDay ~= IRL.Today() then
    IRL.Recompute("day")
  end
end

function IRL.FindGate(name)
  return IRL.GateLogic.Find(IRL.state, name)
end

--------------------------------------------------------------------------
-- Actions
--------------------------------------------------------------------------
function IRL.SetProfile(fields)
  for k, v in pairs(fields) do IRL.db.profile[k] = v end
  IRL.Recompute("profile")
end

-- Choosing a different test starts that category over.
function IRL.SetTest(cat, testKey)
  local c = IRL.db.categories[cat]
  if c.test == testKey then return end
  c.test = testKey
  c.direction = IRL.IsLowerBetter(testKey) and "lower" or "higher"
  c.pr, c.goal, c.baseline = nil, nil, nil
  c.history = {}
  IRL.Recompute("test")
end

function IRL.SetGoal(cat, value)
  local c = IRL.db.categories[cat]
  c.goal = value
  if c.baseline == nil then c.baseline = c.pr end
  return IRL.Recompute("goal")
end

-- Log a result. The PR is the best result ever logged; every entry goes in
-- the history. The first result becomes the ladder's baseline.
function IRL.LogPR(cat, value)
  local c = IRL.db.categories[cat]
  local now = IRL.Now()
  table.insert(c.history, { value = value, date = IRL.DayString(now), t = now })
  local improved = IRL.Units.Better(c.test, value, c.pr)
  if improved then c.pr = value end
  if c.baseline == nil then c.baseline = c.pr end
  local gained, lost = IRL.Recompute("pr")
  return improved, gained, lost
end

-- Restart the ladder from the current PR (e.g. after a long layoff).
function IRL.Rebaseline(cat)
  local c = IRL.db.categories[cat]
  c.baseline = c.pr
  return IRL.Recompute("rebaseline")
end

function IRL.HabitDoneToday()
  return IRL.db.habit.lastDay == IRL.Today()
end

function IRL.CheckIn()
  local now = IRL.Now()
  if IRL.db.habit.lastDay == IRL.DayIndex(now) then return false end
  IRL.db.habit.lastDay = IRL.DayIndex(now)
  IRL.db.habit.last = IRL.DayString(now)
  IRL.Recompute("habit")
  return true
end

-- which = "pt" or "training"
function IRL.LogSession(which)
  local now = IRL.Now()
  local changed = IRL.Streaks.Log(IRL.db.streaks[which], IRL.DayIndex(now), IRL.DayString(now), IRL.Config.maxStrikes)
  if changed then IRL.Recompute(which) end
  return changed
end

function IRL.StreakStatus(which)
  return IRL.Streaks.Evaluate(IRL.db.streaks[which], IRL.Today(), IRL.Config.maxStrikes)
end
