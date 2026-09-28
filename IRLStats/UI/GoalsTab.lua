-- Goals tab: one row per category with test, PR, goal, next milestone,
-- progress bar toward it, what it unlocks, and Log PR / edit buttons.
local _, IRL = ...
local UI = IRL.UI
local Units = IRL.Units

local ROW_HEIGHT = 54

local function CategoryIcon(cat)
  for _, name in ipairs(IRL.Gates[cat].abilities) do
    local tex = C_Spell.GetSpellTexture(name)
    if tex then return tex end
  end
  return 134400 -- INV_Misc_QuestionMark
end

-- Next rung that has rewards: returns rung index and reward names.
local function NextRewards(cs)
  for r = cs.achieved + 1, #cs.rungs do
    if cs.rewards[r] then return r, cs.rewards[r] end
  end
end

-- Prompt for a goal, pre-filled from norms when possible.
function UI.PromptGoal(cat)
  local c = IRL.db.categories[cat]
  local p = IRL.db.profile
  local norm = IRL.NormFor(c.test, p.age, p.sex)
  local text = "Goal for " .. IRL.Tests[c.test].label .. "."
  if norm and not c.goal then text = text .. "\nPre-filled at the ~90th percentile for your age (approximate)." end
  UI.Prompt({
    title = IRL.Categories[cat].label, text = text, test = c.test, value = c.goal or norm,
    onAccept = function(v) IRL.SetGoal(cat, v) end,
  })
end

function UI.PromptPR(cat, thenGoal)
  local c = IRL.db.categories[cat]
  UI.Prompt({
    title = IRL.Categories[cat].label,
    text = "Log a result for " .. IRL.Tests[c.test].label .. ".",
    showHow = true,
    test = c.test,
    value = IRL.Tests[c.test].unit == "level" and c.pr or nil,
    onAccept = function(v)
      local improved = IRL.LogPR(cat, v)
      if not improved then
        IRL.Print(string.format("Logged %s. PR stays %s.", Units.Format(c.test, v), Units.Format(c.test, c.pr)))
      end
      if thenGoal then UI.PromptGoal(cat) end
    end,
  })
end

local function ChangeTest(cat, testKey)
  IRL.SetTest(cat, testKey)
  UI.PromptPR(cat, true)
end

local function ShowEditMenu(owner, cat)
  local c = IRL.db.categories[cat]
  UI.Menu(owner, function(root)
    root:CreateTitle(IRL.Categories[cat].label)
    local sub = root:CreateButton("Change test")
    for _, key in ipairs(IRL.Categories[cat].tests) do
      sub:CreateButton(IRL.Tests[key].label .. (key == c.test and " (current)" or ""), function()
        if key ~= c.test then ChangeTest(cat, key) end
      end)
    end
    if c.test then
      root:CreateButton("Set goal...", function() UI.PromptGoal(cat) end)
      if c.pr and c.baseline and c.pr ~= c.baseline then
        root:CreateButton("Restart ladder from current PR", function() IRL.Rebaseline(cat) end)
      end
      root:CreateButton("Print history to chat", function()
        IRL.Print(IRL.Categories[cat].label .. " history:")
        for _, h in ipairs(c.history) do
          IRL.Print("  " .. h.date .. "  " .. Units.Format(c.test, h.value))
        end
      end)
    end
  end)
end

