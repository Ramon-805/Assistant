-- Startup, day-rollover ticker, toasts and slash commands.
local ADDON, IRL = ...

local function OnStateChanged(gained, lost, reason)
  if reason == nil or reason == "init" then return end
  IRL.ShowUnlockToast(gained, lost)
end
IRL.On("STATE_CHANGED", OnStateChanged)

--------------------------------------------------------------------------
-- /irl verify: check every gate name against the live spellbook and the
-- active talent config (answers "are these names right in 12.1?").
--------------------------------------------------------------------------
local function CollectTalentNames()
  local names = {}
  local configID = C_ClassTalents.GetActiveConfigID()
  local configInfo = configID and C_Traits.GetConfigInfo(configID)
  if not configInfo then return names, false end
  for _, treeID in ipairs(configInfo.treeIDs or {}) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      for _, entryID in ipairs(node and node.entryIDs or {}) do
        local entry = C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
        local name = def and ((def.overrideName ~= "" and def.overrideName) or IRL.SpellName(def.spellID))
        if name then names[name:lower()] = true end
      end
    end
  end
  if C_ClassTalents.GetHeroTalentSpecsForClassSpec then
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID)
    for _, id in ipairs(subTreeIDs or {}) do
      local info = C_Traits.GetSubTreeInfo(configID, id)
      if info and info.name then names[info.name:lower()] = true end
    end
  end
  return names, true
end

local function Verify()
  if InCombatLockdown() then IRL.Print("Run /irl verify out of combat.") return end
  local talents, haveTalents = CollectTalentNames()
  local missing, total = {}, 0
  local function check(name)
    total = total + 1
    local inBook = C_Spell.GetSpellInfo(name) ~= nil
    if not inBook and not talents[name:lower()] then table.insert(missing, name) end
  end
  for _, cat in ipairs(IRL.CategoryOrder) do
    local gate = IRL.Gates[cat]
    for _, n in ipairs(gate.abilities) do check(n) end
    if gate.apex then
      check(gate.apex.name)
      for _, n in pairs(gate.apex.grants or {}) do check(n) end
    end
  end
  for _, key in ipairs({ "habit", "pt" }) do
    for _, n in ipairs(IRL.SpecialGates[key].abilities) do check(n) end
  end
  check(IRL.SpecialGates.training.heroTree)
  check(IRL.SpecialGates.balance.heroTree)

  if #missing == 0 then
    IRL.Print(string.format("All %d gate names found in your spellbook or talent trees.", total))
  else
    IRL.Print(string.format("%d of %d gate names not found%s:", #missing, total,
      haveTalents and "" or " (talent data unavailable)"))
    for _, n in ipairs(missing) do IRL.Print("  |cffff6040" .. n .. "|r") end
    IRL.Print("Unlearned spells can show here at low level; rename entries in Data/Gates.lua if a name changed.")
  end
end

--------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------
local HELP = {
  "/irl - open the character sheet (goals, today, flags)",
  "/irl today | flags - open a tab",
  "/irl setup - run the setup wizard",
  "/irl checkin - took my supplements (daily habit)",
  "/irl pt - did mobility/PT today",
  "/irl trained - trained today",
  "/irl verify - check gate names against your spells and talents",
  "/irl minimap - show/hide the minimap button",
}

SLASH_IRLSTATS1 = "/irl"
SLASH_IRLSTATS2 = "/irlstats"
SlashCmdList.IRLSTATS = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" or cmd == "goals" then IRL.ToggleMain(cmd ~= "" and "Goals" or nil)
  elseif cmd == "today" or cmd == "flags" then IRL.ToggleMain(cmd)
  elseif cmd == "setup" then IRL.UI.ShowWizard()
  elseif cmd == "checkin" then
    IRL.Print(IRL.CheckIn() and "Checked in for today." or "Already checked in today.")
  elseif cmd == "pt" then
    IRL.Print(IRL.LogSession("pt") and "PT session logged." or "PT already logged today.")
  elseif cmd == "trained" then
    IRL.Print(IRL.LogSession("training") and "Training day logged." or "Training already logged today.")
  elseif cmd == "verify" then Verify()
  elseif cmd == "minimap" then
    IRL.db.minimap.hide = not IRL.db.minimap.hide
    IRL.minimapButton:SetShown(not IRL.db.minimap.hide)
  else
    for _, line in ipairs(HELP) do IRL.Print(line) end
  end
end

--------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    IRL.InitDB()
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LOGIN" then
    IRL.enforced = IRL.IsEnforced()
    IRL.Recompute("init")
    IRL.CreateMinimapButton()
    C_Timer.NewTicker(30, IRL.CheckDayRollover)
    if not IRL.db.setupDone then
      IRL.Print("Welcome! Let's set up your real-life stats. (/irl setup any time)")
      C_Timer.After(3, IRL.UI.ShowWizard)
    elseif not IRL.enforced then
      IRL.Print("Gates aren't enforced on this character (build 1 covers Windwalker monks).")
    end
  end
end)
