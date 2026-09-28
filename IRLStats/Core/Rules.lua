-- The Gymlocke rules engine (pure Lua, no WoW API). Turns saved tiers and
-- the character level into open gates and a rank, and judges any talent or
-- spell: unlocked or not, with each requirement and whether it's met.
--
-- Saved shape (see Core/DB.lua):
--   db.disciplines[key] = { tier, last, lastDay, lostTier, retryUntil, history }
--   db.supports[key]    = { baseline, value, last, lastDay, lostTier, retryUntil, history }
local _, IRL = ...

local R = {}
IRL.Rules = R

local function lower(s) return type(s) == "string" and s:lower() or nil end

--------------------------------------------------------------------------
-- Tiers
--------------------------------------------------------------------------

-- Supporting-test targets for tiers 1..4: Bronze matches the baseline, each
-- tier after is a percentage faster, rounded up to the next whole unit.
function R.SupportTargets(baseline)
  local targets = {}
  for i, p in ipairs(IRL.SupportTierPercent) do
    targets[i] = math.ceil(baseline * (1 - p) - 1e-9)
  end
  return targets
end

function R.SupportTier(s)
  if not s or not s.baseline or not s.value then return 0 end
  local tier = 0
  for i, target in ipairs(R.SupportTargets(s.baseline)) do
    if s.value <= target then tier = i end
  end
  return tier
end

function R.Tier(db, key)
  if IRL.Disciplines[key] then
    local d = db.disciplines[key]
    return d and d.tier or 0
  end
  return R.SupportTier(db.supports[key])
end

-- Number of the six disciplines at `tier` or better.
function R.CountAtLeast(db, tier)
  local n = 0
  for _, key in ipairs(IRL.DisciplineOrder) do
    if R.Tier(db, key) >= tier then n = n + 1 end
  end
  return n
end

function R.Meets(db, need) return R.CountAtLeast(db, need[1]) >= need[2] end
function R.KeyMet(db, key) return R.Tier(db, key[1]) >= key[2] end

function R.TestDayDone(db)
  for _, key in ipairs(IRL.DisciplineOrder) do
    if not (db.disciplines[key] and db.disciplines[key].lastDay) then return false end
  end
  return true
end

--------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------
function R.TierName(tier) return tier == 0 and "None" or IRL.Tiers[tier] end

function R.NeedText(need)
  local tier, count = need[1], need[2]
  if count >= #IRL.DisciplineOrder then return IRL.Tiers[tier] .. " in all six" end
  if count == 1 then return IRL.Tiers[tier] .. " in any one" end
  return IRL.Tiers[tier] .. " in " .. count
end

-- e.g. "Push Silver (35 push-ups)", "Mile Silver (5% faster than baseline)"
function R.KeyText(key)
  local what, tier = key[1], key[2]
  local d = IRL.Disciplines[what]
  if d then return d.label .. " " .. IRL.Tiers[tier] .. " (" .. d.tiers[tier] .. ")" end
  local pct = IRL.SupportTierPercent[tier] * 100
  local detail = pct == 0 and "match your baseline" or string.format("%d%% faster than baseline", pct)
  return IRL.Supports[what].label .. " " .. IRL.Tiers[tier] .. " (" .. detail .. ")"
end

function R.GateText(g)
  return string.format("Gate %d (%s)", g, IRL.GateDefs[g].requirement)
end

--------------------------------------------------------------------------
-- Gates and rank. Gates are sequential waves: each needs the one before.
--------------------------------------------------------------------------
function R.GatesOpen(db, level)
  local open = {}
  for g = 0, IRL.GateCount do
    local def = IRL.GateDefs[g]
    local ok = g == 0 or open[g - 1]
    if def.testDay then ok = ok and R.TestDayDone(db) end
    if def.need then ok = ok and R.Meets(db, def.need) end
    if def.level then ok = ok and (level or 0) >= def.level end
    if def.key then ok = ok and R.KeyMet(db, def.key) end
    open[g] = ok and true or false
  end
  return open
end

function R.Rank(db, open)
  local rank = 1
  for i, def in ipairs(IRL.Ranks) do
    local ok = true
    if def.gate then ok = ok and open[def.gate] end
    if def.need then ok = ok and R.Meets(db, def.need) end
    if ok then rank = i end
  end
  return rank
end

function R.Context(db, level)
  local open = R.GatesOpen(db, level)
  return { db = db, level = level, open = open, rank = R.Rank(db, open) }
end

--------------------------------------------------------------------------
-- Judging talents and spells
--------------------------------------------------------------------------
local keysLower, cooldownsLower
local function Lookups()
  if keysLower then return end
  keysLower, cooldownsLower = {}, {}
  for name, k in pairs(IRL.Keys) do keysLower[name:lower()] = k end
  for _, name in ipairs(IRL.MajorCooldowns) do cooldownsLower[name:lower()] = true end