-- Tooltip over the progress bar: the whole ladder with rewards.
local function LadderTooltip(bar)
  local cat = bar.cat
  local c, cs = IRL.db.categories[cat], IRL.state.categories[cat]
  GameTooltip:SetOwner(bar, "ANCHOR_RIGHT")
  GameTooltip:SetText(IRL.Categories[cat].label .. " ladder", 1, 1, 1)
  if not c.test or #cs.rungs == 0 then
    GameTooltip:AddLine("Set a test, PR and goal to build the ladder.", nil, nil, nil, true)
  else
    GameTooltip:AddDoubleLine("Baseline", Units.Format(c.test, c.baseline), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
    for r, v in ipairs(cs.rungs) do
      local done = r <= cs.achieved
      local col = done and UI.GREEN or (r == cs.achieved + 1 and UI.GOLD or { 0.6, 0.6, 0.6 })
      local rewards = cs.rewards[r] and table.concat(cs.rewards[r], ", ") or ""
      GameTooltip:AddDoubleLine(r .. ". " .. Units.Format(c.test, v), rewards, col[1], col[2], col[3], col[1], col[2], col[3])
    end
  end
  GameTooltip:Show()
end

local function BuildRow(page, cat, index)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(760, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 4, -24 - (index - 1) * ROW_HEIGHT)
  row.cat = cat

  if index % 2 == 0 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.03)
  end

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(36, 36)
  row.icon:SetPoint("LEFT", 6, 0)

  row.name = UI.Text(row, "GameFontNormal", IRL.Categories[cat].label)
  row.name:SetPoint("TOPLEFT", 50, -10)
  row.test = UI.Text(row, "GameFontHighlightSmall")
  row.test:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
  row.test:SetWidth(190)
  row.test:SetWordWrap(false)

  row.pr = UI.Text(row, "GameFontHighlight")
  row.pr:SetPoint("LEFT", 250, 0)
  row.pr:SetWidth(100)
  row.goal = UI.Text(row, "GameFontHighlight")
  row.goal:SetPoint("LEFT", 355, 0)
  row.goal:SetWidth(100)

  local bar = CreateFrame("StatusBar", nil, row)
  bar:SetSize(180, 14)
  bar:SetPoint("TOPLEFT", 460, -10)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.2, 0.8, 0.3)
  bar:SetMinMaxValues(0, 1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(0, 0, 0, 0.5)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  bar.cat = cat
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", LadderTooltip)
  bar:SetScript("OnLeave", GameTooltip_Hide)
  row.bar = bar

  row.unlocks = UI.Text(row, "GameFontHighlightSmall")
  row.unlocks:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -5)
  row.unlocks:SetWidth(185)
  row.unlocks:SetWordWrap(false)

  row.log = UI.Button(row, "Log PR", 66, 22, function()
    local c = IRL.db.categories[cat]
    if c.test then
      if c.goal then UI.PromptPR(cat) else UI.PromptPR(cat, true) end
    else
      ShowEditMenu(row.log, cat)
    end
  end)
  row.log:SetPoint("RIGHT", -52, 0)
  row.edit = UI.Button(row, "...", 40, 22, function(self) ShowEditMenu(self, cat) end)
  row.edit:SetPoint("RIGHT", -6, 0)
  return row
end

local function RefreshRow(row)
  local cat = row.cat
  local c, cs = IRL.db.categories[cat], IRL.state.categories[cat]
  row.icon:SetTexture(CategoryIcon(cat))

  if not c.test then
    row.test:SetText("|cff999999No test chosen|r")
    row.pr:SetText("--"); row.goal:SetText("--")
    row.bar:SetValue(0)
    row.bar.text:SetText("Not set up")
    row.unlocks:SetText("|cffff6040Locked: " .. table.concat(IRL.Gates[cat].abilities, ", ") .. "|r")
    row.log:SetText("Set up")
    return
  end

  row.log:SetText("Log PR")
  row.test:SetText(IRL.Tests[c.test].label .. (IRL.Tests[c.test].legacy and " |cff999999(retired)|r" or ""))
  row.pr:SetText(Units.Format(c.test, c.pr))
  row.goal:SetText(Units.Format(c.test, c.goal))

  if #cs.rungs == 0 then
    row.bar:SetValue(0)
    row.bar.text:SetText(c.pr and "Set a goal" or "Log a PR")
    row.unlocks:SetText("")
    return
  end

  local nextValue = cs.rungs[cs.achieved + 1]
  if not nextValue then
    row.bar:SetValue(1)
    row.bar.text:SetText("Goal reached!")
    row.unlocks:SetText("|cff4dff4dEverything unlocked|r")
    return
  end
  local prev = cs.achieved > 0 and cs.rungs[cs.achieved] or c.baseline
  local frac = (nextValue ~= prev and c.pr) and (c.pr - prev) / (nextValue - prev) or 0
  row.bar:SetValue(math.max(0, math.min(1, frac)))
  row.bar.text:SetText(string.format("Next: %s  (%d/%d)", Units.Format(c.test, nextValue), cs.achieved, #cs.rungs))

  local rung, rewards = NextRewards(cs)
  if rewards then
    local where = rung == cs.achieved + 1 and "" or (" at " .. Units.Format(c.test, cs.rungs[rung]))
    row.unlocks:SetText("|cffffd100Unlocks" .. where .. ":|r " .. table.concat(rewards, ", "))
  else
    row.unlocks:SetText("|cff4dff4dAll abilities unlocked|r")
  end
end

UI.RegisterPage("Goals", function(page)
  local headers = { { "Category", 54 }, { "PR", 254 }, { "Goal", 359 }, { "Next milestone", 464 } }
  for _, h in ipairs(headers) do
    local fs = UI.Text(page, "GameFontNormalSmall", h[1])
    fs:SetPoint("TOPLEFT", h[2], -6)
  end
  page.rows = {}
  for i, cat in ipairs(IRL.CategoryOrder) do page.rows[i] = BuildRow(page, cat, i) end

  function page:Refresh()
    for _, row in ipairs(self.rows) do RefreshRow(row) end
  end
end)
