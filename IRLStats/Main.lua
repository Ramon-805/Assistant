-- Startup, day-rollover ticker, toasts and slash commands.
local ADDON, IRL = ...

local function OnStateChanged(gained, lost, reason)
  if reason == nil or reason == "init" then return end
  IRL.ShowUnlockToast(gained, lost)
end
IRL.On("STATE_CHANGED", OnStateChanged)

--------------------------------------------------------------------------
-- /irl verify: check every gate name against the live client. Works at any
-- level: names are checked by spell ID (readable whether or not the spell is
-- learned), by spellbook, and against the Windwalker talent tree, which is
-- read from your loadout or, below level 10, from a view-only copy.
--------------------------------------------------------------------------
local WINDWALKER = 269

local function ScanConfig(configID, names)
  local info = configID and C_Traits.GetConfigInfo(configID)
  if not info or not info.treeIDs or #info.treeIDs == 0 then return false end
  local count = 0
  for _, treeID in ipairs(info.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      for _, entryID in ipairs(node and node.entryIDs or {}) do
        local entry = C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
        local name = def and ((def.overrideName and def.overrideName ~= "" and def.overrideName) or IRL.SpellName(def.spellID))
        if name then names[name:lower()] = true; count = count + 1 end
      end
    end
  end
  local specID = IRL.CurrentSpecID() or WINDWALKER
  if C_ClassTalents.GetHeroTalentSpecsForClassSpec then
    for _, id in ipairs(C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specID) or {}) do
      local sub = C_Traits.GetSubTreeInfo(configID, id)
      if sub and sub.name then names[sub.name:lower()] = true; count = count + 1 end
    end
  end
  return count > 0
end

-- Returns a set of lower-cased talent names and where they came from.
local function CollectTalentNames()
  local names = {}
  local specID = IRL.CurrentSpecID()
  local candidates = { C_ClassTalents.GetActiveConfigID() }
  if specID and C_ClassTalents.GetConfigIDsBySpecID then
    for _, id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specID) or {}) do table.insert(candidates, id) end
  end
  for _, id in ipairs(candidates) do
    local ok, found = pcall(ScanConfig, id, names)
    if ok and found then return names, "your talent loadout" end
  end
  -- No usable loadout (e.g. below level 10): build a view-only Windwalker tree.
  local viewID = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
  if viewID and C_ClassTalents.InitializeViewLoadout then
    local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 90
    local ok = pcall(C_ClassTalents.InitializeViewLoadout, specID or WINDWALKER, maxLevel)
    local ok2, found = pcall(ScanConfig, viewID, names)
    if ok and ok2 and found then return names, "a view-only Windwalker tree" end
  end
  return names, nil
end

local function Verify()
  if InCombatLockdown() then IRL.Print("Run /irl verify out of combat.") return end
  local talents, source = CollectTalentNames()
  local found, missing, renamed, total = 0, {}, {}, 0

  local function check(name)
    total = total + 1
    local id = IRL.SpellIDHints[name]
    local byID = id and IRL.SpellName(id)
    if byID and byID:lower() == name:lower() then found = found + 1 return end
    if talents[name:lower()] or C_Spell.GetSpellInfo(name) ~= nil then found = found + 1 return end
    if byID then
      table.insert(renamed, string.format("%s: spell %d is now called \"%s\"", name, id, byID))
    else
      table.insert(missing, name)
    end
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

  IRL.Print(string.format("Level %s, spec %s, talents read from %s.",
    tostring(UnitLevel("player")), tostring(IRL.CurrentSpecID() or "none"),
    source or "|cffff6040nowhere (talent data unavailable)|r"))
  IRL.Print(string.format("%d of %d gate names found.", found, total))
  for _, line in ipairs(renamed) do IRL.Print("  |cffffd100" .. line .. "|r") end
  for _, n in ipairs(missing) do IRL.Print("  |cffff6040Not found: " .. n .. "|r") end
  if #renamed + #missing > 0 then
    IRL.Print("Copy these lines to Claude so the gate table can be fixed.")
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
    else
      for _, cat in ipairs(IRL.CategoryOrder) do
        local test = IRL.db.categories[cat].test
        if test and IRL.Tests[test].legacy then
          IRL.Print(IRL.Categories[cat].label .. " uses the " .. IRL.Tests[test].label
            .. ", which is no longer offered. Switch to an easier solo test from the ... menu in /irl.")
        end
      end
    end
    if IRL.db.setupDone and not IRL.enforced then
      IRL.Print("Gates aren't enforced on this character (build 1 covers Windwalker monks).")
    end
  end
end)
