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
  local names = {}
  for name in pairs(IRL.Keys) do table.insert(names, name) end
  for _, list in ipairs({ IRL.MajorCooldowns, IRL.FortifyingUpgrades.extra, IRL.ApexNames,
                          { "Shado-Pan", "Conduit of the Celestials" } }) do
    for _, name in ipairs(list) do table.insert(names, name) end
  end
  table.sort(names)
  for _, name in ipairs(names) do check(name) end

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
  "/irl - open the Gymlocke sheet (rank, disciplines, flags)",
  "/irl rank | disciplines | flags - open a tab",
  "/irl testday - run Test Day (log all six disciplines and baselines)",
  "/irl verify - check rulebook talent names against your spells and talents",
  "/irl minimap - show/hide the minimap button",
}

SLASH_IRLSTATS1 = "/irl"
SLASH_IRLSTATS2 = "/irlstats"
SlashCmdList.IRLSTATS = function(msg)
  local cmd = (msg or ""):lower():match("^%s*(%S*)")
  if cmd == "" then IRL.ToggleMain()
  elseif cmd == "rank" or cmd == "disciplines" or cmd == "flags" then IRL.ToggleMain(cmd)
  elseif cmd == "testday" or cmd == "setup" then IRL.UI.ShowWizard()
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
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    IRL.InitDB()
    self:UnregisterEvent("ADDON_LOADED")
  elseif event == "PLAYER_LEVEL_UP" then
    C_Timer.After(0.5, function() IRL.Recompute("level") end) -- gates 4 and 5 are level-based
  elseif event == "PLAYER_LOGIN" then
    IRL.enforced = IRL.IsEnforced()
    IRL.Recompute("init")
    IRL.CreateMinimapButton()
    C_Timer.NewTicker(30, IRL.CheckDayRollover)
    if not IRL.Rules.TestDayDone(IRL.db) then
      IRL.Print("Gymlocke: Test Day isn't done yet. Film all six disciplines, then log them. (/irl testday)")
      C_Timer.After(3, IRL.UI.ShowWizard)
    elseif not IRL.enforced then
      IRL.Print("Gates aren't enforced on this character (the rulebook covers Windwalker monks).")
    end
  end
end)
