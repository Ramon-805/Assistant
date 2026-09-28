-- Talent-tree reading and loadout flagging (out of combat only).
--
-- Walks every node of the active config and records where it sits:
--   section      1 top / 2 middle / 3 bottom, from the tree's own point gates
--   isCapstone   bottom row of the spec tree (apex excluded)
--   isApex       named in IRL.ApexNames, or a 4+ rank spec node
--   heroTree     hero sub-tree name; isHeroFinal = its bottom row
-- That meta feeds Core/Rules.lua, the talent-frame tints and tooltips.
-- Each locked selection writes one flag per loadout change (signature below).
local _, IRL = ...

IRL.nodeMetaByID = {}

local function Currency(configID, nodeID)
  local costs = C_Traits.GetNodeCost and C_Traits.GetNodeCost(configID, nodeID)
  return costs and costs[1] and costs[1].ID
end

local function EntryName(configID, entryID)
  local entry = C_Traits.GetEntryInfo(configID, entryID)
  local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
  if not def then return nil end
  if def.overrideName and def.overrideName ~= "" then return def.overrideName end
  return IRL.SpellName(def.overriddenSpellID or def.spellID)
end

local apexNames
local function IsApexName(name)
  if not apexNames then
    apexNames = {}
    for _, n in ipairs(IRL.ApexNames) do apexNames[n:lower()] = true end
  end
  return name and apexNames[name:lower()]
end

-- Returns metaByID, metaByName, selected = { {meta, rank, entryID} }, signature.
function IRL.ReadTree()
  local configID = C_ClassTalents.GetActiveConfigID()
  local configInfo = configID and C_Traits.GetConfigInfo(configID)
  if not configInfo or not configInfo.treeIDs then return nil end
  local subTreeType = Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection

  local byID, byName, selected, sigParts = {}, {}, {}, {}
  local specBottom, heroBottom = -math.huge, {}

  for _, treeID in ipairs(configInfo.treeIDs) do
    -- Section boundaries: each gate's top-left node, per currency (class/spec).
    local gates = {}
    local treeInfo = C_Traits.GetTreeInfo and C_Traits.GetTreeInfo(configID, treeID)
    for _, g in ipairs(treeInfo and treeInfo.gates or {}) do
      local gn = C_Traits.GetNodeInfo(configID, g.topLeftNodeID)
      if gn then table.insert(gates, { y = gn.posY, currency = Currency(configID, g.topLeftNodeID) }) end
    end
    local currencies = C_Traits.GetTreeCurrencyInfo and C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local specCurrency = currencies and currencies[2] and currencies[2].traitCurrencyID

    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and node.ID ~= 0 then
        local meta = { nodeID = nodeID, posY = node.posY or 0, maxRanks = node.maxRanks }
        if node.type == subTreeType then
          meta.heroTree, meta.isSelection = "Hero talents", true
        elseif node.subTreeID then
          local info = C_Traits.GetSubTreeInfo(configID, node.subTreeID)
          meta.heroTree = info and info.name or "Hero talents"
          meta.subTreeID = node.subTreeID
          heroBottom[node.subTreeID] = math.max(heroBottom[node.subTreeID] or -math.huge, meta.posY)
        else
          local cur = Currency(configID, nodeID)
          local section = 1
          for _, g in ipairs(gates) do
            if g.currency == cur and g.y <= meta.posY then section = section + 1 end
          end
          meta.section = math.min(section, 3)
          meta.isSpec = cur ~= nil and cur == specCurrency
        end

        -- One meta per entry name (choice nodes have two).
        local names = {}
        for _, entryID in ipairs(node.entryIDs or {}) do
          local name = EntryName(configID, entryID)
          if name then names[entryID] = name end
        end
        meta.names = names
        local firstName = node.activeEntry and names[node.activeEntry.entryID] or select(2, next(names))
        meta.name = meta.isSelection and meta.heroTree or firstName
        if meta.name then
          meta.isApex = IsApexName(meta.name) or (meta.isSpec and (node.maxRanks or 0) >= 4) or nil
          if meta.isSpec and not meta.isApex then specBottom = math.max(specBottom, meta.posY) end
          byID[nodeID] = meta

          local active = (node.activeRank or 0) > 0 and node.activeEntry
          if active and node.subTreeID and not node.subTreeActive then active = false end
          if active then
            local entryID = node.activeEntry.entryID
            if meta.isSelection then
              local heroID = C_ClassTalents.GetActiveHeroTalentSpec and C_ClassTalents.GetActiveHeroTalentSpec()
              local info = heroID and C_Traits.GetSubTreeInfo(configID, heroID)
              meta.name = info and info.name or meta.name
            end
            table.insert(selected, { meta = meta, rank = node.activeRank,
                                     name = meta.isSelection and meta.name or names[entryID] or meta.name })
            table.insert(sigParts, nodeID .. "=" .. entryID .. ":" .. node.activeRank)
          end
        end
      end
    end
  end

  -- Bottom rows, now that every node's position is known.
  for _, meta in pairs(byID) do
    if meta.isSpec and not meta.isApex and meta.posY >= specBottom then meta.isCapstone = true end
    if meta.subTreeID and meta.posY >= heroBottom[meta.subTreeID] then meta.isHeroFinal = true end
    for _, name in pairs(meta.names) do
      local m = {}
      for k, v in pairs(meta) do m[k] = v end
      m.name, m.names = name, nil
      byName[name:lower()] = m
    end
  end

  table.sort(sigParts)
  return byID, byName, selected, configID .. "#" .. table.concat(sigParts, ",")
