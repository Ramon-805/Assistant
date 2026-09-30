-- Cast detection. Midnight removed the combat log for addons; the player's
-- own UNIT_SPELLCAST_SUCCEEDED still carries a readable spellID, even in
-- combat. Other unit tokens carry secret spellIDs and are never registered.
local _, IRL = ...

-- Current specialization ID, or nil (e.g. below level 10).
function IRL.CurrentSpecID()
  local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
  local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
  local index = getSpec and getSpec()
  if not index or IRL.IsSecret(index) or not getInfo then return nil end
  local specID = getInfo(index)
  if not specID or IRL.IsSecret(specID) then return nil end
  return specID
end

-- Is this character subject to a rulebook? Monks whose spec has one
-- (Windwalker, Brewmaster); low-level monks with no spec use Windwalker's.
function IRL.IsEnforced()
  local _, class = UnitClass("player")
  return class == "MONK" and IRL.SpecHasRulebook()
end

-- Spell name for an ID, or nil if unreadable.
function IRL.SpellName(spellID)
  if spellID == nil or IRL.IsSecret(spellID) or type(spellID) ~= "number" then return nil end
  local name = C_Spell.GetSpellName(spellID)
  if name == nil or IRL.IsSecret(name) then return nil end
  return name
end

local frame = CreateFrame("Frame")
frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
frame:SetScript("OnEvent", function(_, _, unit, _, spellID)
  if unit ~= "player" or not IRL.state or not IRL.enforced then return end
  local name = IRL.SpellName(spellID)
  if not name then return end
  local gate = IRL.FindGate(name)
  if not gate or gate.unlocked then return end
  if IRL.AddFlag(gate.name, "cast") then
    IRL.ShowWarning(IRL.LockedMessage(gate))
  end
end)
