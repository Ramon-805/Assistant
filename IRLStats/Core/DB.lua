-- SavedVariables and the actions that change them. Every change ends in
-- IRL.Recompute(), which rebuilds gates, rank and unlock state and fires
-- STATE_CHANGED with what was gained or lost.
--
-- IRLStatsDB (account-wide; it's the same body on every character):
--   disciplines[key] = { tier, last = "YYYY-MM-DD", lastDay, lostTier, retryUntil,
--                        history = { {tier, date, t} } }
--   supports[key]    = { baseline, value, last, lastDay, lostTier, retryUntil,
--                        history = { {value, date, t} } }
--   minimap = { angle, hide }, profile = { units }
--   legacyV1 = data from the pre-rulebook build, kept but unused
-- IRLStatsCharDB (per character):
--   flags      { {t, name, kind, detail, zone, combat} }  (never pruned)
--   talentSig  last flagged loadout signature
local _, IRL = ...

local DB_VERSION = 2

local function defaults()
  local disciplines, supports = {}, {}
  for _, key in ipairs(IRL.DisciplineOrder) do disciplines[key] = { tier = 0, history = {} } end
  for _, key in ipairs(IRL.SupportOrder) do supports[key] = { history = {} } end
  return {
    version = DB_VERSION,
    disciplines = disciplines,
    supports = supports,
    profile = { units = "imperial" },
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

-- v1 (categories, ladders, streaks) doesn't map onto the rulebook. Keep it
-- under legacyV1 so nothing is lost, and start fresh.
local function MigrateV1(db)
  if (db.version or 1) >= 2 or not db.categories then return end
  db.legacyV1 = {
    categories = db.categories, habit = db.habit, streaks = db.streaks, profile = db.profile,
  }
  db.categories, db.milestones, db.habit, db.streaks, db.setupDone = nil, nil, nil, nil, nil
end

function IRL.InitDB()
  IRLStatsDB = IRLStatsDB or {}
  MigrateV1(IRLStatsDB)
  fill(IRLStatsDB, defaults())
  IRLStatsDB.version = DB_VERSION
  IRLStatsCharDB = IRLStatsCharDB or {}
  IRLStatsCharDB.flags = IRLStatsCharDB.flags or {}
  IRL.db, IRL.char = IRLStatsDB, IRLStatsCharDB
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------
IRL.nodeMeta = {} -- lower-cased talent name -> tree meta, filled by Detect/Talents.lua

local function AddSpell(state, info, kind)
  info.kind = kind
  state.spells[info.name] = info
  state.byLower[info.name:lower()] = info
end

function IRL.BuildState(db, level, today)
  local R = IRL.Rules
  local ctx = R.Context(db, level)
  local state = { ctx = ctx, open = ctx.open, rank = ctx.rank, spells = {}, byLower = {}, today = today }

  -- Rule names judged without tree position (casts, tooltips, action bars).
  local names = {}
  for name in pairs(IRL.Keys) do names[name] = true end
  for _, name in ipairs(IRL.MajorCooldowns) do names[name] = true end
  for _, name in ipairs(IRL.FortifyingUpgrades.extra) do names[name] = true end
  for name in pairs(names) do AddSpell(state, R.Evaluate(ctx, { name = name }), "rule") end

  -- Everything in the talent tree, judged by its position (overrides the above).
  for _, meta in pairs(IRL.nodeMeta) do
    AddSpell(state, R.Evaluate(ctx, meta), "talent")
  end

  state.flying = R.FlyingAllowed(ctx)
  return state
end

function IRL.PlayerLevelSafe()
  local level = UnitLevel and UnitLevel("player")
  if level == nil or IRL.IsSecret(level) then return 0 end
  return level
end

function IRL.Recompute(reason)
  local old = IRL.state
  local today = IRL.Today()
  IRL.state = IRL.BuildState(IRL.db, IRL.PlayerLevelSafe(), today)
  IRL.stateDay = today
  local gained, lost = IRL.Rules.Diff(old, IRL.state)
  IRL.Fire("STATE_CHANGED", gained, lost, reason)
  return gained, lost
end

-- Retest and retry countdowns are day-based; refresh when the day rolls over.
function IRL.CheckDayRollover()
  if IRL.state and IRL.stateDay ~= IRL.Today() then IRL.Recompute("day") end
end

function IRL.FindGate(name)
  if not IRL.state or type(name) ~= "string" then return nil end
  return IRL.state.byLower[name:lower()]
end

--------------------------------------------------------------------------
-- Logging tests
--------------------------------------------------------------------------

-- Common bookkeeping: date, and the drop/retry rule. A result below the
-- previous tier takes effect at once and opens a one-retry window; getting
-- back to the lost tier clears it.
local function Stamp(entry, oldTier, newTier, now)
  local today = IRL.DayIndex(now)
  if entry.lastDay and newTier < oldTier then
    entry.lostTier = math.max(oldTier, entry.lostTier or 0)
    entry.retryUntil = today + IRL.RetryDays
  elseif entry.lostTier and newTier >= entry.lostTier then
    entry.lostTier, entry.retryUntil = nil, nil
  end
  entry.last, entry.lastDay = IRL.DayString(now), today
end

-- tier: 0 (not yet Bronze) .. 4 (Legendary)
function IRL.LogDiscipline(key, tier)
  local entry = IRL.db.disciplines[key]
  local now = IRL.Now()
  local old = entry.tier or 0
  table.insert(entry.history, { tier = tier, date = IRL.DayString(now), t = now })
  Stamp(entry, old, tier, now)
  entry.tier = tier
  return IRL.Recompute("test")
end

-- value in seconds (mile) or ms (reaction). The first result is the baseline.
function IRL.LogSupport(key, value)
  local entry = IRL.db.supports[key]
  local now = IRL.Now()
  local old = IRL.Rules.SupportTier(entry)
  table.insert(entry.history, { value = value, date = IRL.DayString(now), t = now })
  if not entry.baseline then entry.baseline = value end
  entry.value = value
  Stamp(entry, old, IRL.Rules.SupportTier(entry), now)
  return IRL.Recompute("test")
end

-- Start the % scale over from a new baseline (e.g. a new route).
function IRL.SetSupportBaseline(key, value)
  local entry = IRL.db.supports[key]
  entry.baseline, entry.lostTier, entry.retryUntil = value, nil, nil
  return IRL.Recompute("baseline")
end
