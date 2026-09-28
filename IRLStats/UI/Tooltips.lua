-- Requirement lines on spell and action tooltips (via TooltipDataProcessor)
-- and, through IRL.AppendGateTooltip, on talent-frame buttons. Each rule is
-- listed green when met, red when not.
local _, IRL = ...
local UI = IRL.UI

local done = setmetatable({}, { __mode = "k" }) -- tooltip -> already appended

-- result: an evaluation from Core/Rules.lua ({ unlocked, reqs = { {ok, text} } }).
function IRL.AppendGateTooltip(tooltip, result)
  if not result or done[tooltip] then return end
  done[tooltip] = true
  local R, G = UI.RED, UI.GREEN
  if result.unlocked then
    tooltip:AddLine("Gymlocke: Unlocked", G[1], G[2], G[3])
    return
  end
  tooltip:AddLine("Gymlocke: Locked", R[1], R[2], R[3])
  for _, req in ipairs(result.reqs) do
    local c = req.ok and G or R
    tooltip:AddLine((req.ok and "  done: " or "  needs: ") .. req.text, c[1], c[2], c[3], true)
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
