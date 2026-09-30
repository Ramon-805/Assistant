-- The Gymlocke rules engine (pure Lua, no WoW API). Turns saved tiers and
-- the character level into open gates and a rank for one rulebook (spec),
-- and judges any talent or spell: unlocked or not, with each requirement and
-- whether it's met.
--
-- Saved shape (see Core/DB.lua):
--   db.specs[rulebook].disciplines[key]
--       landmark: { tier, last, lastDay, lostTier, retryUntil, history }
--       measured: { baseline, value, last, lastDay, lostTier, retryUntil, history }
--   db.supports[key] = measured, shared by every spec
local _, IRL = ...

local R = {}
IRL.Rules = R

local function lower(s) return type(s) == "string" and s:lower() or nil end

--------------------------------------------------------------------------
-- Measured tiers: percent over (or under, for times) your baseline
--------------------------------------------------------------------------

-- Targets for tiers 1..4. Bronze matches the baseline; targets round up to
-- the next whole unit.
function R.Targets(def, baseline)
  local targets = {}
  for i, p in ipairs(def.percents or IRL.PercentTiers) do
    local x = def.lower and baseline * (1 - p) or baseline * (1 + p)
    targets[i] = math.ceil(x - 1e-9)
  end
  return targets
end

function R.MeasuredTier(def, entry)
  if not entry or not entry.baseline or not entry.value then return 0 end
  local tier = 0
  for i, target in ipairs(R.Targets(def, entry.baseline)) do
    if (def.lower and entry.value <= target) or (not def.lower and entry.value >= target) then tier = i end
  end
  return tier
end

function R.IsMeasured(def) return def.scale == "percent" or def.percents ~= nil end

-- The definition behind a discipline or supporting-test key.
function R.DefFor(rb, key) return rb.disciplines[key] or IRL.Supports[key] end

function R.TestKey(key, def) return def and def.test or ("d_" .. key) end

--------------------------------------------------------------------------
-- Tiers
--------------------------------------------------------------------------
function R.Tier(ctx, key)
  local def = ctx.rb.disciplines[key]
  if def then
    local entry = ctx.disc[key]
    if def.scale == "percent" then return R.MeasuredTier(def, entry) end
    return entry and entry.tier or 0
  end
  local sup = IRL.Supports[key]
  if sup then return R.MeasuredTier(sup, ctx.db.supports[key]) end
  return 0
end

-- Number of the six disciplines at `tier` or better.
function R.CountAtLeast(ctx, tier)
  local n = 0
  for _, key in ipairs(ctx.rb.disciplineOrder) do
    if R.Tier(ctx, key) >= tier then n = n + 1 end
  end
  return n
end

function R.Meets(ctx, need) return R.CountAtLeast(ctx, need[1]) >= need[2] end
function R.KeyMet(ctx, key) return R.Tier(ctx, key[1]) >= key[2] end

function R.TestDayDone(ctx)
  for _, key in ipairs(ctx.rb.disciplineOrder) do
    if not (ctx.disc[key] and ctx.disc[key].lastDay) then return false end
  end
  return true
end

--------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------
function R.TierName(tier) return tier == 0 and "None" or IRL.Tiers[tier] end

function R.NeedText(rb, need)
  local tier, count = need[1], need[2]
  if count >= #rb.disciplineOrder then return IRL.Tiers[tier] .. " in all six" end
  if count == 1 then return IRL.Tiers[tier] .. " in any one" end
  return IRL.Tiers[tier] .. " in " .. count
end

-- "+15% over your baseline", "5% faster than baseline", "match your baseline"
function R.PercentText(def, tier)
  local pct = math.floor((def.percents or IRL.PercentTiers)[tier] * 100 + 0.5)
  if pct == 0 then return "match your baseline" end
  return string.format(def.lower and "%d%% faster than baseline" or "+%d%% over your baseline", pct)
end

-- e.g. "Push Silver (35 push-ups)", "Brace Silver (+15% over your baseline: 1:09)"
function R.KeyText(ctx, key)
  local what, tier = key[1], key[2]
  local def = R.DefFor(ctx.rb, what)
  if not R.IsMeasured(def) then
    return def.label .. " " .. IRL.Tiers[tier] .. " (" .. def.tiers[tier] .. ")"
  end
  local detail = R.PercentText(def, tier)
  local entry = ctx.disc[what] or ctx.db.supports[what]
  if entry and entry.baseline and IRL.Units then
    detail = detail .. ": " .. IRL.Units.Format(R.TestKey(what, def), R.Targets(def, entry.baseline)[tier])
  end
  return def.label .. " " .. IRL.Tiers[tier] .. " (" .. detail .. ")"
end

function R.GateText(rb, g)
  return string.format("Gate %d (%s)", g, rb.gateDefs[g].requirement)
end

--------------------------------------------------------------------------
-- Gates and rank. Gates are sequential waves: each needs the one before.
--------------------------------------------------------------------------
function R.GatesOpen(ctx)
  local open = {}
  for g = 0, IRL.GateCount do
    local def = ctx.rb.gateDefs[g]
    local ok = g == 0 or open[g - 1]
    if def.testDay then ok = ok and R.TestDayDone(ctx) end
    if def.need then ok = ok and R.Meets(ctx, def.need) end
    if def.level then ok = ok and (ctx.level or 0) >= def.level end
    if def.key then ok = ok and R.KeyMet(ctx, def.key) end
    open[g] = ok and true or false
  end
  return open
