-- SavedVariables and the actions that change them. Every change ends in
-- IRL.Recompute(), which rebuilds gates, rank and unlock state for the
-- active rulebook and fires STATE_CHANGED with what was gained or lost.
--
-- IRLStatsDB (account-wide; it's the same body on every character):
--   specs[rulebook].disciplines[key]   one ladder per spec (Windwalker, Brewmaster)
--       landmark: { tier, last = "YYYY-MM-DD", lastDay, lostTier, retryUntil,
--                   history = { {tier, date, t} } }
--       measured: { baseline, value, last, lastDay, lostTier, retryUntil,
--                   history = { {value, date, t} } }
--   supports[key]   mile and reaction, measured, shared by every spec
--   minimap = { angle, hide }, profile = { units }
--   legacyV1 = data from the pre-rulebook build, kept but unused
-- IRLStatsCharDB (per character):
--   flags      { {t, name, kind, detail, zone, combat} }  (never pruned)
--   talentSig  last flagged loadout signature
local _, IRL = ...

local DB_VERSION = 3

local function defaults()
  local specs, supports = {}, {}
  for _, rbKey in ipairs(IRL.RulebookOrder) do
    local rb = IRL.Rulebooks[rbKey]
    local disciplines = {}
    for _, key in ipairs(rb.disciplineOrder) do
      disciplines[key] = rb.disciplines[key].scale == "percent" and { history = {} } or { tier = 0, history = {} }
    end
    specs[rbKey] = { disciplines = disciplines }
  end
  for _, key in ipairs(IRL.SupportOrder) do supports[key] = { history = {} } end
  return {
    version = DB_VERSION,
    specs = specs,
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

-- v2 had one set of disciplines: Windwalker's. Move them under specs.
local function MigrateV2(db)
  if (db.version or 1) >= 3 or not db.disciplines then return end
  db.specs = db.specs or {}
  db.specs.windwalker = db.specs.windwalker or {}
  db.specs.windwalker.disciplines = db.disciplines
  db.disciplines = nil
end

function IRL.InitDB()
  IRLStatsDB = IRLStatsDB or {}
  MigrateV1(IRLStatsDB)
  MigrateV2(IRLStatsDB)
  fill(IRLStatsDB, defaults())
  IRLStatsDB.version = DB_VERSION
  IRLStatsCharDB = IRLStatsCharDB or {}
  IRLStatsCharDB.flags = IRLStatsCharDB.flags or {}
  IRL.db, IRL.char = IRLStatsDB, IRLStatsCharDB
end

--------------------------------------------------------------------------
-- Rulebooks: which one is active (the current spec's), which one the window
-- is showing.
--------------------------------------------------------------------------
-- No spec yet (below level 10) or a spec without a rulebook: Windwalker's.
function IRL.ActiveRulebook()
  local specID = IRL.CurrentSpecID and IRL.CurrentSpecID()
  local key = specID and IRL.SpecRulebook[specID]
  return IRL.Rulebooks[key or "windwalker"]
end

-- Is the current spec enforced? Everything except a real spec without a
-- rulebook (IRL.UnruledSpecs). Below level 10 WoW reports a starter spec
-- with its own ID rather than none; that plays under Windwalker's rules.
function IRL.SpecHasRulebook()
  local specID = IRL.CurrentSpecID and IRL.CurrentSpecID()
  return not (specID and IRL.UnruledSpecs[specID])
end

function IRL.ViewRulebook() return IRL.viewRb or IRL.rb or IRL.Rulebooks.windwalker end

function IRL.SetViewRulebook(rb)
  IRL.viewRb = rb
  IRL.Fire("VIEW_CHANGED", rb)
end

-- Context for the rulebook the window is showing (may not be the active one).
function IRL.ViewContext()
  return IRL.Rules.Context(IRL.db, IRL.PlayerLevelSafe(), IRL.ViewRulebook())
end

local function Store(rb) return IRL.db.specs[(rb or IRL.rb).key].disciplines end
IRL.DisciplineStore = Store

--------------------------------------------------------------------------
-- State (for the active rulebook)
--------------------------------------------------------------------------
IRL.nodeMeta = {} -- lower-cased talent name -> tree meta, filled by Detect/Talents.lua

local function AddSpell(state, info, kind)
  info.kind = kind
  state.spells[info.name] = info
  state.byLower[info.name:lower()] = info
end

function IRL.BuildState(db, level, today, rb)
  local R = IRL.Rules
  local ctx = R.Context(db, level, rb)
  local state = { ctx = ctx, open = ctx.open, rank = ctx.rank, spells = {}, byLower = {}, today = today }

  -- Rule names judged without tree position (casts, tooltips, action bars).
  for name in pairs(R.RuleNames(ctx.rb)) do
    AddSpell(state, R.Evaluate(ctx, { name = name }), "rule")
  end

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
  IRL.rb = IRL.ActiveRulebook()
  IRL.state = IRL.BuildState(IRL.db, IRL.PlayerLevelSafe(), today, IRL.rb)
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

-- Landmark discipline. tier: 0 (not yet Bronze) .. 4 (Legendary)
function IRL.LogDiscipline(key, tier, rb)
  local entry = Store(rb)[key]
  local now = IRL.Now()
  local old = entry.tier or 0
  table.insert(entry.history, { tier = tier, date = IRL.DayString(now), t = now })
  Stamp(entry, old, tier, now)
  entry.tier = tier
  return IRL.Recompute("test")
end

-- Measured result (reps, seconds held, mile seconds, reaction ms). The first
-- result is the baseline and stays fixed: tiers are measured from it.
local function LogMeasured(def, entry, value)
  local now = IRL.Now()
  local old = IRL.Rules.MeasuredTier(def, entry)
  table.insert(entry.history, { value = value, date = IRL.DayString(now), t = now })
  if not entry.baseline then entry.baseline = value end
  entry.value = value
  Stamp(entry, old, IRL.Rules.MeasuredTier(def, entry), now)
  return IRL.Recompute("test")
end

function IRL.LogMeasured(key, value, rb)
  rb = rb or IRL.rb
  return LogMeasured(rb.disciplines[key], Store(rb)[key], value)
end

function IRL.LogSupport(key, value)
  return LogMeasured(IRL.Supports[key], IRL.db.supports[key], value)
end

-- Start a supporting test's % scale over from a new baseline (e.g. a new
-- mile route). Disciplines never re-baseline: that would let a sandbagged
-- Test Day make every tier easy.
function IRL.SetSupportBaseline(key, value)
  local entry = IRL.db.supports[key]
  entry.baseline, entry.lostTier, entry.retryUntil = value, nil, nil
  return IRL.Recompute("baseline")
end
