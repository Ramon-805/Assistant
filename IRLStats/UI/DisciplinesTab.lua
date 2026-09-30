-- Disciplines tab: the viewed spec's six disciplines plus the shared
-- supporting tests, each with your tier, the next target, what it keys,
-- retest countdown and the retry window after a failed retest.
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
local function KeyedBy(rb, key)
  local cacheKey = rb.key .. ":" .. key
  if keyedCache[cacheKey] then return keyedCache[cacheKey] end
  local list = {}
  for name, k in pairs(rb.keys) do
    if k.key[1] == key then table.insert(list, name .. " (" .. IRL.Tiers[k.key[2]] .. ")") end
  end
  for _, pk in ipairs(rb.patternKeys) do
    if pk.key[1] == key then table.insert(list, pk.label .. " (" .. IRL.Tiers[pk.key[2]] .. ")") end
  end
  if IRL.FlyingKey[1] == key then table.insert(list, "Flying (" .. IRL.Tiers[IRL.FlyingKey[2]] .. ")") end
  for g = 0, IRL.GateCount do
    local def = rb.gateDefs[g]
    if def.key and def.key[1] == key then
      table.insert(list, "Gate " .. g .. " (" .. IRL.Tiers[def.key[2]] .. ")")
    end
  end
  table.sort(list)
  keyedCache[cacheKey] = table.concat(list, ", ")
  return keyedCache[cacheKey]
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

-- "Baseline 1:00, latest 1:05" and "Next: Silver at 1:09 or better"
local function MeasuredText(def, testKey, entry, tier)
  if not entry.baseline then return nil, nil end
  local sub = "Baseline " .. Units.Format(testKey, entry.baseline) .. ", latest " .. Units.Format(testKey, entry.value)
  local targets = R.Targets(def, entry.baseline)
  local nextTier = tier + 1
  local nextText = targets[nextTier]
    and string.format("Next: %s at %s or %s", IRL.Tiers[nextTier], Units.Format(testKey, targets[nextTier]),
      def.lower and "faster" or "better")
    or "|cffffd100Legendary - top tier|r"
  return sub, nextText
end

local function DroppedNotice(label, entry, oldTier, newTier)
  if entry.lastDay and newTier < oldTier then
    IRL.Print(string.format("%s dropped to %s. Its keys are off your bar until you pass again; one retry within %d days.",
      label, R.TierName(newTier), IRL.RetryDays))
  end
end

local function LogDiscipline(rb, key)
  local d = rb.disciplines[key]
  local entry = IRL.DisciplineStore(rb)[key]
  local testKey = "d_" .. key
  if d.scale == "percent" then
    local ctx = IRL.ViewContext()
    local text
    if not entry.baseline then
      text = "Log your Test Day result. It becomes your baseline, so test honestly: every tier is measured from it."
    else
      local target = R.Targets(d, entry.baseline)[R.Tier(ctx, key) + 1]
      text = "Log today's result." .. (target and (" Next tier at " .. Units.Format(testKey, target) .. ".") or "")
    end
    UI.Prompt({
      title = rb.label .. ": " .. d.label, text = text, showHow = true, requireVideo = true, test = testKey,
      onAccept = function(v)
        local old = R.Tier(IRL.ViewContext(), key)
        IRL.LogMeasured(key, v, rb)
        DroppedNotice(d.label, entry, old, R.Tier(IRL.ViewContext(), key))
      end,
    })
  else
    UI.Prompt({
      title = rb.label .. ": " .. d.label,
      text = "Pick the highest tier you passed on camera today.",
      showHow = true, requireVideo = true,
      test = testKey, value = (entry.tier or 0) + 1,
      onAccept = function(v)
        local old = entry.tier or 0
        IRL.LogDiscipline(key, v - 1, rb)
        DroppedNotice(d.label, entry, old, v - 1)
      end,
    })
  end
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

-- A row is either discipline slot `slot` of the viewed rulebook, or a
-- supporting test `supportKey` (shared by every spec).
local function BuildRow(page, index, y, slot, supportKey)
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

  row.log = UI.Button(row, "Log test", 80, 22, function()
    if supportKey then LogSupport(supportKey) else LogDiscipline(IRL.ViewRulebook(), row.key) end
  end)
  row.log:SetPoint("RIGHT", supportKey and -50 or -6, 0)
  if supportKey then
    row.more = UI.Button(row, "...", 40, 22, function(self)
      UI.Menu(self, function(root)
        root:CreateTitle(IRL.Supports[supportKey].label)
        root:CreateButton("Set a new baseline...", function() LogSupport(supportKey, true) end)
      end)
    end)
    row.more:SetPoint("RIGHT", -6, 0)
  end

  function row:Refresh(ctx)
    local rb = ctx.rb
    local key = supportKey or rb.disciplineOrder[slot]
    self.key = key
    local tier = R.Tier(ctx, key)
    self.tier:SetText(TierLabel(tier))
    local keyed = KeyedBy(rb, key)
    self.keys:SetText(keyed ~= "" and ("Keys: " .. keyed) or "")

    if supportKey then
      local s, entry = IRL.Supports[key], IRL.db.supports[key]
      self.name:SetText(s.label)
      local sub, nextText = MeasuredText(s, s.test, entry, tier)
      self.sub:SetText(sub or "Supporting test")
      self.nextText:SetText(nextText or "Log a first result to set your baseline.")
      self.retest:SetText(RetestText(entry))
      return
    end

    local d, entry = rb.disciplines[key], ctx.disc[key]
    self.name:SetText(d.label)
    if d.scale == "percent" then
      local sub, nextText = MeasuredText(d, "d_" .. key, entry, tier)
      self.sub:SetText(sub or d.equipment)
      self.nextText:SetText(nextText or (d.measure .. ": Test Day sets your baseline."))
    else
      self.sub:SetText(d.equipment)
      self.nextText:SetText(d.tiers[tier + 1]
        and ("Next: " .. IRL.Tiers[tier + 1] .. " - " .. d.tiers[tier + 1])
        or "|cffffd100Legendary - top tier|r")
    end
    self.retest:SetText(RetestText(entry))
  end
  return row
end

UI.RegisterPage("Disciplines", function(page)
  page.rows = {}
  local y = -4
  for slot = 1, 6 do
    table.insert(page.rows, BuildRow(page, slot, y, slot))
    y = y - ROW_HEIGHT
  end
  local sep = UI.Text(page, "GameFontNormalSmall", "Supporting tests (shared by every spec; keys only, not rank)")
  sep:SetPoint("TOPLEFT", 14, y - 4)
  y = y - 20
  for i, key in ipairs(IRL.SupportOrder) do
    table.insert(page.rows, BuildRow(page, i, y, nil, key))
    y = y - ROW_HEIGHT
  end

  function page:Refresh()
    local ctx = IRL.ViewContext()
    for _, row in ipairs(self.rows) do row:Refresh(ctx) end
  end
end)
