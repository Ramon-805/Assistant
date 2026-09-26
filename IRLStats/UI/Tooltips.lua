-- Requirement lines on spell and action tooltips (via TooltipDataProcessor)
-- and, through IRL.AppendGateTooltip, on talent-frame buttons.
local _, IRL = ...
local UI = IRL.UI

local done = setmetatable({}, { __mode = "k" }) -- tooltip -> already appended

local function Exercises(cat)
  local list = IRL.Categories[cat].exercises
  local out = {}
  for i = 1, math.min(IRL.Config.exercisesShown, #list) do out[i] = list[i] end
  return table.concat(out, ", ")
end

-- gate: a state.spells entry, or a state.heroTrees entry with .name set.
function IRL.AppendGateTooltip(tooltip, gate, activeRank)
  if not gate or done[tooltip] then return end
  done[tooltip] = true
  local R, G = UI.RED, UI.GREEN
  local apex = IRL.state.apex[gate.name]

  if apex then
    local c = IRL.db.categories[apex.category]
    local rankLocked = activeRank and activeRank > apex.unlockedRanks
    local col = (apex.unlockedRanks == 0 or rankLocked) and R or G
    tooltip:AddLine(string.format("IRL: %d/3 ranks unlocked", apex.unlockedRanks), col[1], col[2], col[3])
    if apex.values then
      for r = apex.unlockedRanks + 1, 3 do
        tooltip:AddLine("Rank " .. r .. " unlocks at " .. IRL.Units.Phrase(c.test, apex.values[r]), R[1], R[2], R[3], true)
      end
    elseif not gate.unlocked then
      tooltip:AddLine(gate.requirement, R[1], R[2], R[3], true)
    end
    if apex.unlockedRanks < 3 then
      tooltip:AddLine("Train: " .. Exercises(apex.category), 0.8, 0.8, 0.8, true)
    end
    return
  end

  if gate.unlocked then
    tooltip:AddLine("IRL: Unlocked", G[1], G[2], G[3])
    return
  end
  tooltip:AddLine("IRL: " .. gate.requirement, R[1], R[2], R[3], true)
  if gate.category then
    local c = IRL.db.categories[gate.category]
    local cs = IRL.state.categories[gate.category]
    if c.test and cs.nextValue then
      tooltip:AddLine(string.format("Next milestone: %s (PR %s)", IRL.Units.Phrase(c.test, cs.nextValue),
        IRL.Units.Format(c.test, c.pr)), 1, 0.82, 0, true)
    end
    tooltip:AddLine("Train: " .. Exercises(gate.category), 0.8, 0.8, 0.8, true)
  end
end

local function OnSpellTooltip(tooltip, data)
  if not IRL.state or not IRL.enforced or not data then return end
  local id = data.id
  if IRL.IsSecret(id) then return end
  local name = IRL.SpellName(id)
  local gate = name and IRL.FindGate(name)
  if gate then IRL.AppendGateTooltip(tooltip, gate) end
end

if TooltipDataProcessor and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, OnSpellTooltip)
end
-- Macros on action bars don't produce a spell tooltip; resolve the slot.
hooksecurefunc(GameTooltip, "SetAction", function(tooltip, slot)
  if not IRL.state or not IRL.enforced or done[tooltip] then return end
  local gate = IRL.GateForSpell(IRL.ActionSpellID(slot))
  if gate then
    IRL.AppendGateTooltip(tooltip, gate)
    tooltip:Show()
  end
end)

GameTooltip:HookScript("OnTooltipCleared", function(self) done[self] = nil end)
if ItemRefTooltip then
  ItemRefTooltip:HookScript("OnTooltipCleared", function(self) done[self] = nil end)
end
