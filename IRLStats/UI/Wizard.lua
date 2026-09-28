-- First-launch setup wizard: profile, then one page per category (test,
-- current PR, goal pre-filled from norms where they exist). Re-runnable from
-- the main window; re-running keeps existing ladders and history.
local _, IRL = ...
local UI = IRL.UI
local Units = IRL.Units

local wiz
local draft -- { profile = {...}, [cat] = { test, pr, goal } }

local SEX_LABELS = { male = "Male", female = "Female", none = "Prefer not to say" }

local function Label(parent, text, x, y)
  local fs = UI.Text(parent, "GameFontNormal", text)
  fs:SetPoint("TOPLEFT", x, y)
  return fs
end

local function Edit(parent, width, x, y)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetPoint("TOPLEFT", x + 6, y)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", e.ClearFocus)
  e:SetScript("OnEnterPressed", e.ClearFocus)
  return e
end

--------------------------------------------------------------------------
-- Pages
--------------------------------------------------------------------------
local function BuildProfilePage(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  local intro = UI.Text(p, "GameFontHighlight",
    "Your real-life stats are shared by every character on this account. This takes about a minute.")
  intro:SetPoint("TOPLEFT", 20, -10)
  intro:SetWidth(480)

  Label(p, "Units", 20, -56)
  p.units = UI.Button(p, "", 140, 22, function(self)
    p:Capture()
    draft.profile.units = draft.profile.units == "metric" and "imperial" or "metric"
    p:Load()
  end)
  p.units:SetPoint("TOPLEFT", 150, -52)

  Label(p, "Age", 20, -92)
  p.age = Edit(p, 60, 150, -88)
  p.age:SetNumeric(true)

  Label(p, "Sex", 20, -128)
  p.sex = UI.Button(p, "", 140, 22, function(self)
    UI.Menu(self, function(root)
      for _, key in ipairs({ "male", "female", "none" }) do
        root:CreateButton(SEX_LABELS[key], function() p:Capture(); draft.profile.sex = key; p:Load() end)
      end
    end)
  end)
  p.sex:SetPoint("TOPLEFT", 150, -124)
  local sexNote = UI.Text(p, "GameFontDisableSmall", "Only used to look up goal norms.")
  sexNote:SetPoint("LEFT", p.sex, "RIGHT", 10, 0)

  Label(p, "Bodyweight", 20, -164)
  p.weight = Edit(p, 60, 150, -160)
  p.weightUnit = UI.Text(p, "GameFontDisableSmall")
  p.weightUnit:SetPoint("LEFT", p.weight, "RIGHT", 8, 0)

  function p:Load()
    local pr = draft.profile
    self.units:SetText(pr.units == "metric" and "Metric" or "Imperial")
    self.sex:SetText(SEX_LABELS[pr.sex or "none"])
    self.age:SetText(pr.age and tostring(pr.age) or "")
    local imperial = pr.units ~= "metric"
    self.weightUnit:SetText(imperial and "lb" or "kg")
    if pr.weight then
      self.weight:SetText(string.format(imperial and "%d" or "%.1f", imperial and pr.weight * 2.20462 + 0.5 or pr.weight))
    else
      self.weight:SetText("")
    end
  end

  -- Keep whatever is typed, without validating.
  function p:Capture()
    local pr = draft.profile
    local age = tonumber(self.age:GetText())
    if age then pr.age = age end
    local w = tonumber(self.weight:GetText())
    if w then pr.weight = pr.units == "metric" and w or w / 2.20462 end
  end

  function p:Save()
    self:Capture()
    local age = draft.profile.age
    if not age or age < 8 or age > 100 then return false, "Enter your age." end
    -- Category pages parse input in the chosen units.
    IRL.db.profile.units = draft.profile.units
    return true
  end
  return p
end

local function BuildCategoryPage(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  p.heading = UI.Text(p, "GameFontNormalLarge")
  p.heading:SetPoint("TOPLEFT", 20, -10)
  p.gates = UI.Text(p, "GameFontHighlightSmall")
  p.gates:SetPoint("TOPLEFT", p.heading, "BOTTOMLEFT", 0, -6)
  p.gates:SetWidth(480)

  Label(p, "Test", 20, -64)
  p.test = UI.Button(p, "Pick a test", 260, 22, function(self)
    local cat = p.cat
    UI.Menu(self, function(root)
      for _, key in ipairs(IRL.Categories[cat].tests) do
        root:CreateButton(IRL.Tests[key].label, function()
          if draft[cat].test ~= key then draft[cat] = { test = key } end
          p:Load(cat)
        end)
      end
    end)
  end)
  p.test:SetPoint("TOPLEFT", 150, -60)
  p.how = UI.Text(p, "GameFontHighlightSmall")
  p.how:SetPoint("TOPLEFT", 150, -88)
  p.how:SetWidth(360)

  Label(p, "Current PR", 20, -130)
  p.pr = UI.ValueInput(p, 260)
  p.pr:SetPoint("TOPLEFT", 144, -126)

  Label(p, "Goal", 20, -170)
  p.goal = UI.ValueInput(p, 260)
  p.goal:SetPoint("TOPLEFT", 144, -166)
  p.goalNote = UI.Text(p, "GameFontDisableSmall")
  p.goalNote:SetPoint("TOPLEFT", 150, -196)
  p.goalNote:SetWidth(340)

  function p:Load(cat)
    self.cat = cat
    local d = draft[cat]
    local catDef = IRL.Categories[cat]
    local index
    for i, c in ipairs(IRL.CategoryOrder) do if c == cat then index = i end end
    self.heading:SetText(string.format("%d of %d: %s", index, #IRL.CategoryOrder, catDef.label))
    local gate = IRL.Gates[cat]
    local names = table.concat(gate.abilities, ", ") .. (gate.apex and (", " .. gate.apex.name .. " (apex)") or "")
    self.gates:SetText("Gates: " .. names)

    self.test:SetText(d.test and IRL.Tests[d.test].label or "Pick a test")
    local how = d.test and IRL.Tests[d.test].how
    self.how:SetText(how and ("How: " .. how) or "")
    self.pr:SetTest(d.test)
    self.goal:SetTest(d.test)
    self.pr:SetValue(d.pr)
    local norm = d.test and IRL.NormFor(d.test, draft.profile.age, draft.profile.sex)
    self.goal:SetValue(d.goal or norm)
    if not d.test then
      self.goalNote:SetText("Skip this category to leave its abilities locked for now.")
    elseif norm and not d.goal then
      self.goalNote:SetText("Pre-filled at about the 90th percentile for your age and sex (approximate). Edit freely.")
    elseif IRL.Tests[d.test].norm or IRL.Tests[d.test].unit ~= "level" then
      self.goalNote:SetText(norm and "" or "No norm for this test yet - set your own goal.")
    else
      self.goalNote:SetText("Pick the progression you're aiming for.")
    end
  end

  function p:Save()
    local d = draft[self.cat]
    if not d.test then return true end -- skipped
    local pr, err = self.pr:GetValue()
    if not pr then return false, "Current PR: " .. err end
    local goal, err2 = self.goal:GetValue()
    if not goal then return false, "Goal: " .. err2 end
    d.pr, d.goal = pr, goal
    return true
  end
  return p
end

--------------------------------------------------------------------------
-- Apply the draft to the saved data.
--------------------------------------------------------------------------
local function Apply()
  local before = IRL.state
  IRL.suppressToasts = true
  for k, v in pairs(draft.profile) do IRL.db.profile[k] = v end
  if IRL.db.profile.sex == "none" then IRL.db.profile.sex = nil end
  for _, cat in ipairs(IRL.CategoryOrder) do
    local d, c = draft[cat], IRL.db.categories[cat]
    if d.test then
      if c.test ~= d.test then IRL.SetTest(cat, d.test) end
      if d.pr ~= c.pr then IRL.LogPR(cat, d.pr) end
      if d.goal ~= c.goal then IRL.SetGoal(cat, d.goal) end
    end
  end
  IRL.db.setupDone = true
  IRL.Recompute("wizard")
  IRL.suppressToasts = false
  IRL.ShowUnlockToast(IRL.GateLogic.Diff(before, IRL.state))
end

local function Build()
  local f = CreateFrame("Frame", "IRLStatsWizard", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(540, 330)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "IRLStatsWizard")

  f.title = UI.Text(f, "GameFontHighlight", "IRL Stats setup")
  f.title:SetPoint("TOP", 0, -5)

  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 4, -30)
  body:SetPoint("BOTTOMRIGHT", -4, 44)
  f.profile = BuildProfilePage(body)
  f.category = BuildCategoryPage(body)

  f.error = UI.Text(f, "GameFontRedSmall")
  f.error:SetPoint("BOTTOMLEFT", 16, 40)

  f.back = UI.Button(f, "Back", 90, 22, function() f:Go(f.step - 1, "lenient") end)
  f.back:SetPoint("BOTTOMLEFT", 12, 12)
  f.skip = UI.Button(f, "Skip", 90, 22, function()
    local cat = IRL.CategoryOrder[f.step]
    if cat and not IRL.db.categories[cat].test then draft[cat] = {} end
    f:Go(f.step + 1, true)
  end)
  f.skip:SetPoint("BOTTOMRIGHT", -108, 12)
  f.next = UI.Button(f, "Next", 90, 22, function() f:Go(f.step + 1) end)
  f.next:SetPoint("BOTTOMRIGHT", -12, 12)

  -- step 0 = profile, 1..8 = categories. save: nil = validate and save,
  -- "lenient" = save what's valid and move on anyway, true = don't save.
  function f:Go(step, save)
    self.error:SetText("")
    if save ~= true and self.step then
      local page = self.step == 0 and self.profile or self.category
      local ok, err = page:Save()
      if not ok and save ~= "lenient" then self.error:SetText(err) return end
    end
    if step > #IRL.CategoryOrder then
      Apply()
      self:Hide()
      IRL.Print("Setup saved. Open /irl any time to log PRs and check-ins.")
      IRL.ToggleMain("Goals")
      return
    end
    self.step = math.max(0, step)
    self.profile:SetShown(self.step == 0)
    self.category:SetShown(self.step > 0)
    if self.step == 0 then self.profile:Load() else self.category:Load(IRL.CategoryOrder[self.step]) end
    self.back:SetEnabled(self.step > 0)
    self.skip:SetShown(self.step > 0)
    self.next:SetText(self.step == #IRL.CategoryOrder and "Finish" or "Next")
  end
  f:Hide()
  return f
end

function UI.ShowWizard()
  wiz = wiz or Build()
  draft = { profile = IRL.CopyTable(IRL.db.profile) }
  for _, cat in ipairs(IRL.CategoryOrder) do
    local c = IRL.db.categories[cat]
    draft[cat] = { test = c.test, pr = c.pr, goal = c.goal }
  end
  wiz.step = nil
  wiz:Show()
  wiz:Go(0, true)
end
