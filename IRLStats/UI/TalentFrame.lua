-- Locked talents view: red tint and requirement tooltips on talent-frame
-- buttons (class, spec and hero talents). The talent UI loads on demand, so
-- this hooks in when Blizzard_PlayerSpells loads. Only textures and script
-- hooks are added; no Blizzard fields are written.
local _, IRL = ...

local tints = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function Call(obj, method)
  if obj and obj[method] then
    local ok, v = pcall(obj[method], obj)
    if ok then return v end
  end
end

-- The gate (and active rank) behind a talent button, or nil.
local function ButtonGate(button)
  if not IRL.state then return nil end
  local node = Call(button, "GetNodeInfo")
  local rank = node and node.activeRank or 0
  if node and node.subTreeID then
    local configID = C_ClassTalents.GetActiveConfigID()
    local info = configID and C_Traits.GetSubTreeInfo(configID, node.subTreeID)
    local tree = info and IRL.state.heroTrees[info.name]
    if tree then return tree, rank end
  end
  local name = IRL.SpellName(Call(button, "GetSpellID"))
  if not name then return nil end
  return IRL.FindGate(name), rank
end

local function IsLocked(gate, rank)
  local apex = IRL.state.apex[gate.name]
  if apex then return apex.unlockedRanks == 0 or rank > apex.unlockedRanks end
  return not gate.unlocked
end

local function OnEnter(button)
  if not IRL.enforced then return end
  local gate, rank = ButtonGate(button)
  if gate and GameTooltip:IsOwned(button) then
    IRL.AppendGateTooltip(GameTooltip, gate, rank)
    GameTooltip:Show()
  end
end

local function Refresh()
  if InCombatLockdown() then return end
  local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
  if not tf or not tf:IsVisible() or not tf.EnumerateAllTalentButtons then return end
  for button in tf:EnumerateAllTalentButtons() do
    local gate, rank = ButtonGate(button)
    local locked = IRL.enforced and gate ~= nil and IsLocked(gate, rank)
    local tex = tints[button]
    if locked and not tex then
      tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
      tex:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
      tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
      tex:SetColorTexture(1, 0, 0, 0.4)
      tints[button] = tex
    end
    if tex then tex:SetShown(locked) end
    if not hooked[button] then
      hooked[button] = true
      button:HookScript("OnEnter", OnEnter)
    end
  end
end

local scheduled = false
local function Schedule()
  if scheduled then return end
  scheduled = true
  C_Timer.After(0.1, function() scheduled = false; Refresh() end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_PlayerSpells", function()
  local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
  if not tf then return end
  tf:HookScript("OnShow", Schedule)
  if tf.UpdateTreeInfo then hooksecurefunc(tf, "UpdateTreeInfo", Schedule) end
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("TRAIT_NODE_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", Schedule)
IRL.On("STATE_CHANGED", Schedule)
