-- Red tint over action buttons holding locked spells. The tint is a plain
-- (non-secure) texture; it is only created or changed out of combat, and any
-- refresh requested in combat waits for PLAYER_REGEN_ENABLED.
--
-- Covers Blizzard's default action bars. Bar addons that build their own
-- buttons (Bartender, ElvUI, Dominos) aren't tinted in build 1; casts are
-- still flagged there.
local _, IRL = ...

local BARS = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
  "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local tints = setmetatable({}, { __mode = "k" }) -- button -> texture
local pending = false

local function ActionSlot(button)
  if button.GetPagedID then
    local ok, id = pcall(button.GetPagedID, button)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  if type(button.action) == "number" and button.action > 0 then return button.action end
  local a = button.GetAttribute and button:GetAttribute("action")
  if type(a) == "number" and a > 0 then return a end
end

-- The spell a slot will actually cast (its override if it has one), or nil.
function IRL.ActionSpellID(slot)
  if not slot or not HasAction(slot) then return nil end
  local actionType, id, subType = GetActionInfo(slot)
  if IRL.IsSecret(actionType) or IRL.IsSecret(id) then return nil end
  local spellID
  if actionType == "spell" then
    spellID = id
  elseif actionType == "macro" then
    if subType == "spell" then spellID = id else spellID = GetMacroSpell(id) end
  end
  if type(spellID) ~= "number" or IRL.IsSecret(spellID) then return nil end
  return spellID
end

-- Gate for the spell a button will actually cast: its override when it has
-- one (e.g. Rushing Wind Kick replacing Rising Sun Kick), else the spell.
function IRL.GateForSpell(spellID)
  if not spellID then return nil end
  local override = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellID)
  if override and not IRL.IsSecret(override) and override ~= spellID then
    return IRL.FindGate(IRL.SpellName(override))
  end
  return IRL.FindGate(IRL.SpellName(spellID))
end

function IRL.LockedGateForSpell(spellID)
  local gate = IRL.GateForSpell(spellID)
  if gate and not gate.unlocked then return gate end
end

local function SetTint(button, on)
  local tex = tints[button]
  if on and not tex then
    tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
    tex:SetAllPoints(button.icon or button)
    tex:SetColorTexture(1, 0, 0, 0.45)
    tints[button] = tex
  end
  if tex then tex:SetShown(on) end
end

function IRL.RefreshOverlays()
  if InCombatLockdown() then pending = true return end
  pending = false
  local active = IRL.enforced and IRL.state ~= nil
  for _, prefix in ipairs(BARS) do
    for i = 1, 12 do
      local button = _G[prefix .. i]
      if button then
        local locked = active and IRL.LockedGateForSpell(IRL.ActionSpellID(ActionSlot(button))) ~= nil
        SetTint(button, locked)
      end
    end
  end
end

-- Coalesce bursts of slot events into one refresh.
local scheduled = false
function IRL.ScheduleOverlayRefresh()
  if InCombatLockdown() then pending = true return end
  if scheduled then return end
  scheduled = true
  C_Timer.After(0.2, function()
    scheduled = false
    IRL.RefreshOverlays()
  end)
end

local frame = CreateFrame("Frame")
for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
                     "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED" }) do
  frame:RegisterEvent(e)
end
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_ENABLED" then
    if pending then IRL.RefreshOverlays() end
    return
  end
  IRL.ScheduleOverlayRefresh()
end)

IRL.On("STATE_CHANGED", IRL.ScheduleOverlayRefresh)
