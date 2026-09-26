-- Talent-loadout detection. Out of combat only: walks the active loadout
-- via C_ClassTalents / C_Traits and flags locked talents and hero trees.
-- Each locked selection writes one flag per loadout change: a signature of
-- the loadout (and of what is locked) is stored per character, and flags are
-- only written when it differs from the last one.
local _, IRL = ...

-- Returns a list of selected talents: { name, rank, nodeID, spellID },
-- the active hero tree name (or nil), and a loadout signature.
function IRL.ReadLoadout()
  local configID = C_ClassTalents.GetActiveConfigID()
  if not configID then return nil end
  local configInfo = C_Traits.GetConfigInfo(configID)
  if not configInfo or not configInfo.treeIDs then return nil end

  local selected, sigParts = {}, {}
  local subTreeType = Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection
  for _, treeID in ipairs(configInfo.treeIDs) do
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      local active = node and node.ID ~= 0 and (node.activeRank or 0) > 0 and node.activeEntry
      if active and node.subTreeID and not node.subTreeActive then active = false end
      if active and subTreeType and node.type == subTreeType then active = false end
      if active then
        local entryID = node.activeEntry.entryID
        local entry = C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
        local spellID = def and (def.overriddenSpellID or def.spellID)
        local name = (def and def.overrideName and def.overrideName ~= "" and def.overrideName) or IRL.SpellName(spellID)
        if name then
          table.insert(selected, { name = name, rank = node.activeRank, nodeID = nodeID, spellID = spellID })
        end
        table.insert(sigParts, nodeID .. "=" .. entryID .. ":" .. node.activeRank)
      end
    end
  end

  local heroTree
  local subTreeID = C_ClassTalents.GetActiveHeroTalentSpec and C_ClassTalents.GetActiveHeroTalentSpec()
  if subTreeID then
    local info = C_Traits.GetSubTreeInfo(configID, subTreeID)
    heroTree = info and info.name
  end

  table.sort(sigParts)
  return selected, heroTree, configID .. "#" .. table.concat(sigParts, ","), subTreeID
end

-- Locked selections in a loadout: list of { name, detail, requirement }.
function IRL.LockedSelections(selected, heroTree)
  local locked = {}
  for _, t in ipairs(selected) do
    local gate = IRL.FindGate(t.name)
    local apex = IRL.state.apex[t.name]
    if apex then
      if t.rank > apex.unlockedRanks then
        table.insert(locked, { name = t.name, detail = "rank " .. t.rank .. " (unlocked: " .. apex.unlockedRanks .. ")" })
      end
    elseif gate and not gate.unlocked then
      table.insert(locked, { name = t.name })
    end
  end
  if heroTree then
    local tree = IRL.state.heroTrees[heroTree]
    if tree and not tree.unlocked then
      table.insert(locked, { name = heroTree, detail = "hero tree" })
    end
  end
  table.sort(locked, function(a, b) return a.name < b.name end)
  return locked
end

function IRL.CheckTalents()
  if not IRL.state or not IRL.enforced then return end
  if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED re-checks
  local ok, selected, heroTree, sig, subTreeID = pcall(IRL.ReadLoadout)
  if not ok or not selected then return end
  IRL.loadout = { selected = selected, heroTree = heroTree, subTreeID = subTreeID }

  local locked = IRL.LockedSelections(selected, heroTree)
  local lockedParts = {}
  for _, l in ipairs(locked) do table.insert(lockedParts, l.name .. (l.detail or "")) end
  local fullSig = sig .. "|" .. table.concat(lockedParts, ",")
  if fullSig == IRL.char.talentSig then return end
  IRL.char.talentSig = fullSig
  for _, l in ipairs(locked) do
    IRL.AddFlag(l.name, "talent", l.detail)
  end
  if #locked > 0 then
    IRL.ShowWarning(#locked == 1 and ("Locked talent selected: " .. locked[1].name)
      or (#locked .. " locked talents selected - see /irl"))
  end
  IRL.Fire("LOADOUT_READ")
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_SPECIALIZATION_CHANGED" then
    if arg1 and arg1 ~= "player" then return end
    IRL.enforced = IRL.IsEnforced()
  end
  -- Loadout data settles a frame after these events.
  C_Timer.After(0.5, IRL.CheckTalents)
end)

IRL.On("STATE_CHANGED", function() C_Timer.After(0, IRL.CheckTalents) end)