end

local function IsFortifyingUpgrade(name)
  local f = IRL.FortifyingUpgrades
  local l = lower(name)
  if not l then return false end
  for _, extra in ipairs(f.extra) do if extra:lower() == l then return true end end
  return l ~= f.base:lower() and l:find(f.pattern, 1, true) ~= nil
end

-- Is this name governed by a rule even without talent-tree position?
function R.IsRuleName(name)
  Lookups()
  local l = lower(name)
  return l ~= nil and (keysLower[l] ~= nil or cooldownsLower[l] or IsFortifyingUpgrade(name))
end

-- meta: { name, section (1-3), isCapstone, heroTree, isHeroFinal, isApex, rank }
-- Returns { name, unlocked, reqs = { {ok, text}, ... }, missing = {texts} }.
function R.Evaluate(ctx, meta)
  Lookups()
  local db, open = ctx.db, ctx.open
  local reqs = {}
  local function add(ok, text) table.insert(reqs, { ok = ok and true or false, text = text }) end

  if meta.isApex then
    local rule = IRL.ApexRule
    add(open[rule.gate], R.GateText(rule.gate))
    local rank = math.max(meta.rank or 1, 1)
    for _, r in ipairs(rule.ranks) do
      if r.minRank <= rank then
        add(R.Meets(db, r.need), string.format("%s (rank %d+): %s", r.label, r.minRank, R.NeedText(r.need)))
      end
    end
  elseif meta.heroTree then
    local rule = IRL.HeroRule
    add(open[rule.gate], R.GateText(rule.gate))
    if meta.isHeroFinal then add(R.Meets(db, rule.finalNeed), "Final hero node: " .. R.NeedText(rule.finalNeed)) end
  else
    local l = lower(meta.name)
    local keyed = l and keysLower[l]
    local fort = IsFortifyingUpgrade(meta.name) and IRL.FortifyingUpgrades
    local gate
    if keyed then gate = keyed.gate
    elseif l and cooldownsLower[l] then gate = 2
    elseif fort then gate = fort.gate
    else gate = IRL.SectionGate[meta.section or 1] or 0 end
    if meta.isCapstone then gate = math.max(gate, IRL.CapstoneRule.gate) end

    add(open[gate], R.GateText(gate))
    if keyed then add(R.KeyMet(db, keyed.key), "Key: " .. R.KeyText(keyed.key)) end
    if fort then add(R.KeyMet(db, fort.key), "Key: " .. R.KeyText(fort.key)) end
    if meta.isCapstone then
      add(R.Meets(db, IRL.CapstoneRule.need), "Capstone: " .. R.NeedText(IRL.CapstoneRule.need))
    end
  end

  local missing = {}
  for _, r in ipairs(reqs) do if not r.ok then table.insert(missing, r.text) end end
  return { name = meta.name, unlocked = #missing == 0, reqs = reqs, missing = missing }
end

function R.FlyingAllowed(ctx)
  return R.KeyMet(ctx.db, IRL.FlyingKey), "Key: " .. R.KeyText(IRL.FlyingKey)
end

--------------------------------------------------------------------------
-- Retests
--------------------------------------------------------------------------
function R.RetestDue(entry, today)
  if not entry or not entry.lastDay then return nil end
  return entry.lastDay + IRL.RetestDays - today -- days left (negative = overdue)
end

-- Days left in the one-retry window, or nil.
function R.RetryLeft(entry, today)
  if not entry or not entry.retryUntil then return nil end
  local left = entry.retryUntil - today
  if left < 0 then return nil end
  return left
end

--------------------------------------------------------------------------
-- What changed between two states, for toasts.
--------------------------------------------------------------------------
function R.Diff(a, b)
  local gained, lost = {}, {}
  if not a then return gained, lost end
  for g = 0, IRL.GateCount do
    local name = string.format("Gate %d: %s", g, IRL.GateDefs[g].name)
    if b.open[g] and not a.open[g] then table.insert(gained, name) end
    if a.open[g] and not b.open[g] then table.insert(lost, name) end
  end
  if b.rank > a.rank then table.insert(gained, "Rank: " .. IRL.Ranks[b.rank].name) end
  if b.rank < a.rank then table.insert(lost, "Rank: " .. IRL.Ranks[b.rank].name) end
  for name, info in pairs(b.spells) do
    local old = a.spells[name]
    if old and info.unlocked ~= old.unlocked then
      table.insert(info.unlocked and gained or lost, name)
    end
  end
  if b.flying ~= a.flying then table.insert(b.flying and gained or lost, "Flying") end
  return gained, lost
end