end

-- Judge one node at a rank.
function IRL.EvaluateMeta(meta, rank, name)
  local m = {}
  for k, v in pairs(meta) do m[k] = v end
  m.rank, m.name, m.names = rank, name or meta.name, nil
  return IRL.Rules.Evaluate(IRL.state.ctx, m)
end

-- Locked selections: list of { name, detail }.
function IRL.LockedSelections(selected)
  local locked = {}
  for _, s in ipairs(selected or {}) do
    local result = IRL.EvaluateMeta(s.meta, s.rank, s.name)
    if not result.unlocked then
      local detail = result.missing[1]
      if s.meta.isApex then detail = "rank " .. s.rank .. ": " .. detail end
      table.insert(locked, { name = s.name, detail = detail })
    end
  end
  table.sort(locked, function(a, b) return a.name < b.name end)
  return locked
end

local lastMetaSig
function IRL.CheckTalents()
  if not IRL.state or not IRL.enforced then return end
  if InCombatLockdown() then return end -- PLAYER_REGEN_ENABLED re-checks
  local ok, byID, byName, selected, sig = pcall(IRL.ReadTree)
  if not ok or not byID then return end
  IRL.nodeMetaByID = byID
  IRL.loadout = { selected = selected }

  -- New tree data changes what casts and tooltips know about; recompute once.
  local names = {}
  for name in pairs(byName) do names[#names + 1] = name end
  table.sort(names)
  local metaSig = table.concat(names, ",")
  if metaSig ~= lastMetaSig then
    lastMetaSig = metaSig
    IRL.nodeMeta = byName
    IRL.Recompute("loadout")
  end

  local locked = IRL.LockedSelections(selected)
  local lockedParts = {}
  for _, l in ipairs(locked) do table.insert(lockedParts, l.name .. (l.detail or "")) end
  local fullSig = sig .. "|" .. table.concat(lockedParts, ",")
  if fullSig ~= IRL.char.talentSig then
    IRL.char.talentSig = fullSig
    for _, l in ipairs(locked) do IRL.AddFlag(l.name, "talent", l.detail) end
    if #locked > 0 then
      IRL.ShowWarning(#locked == 1 and ("Locked talent selected: " .. locked[1].name)
        or (#locked .. " locked talents selected - see /irl flags"))
    end
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

IRL.On("STATE_CHANGED", function(_, _, reason)
  if reason ~= "loadout" then C_Timer.After(0, IRL.CheckTalents) end
end)
