-- Unlock state (pure). Compute(db, today) turns the saved real-life data
-- into the state every other module reads:
--
--   state.spells[name]     = { unlocked, category, kind, requirement, rank }
--   state.heroTrees[name]  = { unlocked, kind, requirement }
--   state.apex[name]       = { category, unlockedRanks, rungs = {r1, r2, r3} }
--   state.categories[cat]  = { rungs, achieved, nextValue, rewards[rung] = {names} }
--
-- kind is "milestone", "apex", "habit", "pt", "training", "balance" or "unset".
local _, IRL = ...

local G = {}
IRL.GateLogic = G

local function lowerKey(name) return name:lower() end

local function categoryReady(c)
  return c and c.test and IRL.Tests[c.test] and c.baseline ~= nil and c.goal ~= nil
end

function G.Compute(db, today)
  local cfg = IRL.Config
  local Units, M = IRL.Units, IRL.Milestones
  local state = { spells = {}, heroTrees = {}, apex = {}, categories = {}, byLower = {} }

  local function addSpell(name, info)
    info.name = name
    state.spells[name] = info
    state.byLower[lowerKey(name)] = info
  end

  for _, cat in ipairs(IRL.CategoryOrder) do
    local c = db.categories[cat]
    local gate = IRL.Gates[cat]
    local catLabel = IRL.Categories[cat].label
    local cs = { rungs = {}, achieved = 0, rewards = {} }
    state.categories[cat] = cs

    if not categoryReady(c) then
      local req = "Set a test, PR and goal for " .. catLabel .. " (/irl)"
      for _, name in ipairs(gate.abilities) do
        addSpell(name, { unlocked = false, category = cat, kind = "unset", requirement = req })
      end
      if gate.apex then
        state.apex[gate.apex.name] = { category = cat, unlockedRanks = 0, rungs = {} }
        addSpell(gate.apex.name, { unlocked = false, category = cat, kind = "unset", requirement = req })
        for _, granted in pairs(gate.apex.grants or {}) do
          addSpell(granted, { unlocked = false, category = cat, kind = "unset", requirement = req })
        end
      end
    else
      local test = IRL.Tests[c.test]
      local absolute = test.unit == "level"
      local counted = test.unit == "reps" or test.unit == "hold"
      local step = absolute and 1 or (counted and cfg.countStep) or cfg.steps[cat] or 0.05
      local rungs = M.Build(c.test, c.baseline, c.goal, step, absolute, cfg.maxRungs)
      local achieved = M.Achieved(c.test, rungs, c.pr)
      cs.rungs, cs.achieved = rungs, achieved
      cs.nextValue = rungs[achieved + 1]

      local gateRungs, apexRungs = M.Place(#rungs, #gate.abilities, gate.apex ~= nil, cfg.reservedTopRungs)
      local function reward(rung, text)
        cs.rewards[rung] = cs.rewards[rung] or {}
        table.insert(cs.rewards[rung], text)
      end

      for i, name in ipairs(gate.abilities) do
        local rung = gateRungs[i]
        addSpell(name, {
          unlocked = achieved >= rung, category = cat, kind = "milestone", rung = rung,
          requirement = "Unlocks at " .. Units.Phrase(c.test, rungs[rung]),
        })
        reward(rung, name)
      end

      if gate.apex then
        local unlockedRanks = 0
        for r = 1, 3 do
          if achieved >= apexRungs[r] then unlockedRanks = r end
          reward(apexRungs[r], gate.apex.name .. " rank " .. r)
        end
        state.apex[gate.apex.name] = { category = cat, unlockedRanks = unlockedRanks, rungs = apexRungs,
                                       test = c.test, values = { rungs[apexRungs[1]], rungs[apexRungs[2]], rungs[apexRungs[3]] } }
        addSpell(gate.apex.name, {
          unlocked = unlockedRanks >= 1, category = cat, kind = "apex", rank = 1,
          requirement = "Rank 1 unlocks at " .. Units.Phrase(c.test, rungs[apexRungs[1]]),
        })
        for r, granted in pairs(gate.apex.grants or {}) do
          addSpell(granted, {
            unlocked = unlockedRanks >= r, category = cat, kind = "apex", rank = r,
            requirement = gate.apex.name .. " rank " .. r .. " unlocks at " .. Units.Phrase(c.test, rungs[apexRungs[r]]),
          })
        end
      end
    end
  end

  -- Daily habit: unlocked for the calendar day of the check-in.
  local habitOn = db.habit and db.habit.lastDay == today
  for _, name in ipairs(IRL.SpecialGates.habit.abilities) do
    addSpell(name, { unlocked = habitOn, kind = "habit",
                     requirement = "Unlocks for the day when you tick \"Took my supplements\" (/irl)" })
  end

  -- PT streak gates self-heals.
  local ptAlive = IRL.Streaks.Evaluate(db.streaks.pt, today, cfg.maxStrikes)
  for _, name in ipairs(IRL.SpecialGates.pt.abilities) do
    addSpell(name, { unlocked = ptAlive, kind = "pt",
                     requirement = "Unlocked while your mobility/PT streak is alive; log a session to revive it" })
  end

  -- Training streak gates the Shado-Pan hero tree.
  local trainAlive = IRL.Streaks.Evaluate(db.streaks.training, today, cfg.maxStrikes)
  state.heroTrees[IRL.SpecialGates.training.heroTree] = {
    name = IRL.SpecialGates.training.heroTree, unlocked = trainAlive, kind = "training",
    requirement = "Unlocked while your training streak is alive; tick \"Trained today\" to revive it",
  }

  -- Four-category balance gates Conduit of the Celestials.
  local balanced, missing = true, {}
  for _, cat in ipairs(IRL.SpecialGates.balance.requires) do
    if state.categories[cat].achieved < 1 then
      balanced = false
      table.insert(missing, IRL.Categories[cat].label:lower())
    end
  end
  state.heroTrees[IRL.SpecialGates.balance.heroTree] = {
    name = IRL.SpecialGates.balance.heroTree, unlocked = balanced, kind = "balance",
    requirement = "Unlocks once speed, grip and pull, mobility and explosive power each reach a milestone"
      .. (#missing > 0 and (" (still needed: " .. table.concat(missing, ", ") .. ")") or ""),
  }

  return state
end

-- Look up a gate by spell or talent name (case-insensitive).
function G.Find(state, name)
  if not state or type(name) ~= "string" then return nil end
  return state.byLower[lowerKey(name)]
end

-- Names that are unlocked in b but were locked in a, and vice versa.
function G.Diff(a, b)
  local gained, lost = {}, {}
  if not a then return gained, lost end
  local function walk(tableA, tableB)
    for name, info in pairs(tableB) do
      local old = tableA[name]
      if old then
        if info.unlocked and not old.unlocked then table.insert(gained, name) end
        if old.unlocked and not info.unlocked then table.insert(lost, name) end
      end
    end
  end
  walk(a.spells, b.spells)
  walk(a.heroTrees, b.heroTrees)
  for name, info in pairs(b.apex) do
    local old = a.apex[name]
    if old and info.unlockedRanks > old.unlockedRanks then
      for r = old.unlockedRanks + 1, info.unlockedRanks do
        if r > 1 then table.insert(gained, name .. " rank " .. r) end
      end
    end
  end
  table.sort(gained)
  table.sort(lost)
  return gained, lost
end
