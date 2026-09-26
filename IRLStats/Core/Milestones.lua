-- Milestone ladders and gate placement (pure functions).
--
-- A ladder runs from the category's baseline (the PR when its goal was set)
-- to the goal. It is anchored at the baseline, not the latest PR, so logging
-- a PR moves you up the ladder instead of rebuilding it underneath you.
local _, IRL = ...

local M = {}
IRL.Milestones = M

-- Build the ordered rung values from baseline to goal.
--   step      fraction of baseline per rung (0.05), or levels per rung when absolute
--   absolute  true for skill ladders
-- The last rung always equals the goal.
function M.Build(testKey, baseline, goal, step, absolute, maxRungs)
  if baseline == nil or goal == nil then return {} end
  local Units = IRL.Units
  local unit = IRL.Tests[testKey].unit
  local lower = IRL.IsLowerBetter(testKey)
  local dir = lower and -1 or 1
  local prec = Units.precision[unit] or 0.01
  maxRungs = maxRungs or 30

  -- Goal already reached (or behind the baseline): a single rung at the goal.
  if Units.AtLeast(testKey, baseline, goal) then return { goal } end

  local delta = absolute and step or baseline * step
  if delta < prec then delta = prec end
  -- Too many rungs? Widen the step so the ladder stays a sensible length.
  local span = math.abs(goal - baseline)
  if span / delta > maxRungs then delta = span / maxRungs end

  local rungs = {}
  local prev = baseline
  local i = 1
  while true do
    local v = Units.Round(unit, baseline + dir * delta * i)
    -- Rounding must never produce a rung that isn't an improvement.
    if not (dir * (v - prev) > prec / 2) then v = Units.Round(unit, prev + dir * prec) end
    if Units.AtLeast(testKey, v, goal) or #rungs + 1 >= maxRungs then
      rungs[#rungs + 1] = goal
      break
    end
    rungs[#rungs + 1] = v
    prev = v
    i = i + 1
  end
  return rungs
end

-- Number of rungs the value has reached.
function M.Achieved(testKey, rungs, value)
  if value == nil then return 0 end
  local n = 0
  for i = 1, #rungs do
    if IRL.Units.AtLeast(testKey, value, rungs[i]) then n = i else break end
  end
  return n
end

-- Place k gates and (optionally) three apex ranks on an n-rung ladder.
-- Gates spread evenly over the rungs below the reserved top rungs, first
-- gate on rung 1, last gate on the highest available rung. Apex rank r sits
-- on rung n - 3 + r. Short ladders collapse onto the rungs they have.
function M.Place(n, k, hasApex, reserved)
  reserved = reserved or 3
  local gates, apex = {}, {}
  if n < 1 then return gates, apex end
  local avail = math.max(1, n - reserved)
  for i = 1, k do
    if k == 1 then
      gates[i] = 1
    else
      gates[i] = 1 + math.floor((i - 1) * (avail - 1) / (k - 1) + 0.5)
    end
  end
  if hasApex then
    for r = 1, 3 do apex[r] = math.max(1, n - 3 + r) end
  end
  return gates, apex
end