end

function R.Rank(ctx)
  local rank = 1
  for i, def in ipairs(IRL.Ranks) do
    local ok = true
    if def.gate then ok = ok and ctx.open[def.gate] end
    if def.need then ok = ok and R.Meets(ctx, def.need) end
    if ok then rank = i end
  end
  return rank
end

function R.Context(db, level, rb)
  rb = rb or IRL.Rulebooks.windwalker
  local spec = db.specs and db.specs[rb.key]
  local ctx = { db = db, level = level, rb = rb, disc = spec and spec.disciplines or {} }
  ctx.open = R.GatesOpen(ctx)
  ctx.rank = R.Rank(ctx)
  return ctx
end

--------------------------------------------------------------------------
-- Judging talents and spells
--------------------------------------------------------------------------
local function Lookups(rb)
  if rb._keysLower then return end
  rb._keysLower, rb._cooldownsLower = {}, {}
  for name, k in pairs(rb.keys) do rb._keysLower[name:lower()] = k end
  for _, name in ipairs(rb.majorCooldowns) do rb._cooldownsLower[name:lower()] = true end
end

-- The pattern rule a name falls under, or nil.
local function MatchPattern(rb, name)
  local l = lower(name)
  if not l then return nil end
  for _, pk in ipairs(rb.patternKeys) do
    for _, extra in ipairs(pk.extra or {}) do
      if extra:lower() == l then return pk end
    end
    local excluded = false
    for _, e in ipairs(pk.except or {}) do if e == l then excluded = true end end
    if not excluded and l:find(pk.pattern, 1, true) then return pk end
  end
  return nil
end

-- Names that carry a rule even without talent-tree position (for casts,
-- tooltips and action bars).
function R.RuleNames(rb)
  local names = {}
  for name in pairs(rb.keys) do names[name] = true end
  for _, name in ipairs(rb.majorCooldowns) do names[name] = true end
  for _, pk in ipairs(rb.patternKeys) do
    for _, extra in ipairs(pk.extra or {}) do names[extra] = true end
  end
  return names
end

-- meta: { name, section (1-3), isCapstone, heroTree, isHeroFinal, isApex, rank }
-- Returns { name, unlocked, reqs = { {ok, text}, ... }, missing = {texts} }.
function R.Evaluate(ctx, meta)
  local rb, open = ctx.rb, ctx.open
  Lookups(rb)
  local reqs = {}
  local function add(ok, text) table.insert(reqs, { ok = ok and true or false, text = text }) end

  if meta.isApex then
    local rule = IRL.ApexRule
    add(open[rule.gate], R.GateText(rb, rule.gate))
    local rank = math.max(meta.rank or 1, 1)
    for _, r in ipairs(rule.ranks) do
      if r.minRank <= rank then
        add(R.Meets(ctx, r.need), string.format("%s (rank %d+): %s", r.label, r.minRank, R.NeedText(rb, r.need)))
      end
    end
  elseif meta.heroTree then
    local rule = IRL.HeroRule
    add(open[rule.gate], R.GateText(rb, rule.gate))
    if meta.isHeroFinal then
      add(R.Meets(ctx, rule.finalNeed), "Final hero node: " .. R.NeedText(rb, rule.finalNeed))
    end
  else
    local l = lower(meta.name)
    local keyed = l and rb._keysLower[l]
    local pat = MatchPattern(rb, meta.name)
    local gate
    if keyed then gate = keyed.gate
    elseif l and rb._cooldownsLower[l] then gate = 2
    elseif pat then gate = pat.gate
    else gate = IRL.SectionGate[meta.section or 1] or 0 end
    if meta.isCapstone then gate = math.max(gate, IRL.CapstoneRule.gate) end

    add(open[gate], R.GateText(rb, gate))
    if keyed then add(R.KeyMet(ctx, keyed.key), "Key: " .. R.KeyText(ctx, keyed.key)) end
    if pat then add(R.KeyMet(ctx, pat.key), "Key: " .. R.KeyText(ctx, pat.key)) end
    if meta.isCapstone then
      add(R.Meets(ctx, IRL.CapstoneRule.need), "Capstone: " .. R.NeedText(rb, IRL.CapstoneRule.need))
    end
  end

  local missing = {}
  for _, r in ipairs(reqs) do if not r.ok then table.insert(missing, r.text) end end
  return { name = meta.name, unlocked = #missing == 0, reqs = reqs, missing = missing }
end

function R.FlyingAllowed(ctx)
  return R.KeyMet(ctx, IRL.FlyingKey), "Key: " .. R.KeyText(ctx, IRL.FlyingKey)
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
-- What changed between two states, for toasts. Switching spec changes the
-- whole ruleset, so a diff across specs is empty.
--------------------------------------------------------------------------
function R.Diff(a, b)
  local gained, lost = {}, {}
  if not a or a.ctx.rb ~= b.ctx.rb then return gained, lost end
  for g = 0, IRL.GateCount do
    local name = string.format("Gate %d: %s", g, b.ctx.rb.gateDefs[g].name)
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
