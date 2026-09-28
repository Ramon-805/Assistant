-- Disciplines tab: one row per discipline and supporting test with your
-- tier, the next landmark, what it keys, retest countdown and the retry
-- window after a failed retest.
local _, IRL = ...
local UI = IRL.UI
local R = IRL.Rules
local Units = IRL.Units

local ROW_HEIGHT = 52

local function TierLabel(tier)
  return "|c" .. IRL.TierColors[tier] .. R.TierName(tier) .. "|r"
end

-- Talents and gates that use this discipline or test, e.g. "Fists of Fury (Silver)".
local keyedCache = {}
local function KeyedBy(key)
  if keyedCache[key] then return keyedCache[key] end
  local list = {}
  for name, k in pairs(IRL.Keys) do
    if k.key[1] == key then table.insert(list, name .. " (" .. IRL.Tiers[k.key[2]] .. ")") end
  end
  local f = IRL.FortifyingUpgrades
  if f.key[1] == key then table.insert(list, "Fortifying Brew upgrades (" .. IRL.Tiers[f.key[2]] .. ")") end
  if IRL.FlyingKey[1] == key then table.insert(list, "Flying (" .. IRL.Tiers[IRL.FlyingKey[2]] .. ")") end
  for g = 0, IRL.GateCount do
    local def = IRL.GateDefs[g]
    if def.key and def.key[1] == key then
      table.insert(list, "Gate " .. g .. " (" .. IRL.Tiers[def.key[2]] .. ")")
    end
  end
  table.sort(list)
  keyedCache[key] = table.concat(list, ", ")
  return keyedCache[key]
end

local function RetestText(entry)
  local today = IRL.Today()
  local parts = {}
  local retry = R.RetryLeft(entry, today)
  if retry then
    table.insert(parts, string.format("|cffff6040Lost %s - one retry, %d day%s left|r",
      R.TierName(entry.lostTier), retry, retry == 1 and "" or "s"))
  end
  local due = R.RetestDue(entry, today)
  if due then
    if due < 0 then table.insert(parts, string.format("|cffff6040Retest overdue by %d days|r", -due))
    else table.insert(parts, string.format("Retest in %d day%s", due, due == 1 and "" or "s")) end
  end
  if entry.last then table.insert(parts, "last tested " .. entry.last) end
  return #parts > 0 and table.concat(parts, "  -  ") or "|cff999999Not tested yet|r"
end

local function LogDiscipline(key)
  local d, entry = IRL.Disciplines[key], IRL.db.disciplines[key]
  UI.Prompt({
    title = d.label,
    text = "Pick the highest tier you passed on camera today.",
    showHow = true, requireVideo = true,
    test = "d_" .. key, value = (entry.tier or 0) + 1,
    onAccept = function(v)
      local old = entry.tier or 0
      IRL.LogDiscipline(key, v - 1)
      if entry.lastDay and v - 1 < old then
        IRL.Print(string.format("%s dropped to %s. Its keys are off your bar until you pass again; one retry within %d days.",
          d.label, R.TierName(v - 1), IRL.RetryDays))
      end
    end,
  })
end

local function LogSupport(key, asBaseline)
  local s, entry = IRL.Supports[key], IRL.db.supports[key]
  UI.Prompt({
    title = s.label,
    text = asBaseline and "Enter your new baseline. Tiers are measured from it."
      or (entry.baseline and "Log today's result." or "Log your first result; it becomes your baseline."),
    showHow = true, requireVideo = true,
    test = s.test,
    onAccept = function(v)
      if asBaseline then IRL.SetSupportBaseline(key, v) else IRL.LogSupport(key, v) end
    end,
  })
end

local function BuildRow(page, index, y, key, isSupport)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(750, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 6, y)
  if index % 2 == 0 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.03)
  end

  row.name = UI.Text(row, "GameFontNormal")
  row.name:SetPoint("TOPLEFT", 8, -6)
  row.sub = UI.Text(row, "GameFontDisableSmall")
  row.sub:SetPoint("TOPLEFT", 8, -22)
  row.sub:SetWidth(130)
  row.tier = UI.Text(row, "GameFontNormalLarge")
  row.tier:SetPoint("TOPLEFT", 140, -8)
  row.nextText = UI.Text(row, "GameFontHighlightSmall")
  row.nextText:SetPoint("TOPLEFT", 250, -6)
  row.nextText:SetWidth(390)
  row.keys = UI.Text(row, "GameFontDisableSmall")
  row.keys:SetPoint("TOPLEFT", 250, -20)
  row.keys:SetWidth(390)
  row.keys:SetWordWrap(false)
  row.retest = UI.Text(row, "GameFontHighlightSmall")
  row.retest:SetPoint("TOPLEFT", 250, -34)
  row.retest:SetWidth(390)

  row.log = UI.Button(row, "Log test", 80, 22, function() if isSupport then LogSupport(key) else LogDiscipline(key) end end)
  row.log:SetPoint("RIGHT", isSupport and -50 or -6, 0)
  if isSupport then
    row.more = UI.Button(row, "...", 40, 22, function(self)
      UI.Menu(self, function(root)
        root:CreateTitle(IRL.Supports[key].label)
        root:CreateButton("Set a new baseline...", function() LogSupport(key, true) end)
      end)
    end)
    row.more:SetPoint("RIGHT", -6, 0)
  end

  function row:Refresh()
    local db = IRL.db
    local tier = R.Tier(db, key)
    self.tier:SetText(TierLabel(tier))
    local keyed = KeyedBy(key)
    self.keys:SetText(keyed ~= "" and ("Keys: " .. keyed) or "")
    if isSupport then
      local s, entry = IRL.Supports[key], db.supports[key]
      self.name:SetText(s.label)
      local test = s.test
      if entry.baseline then
        self.sub:SetText("Baseline " .. Units.Format(test, entry.baseline) .. ", latest " .. Units.Format(test, entry.value))
        local targets = R.SupportTargets(entry.baseline)
        local nextTier = tier + 1
        self.nextText:SetText(targets[nextTier]
          and string.format("Next: %s at %s or faster", IRL.Tiers[nextTier], Units.Format(test, targets[nextTier]))
          or "|cffffd100Legendary - top tier|r")
      else
        self.sub:SetText("Supporting test")
        self.nextText:SetText("Log a first result to set your baseline.")
      end
      self.retest:SetText(RetestText(entry))
    else
      local d, entry = IRL.Disciplines[key], db.disciplines[key]
      self.name:SetText(d.label)
      self.sub:SetText(d.equipment)
      self.nextText:SetText(d.tiers[tier + 1]
        and ("Next: " .. IRL.Tiers[tier + 1] .. " - " .. d.tiers[tier + 1])
        or "|cffffd100Legendary - top tier|r")
      self.retest:SetText(RetestText(entry))
    end
  end
  return row
end

UI.RegisterPage("Disciplines", function(page)
  page.rows = {}
  local y = -4
  for i, key in ipairs(IRL.DisciplineOrder) do
    table.insert(page.rows, BuildRow(page, i, y, key, false))
    y = y - ROW_HEIGHT
  end
  local sep = UI.Text(page, "GameFontNormalSmall", "Supporting tests (don't count toward rank; keys only)")
  sep:SetPoint("TOPLEFT", 14, y - 4)
  y = y - 20
  for i, key in ipairs(IRL.SupportOrder) do
    table.insert(page.rows, BuildRow(page, i, y, key, true))
    y = y - ROW_HEIGHT
  end

  function page:Refresh()
    for _, row in ipairs(self.rows) do row:Refresh() end
  end
end)
