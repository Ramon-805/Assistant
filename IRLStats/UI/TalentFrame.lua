-- Locked talents view: red tint and requirement tooltips on talent-frame
-- buttons. Unselected nodes are tinted too, so closed tree sections show at
-- a glance. The talent UI loads on demand, so this hooks in when
-- Blizzard_PlayerSpells loads. Only textures and script hooks are added; no
-- Blizzard fields are written.
local _, IRL = ...

local tints = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })

local function Call(obj, method)
  if obj and obj[method] then
    local ok, v = pcall(obj[method], obj)
    if ok then return v end
  end
end

-- Evaluation for the node behind a button, at its current rank (or rank 1).
local function ButtonResult(button)
  if not IRL.state then return nil end
  local node = Call(button, "GetNodeInfo")
  local nodeID = Call(button, "GetNodeID") or (node and node.ID)
  local meta = nodeID and IRL.nodeMetaByID[nodeID]
  if not meta then return nil end
  local rank = math.max(node and node.activeRank or 0, 1)
  local name = IRL.SpellName(Call(button, "GetSpellID"))
  return IRL.EvaluateMeta(meta, rank, name or meta.name)
end

local function OnEnter(button)
  if not IRL.enforced then return end
  local result = ButtonResult(button)
  if result and GameTooltip:IsOwned(button) then
    IRL.AppendGateTooltip(GameTooltip, result)
    GameTooltip:Show()
  end
end

local function Refresh()
  if InCombatLockdown() then return end
  local tf = PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
  if not tf or not tf:IsVisible() or not tf.EnumerateAllTalentButtons then return end
  for button in tf:EnumerateAllTalentButtons() do
    local result = IRL.enforced and ButtonResult(button)
    local locked = result and not result.unlocked
    local tex = tints[button]
    if locked and not tex then
      tex = button:CreateTexture(nil, "OVERLAY", nil, 7)
      tex:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
      tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
      tex:SetColorTexture(1, 0, 0, 0.4)
      tints[button] = tex
    end
    if tex then tex:SetShown(locked and true or false) end
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
IRL.On("LOADOUT_READ", Schedule)
