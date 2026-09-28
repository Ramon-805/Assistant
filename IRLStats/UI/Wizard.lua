-- Test Day wizard: the protocol, then one page per discipline (pick the
-- highest tier you passed on camera), then reaction time and the mile.
-- Re-running it is the monthly retest: every discipline is logged again.
local _, IRL = ...
local UI = IRL.UI

local wiz
local draft -- [key] = { value, filmed }

-- Steps: intro, six disciplines, reaction, mile.
local STEPS = { "intro" }
for _, key in ipairs(IRL.DisciplineOrder) do table.insert(STEPS, key) end
table.insert(STEPS, "reaction")
table.insert(STEPS, "mile")

local INTRO = table.concat({
  "Your Windwalker is only as strong as you are. Log what you can do on camera today.",
  "",
  "- Same time of day and the same warm-up every test (5 min light jog plus dynamic stretches).",
  "- Day 1: Flexibility, Press, Pull, Push, Legs, Core, reaction time. Day 2: mile run.",
  "- Film every attempt uncut with a timer visible, in one folder named by date.",
  "- A rep that breaks form doesn't count.",
  "",
  "Re-run this every month as your retest. Anything you can no longer do comes off your bar.",
}, "\n")

local function TestKey(key)
  return IRL.Disciplines[key] and ("d_" .. key) or IRL.Supports[key].test
end

local function BuildPage(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  p.heading = UI.Text(p, "GameFontNormalLarge")
  p.heading:SetPoint("TOPLEFT", 20, -8)
  p.body = UI.Text(p, "GameFontHighlight")
  p.body:SetPoint("TOPLEFT", 20, -34)
  p.body:SetWidth(500)
  p.body:SetSpacing(2)

  p.tiers = UI.Text(p, "GameFontHighlightSmall")
  p.tiers:SetPoint("TOPLEFT", 20, -96)
  p.tiers:SetWidth(500)
  p.tiers:SetSpacing(3)

  p.inputLabel = UI.Text(p, "GameFontNormal")
  p.inputLabel:SetPoint("TOPLEFT", 20, -186)
  p.input = UI.ValueInput(p, 300)
  p.input:SetPoint("TOPLEFT", 150, -182)
  p.video = UI.VideoCheck(p)
  p.video:SetPoint("TOPLEFT", 146, -210)

  function p:Load(step)
    local isIntro = step == "intro"
    self.tiers:SetShown(not isIntro)
    self.inputLabel:SetShown(not isIntro)
    self.input:SetShown(not isIntro)
    self.video:SetShown(not isIntro)
    if isIntro then
      self.heading:SetText("Test Day")
      self.body:SetText(INTRO)
      return
    end
    local d = draft[step]
    local test = TestKey(step)
    self.input:SetTest(test)
    self.input:SetValue(d.value)
    self.video:SetChecked(d.filmed or false)
    local disc = IRL.Disciplines[step]
    if disc then
      self.heading:SetText(disc.label .. "  |cff999999(" .. disc.equipment .. ")|r")
      self.body:SetText(disc.form)
      local lines = {}
      for i, text in ipairs(disc.tiers) do
        lines[i] = "|c" .. IRL.TierColors[i] .. IRL.Tiers[i] .. "|r  " .. text
      end
      self.tiers:SetText(table.concat(lines, "\n"))
      self.inputLabel:SetText("Highest tier")
    else
      local s, entry = IRL.Supports[step], IRL.db.supports[step]
      self.heading:SetText(s.label .. "  |cff999999(supporting test)|r")
      self.body:SetText(IRL.Tests[test].how)
      self.tiers:SetText(entry.baseline
        and ("Baseline " .. IRL.Units.Format(test, entry.baseline)
             .. ". Bronze matches it; Silver, Gold and Legendary are 5%, 10% and 15% faster.")
        or "Your first result becomes your baseline. Skip if you'll test it another day; its keys stay locked.")
      self.inputLabel:SetText("Result")
    end
  end

  function p:Save(step, lenient)
    if step == "intro" then return true end
    local d = draft[step]
    local v, err = self.input:GetValue()
    d.filmed = self.video:GetChecked() and true or false
    if not v then
      if lenient then return true end
      return false, err
    end
    d.value = v
    if not d.filmed and not lenient then return false, UI.NO_VIDEO end
    return true
  end
  return p
end

local function Apply()
  local before = IRL.state
  IRL.suppressToasts = true
  for _, step in ipairs(STEPS) do
    local d = draft[step]
    if d and d.value and d.filmed then
      if IRL.Disciplines[step] then IRL.LogDiscipline(step, d.value - 1)
      else IRL.LogSupport(step, d.value) end
    end
  end
  IRL.suppressToasts = false
  IRL.ShowUnlockToast(IRL.Rules.Diff(before, IRL.state))
end

local function Build()
  local f = CreateFrame("Frame", "IRLStatsWizard", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(560, 330)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "IRLStatsWizard")

  f.title = UI.Text(f, "GameFontHighlight", "Gymlocke - Test Day")
  f.title:SetPoint("TOP", 0, -5)
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 4, -26)
  body:SetPoint("BOTTOMRIGHT", -4, 44)
  f.page = BuildPage(body)

  f.error = UI.Text(f, "GameFontRedSmall")
  f.error:SetPoint("BOTTOMLEFT", 16, 40)
  f.back = UI.Button(f, "Back", 90, 22, function() f:Go(f.step - 1, "lenient") end)
  f.back:SetPoint("BOTTOMLEFT", 12, 12)
  f.skip = UI.Button(f, "Skip", 90, 22, function()
    draft[STEPS[f.step]] = {}
    f:Go(f.step + 1, true)
  end)
  f.skip:SetPoint("BOTTOMRIGHT", -108, 12)
  f.next = UI.Button(f, "Next", 90, 22, function() f:Go(f.step + 1) end)
  f.next:SetPoint("BOTTOMRIGHT", -12, 12)

  -- save: nil = validate, "lenient" = keep what's valid, true = don't save.
  function f:Go(step, save)
    self.error:SetText("")
    if save ~= true and self.step then
      local ok, err = self.page:Save(STEPS[self.step], save == "lenient")
      if not ok then self.error:SetText(err) return end
    end
    if step > #STEPS then
      Apply()
      self:Hide()
      IRL.Print("Test Day logged. See your rank and gates in /irl.")
      IRL.ToggleMain("Rank")
      return
    end
    self.step = math.max(1, step)
    local name = STEPS[self.step]
    self.page:Load(name)
    self.back:SetEnabled(self.step > 1)
    -- The six disciplines are all required for Test Day; supporting tests can wait.
    self.skip:SetShown(IRL.Supports[name] ~= nil)
    self.next:SetText(self.step == #STEPS and "Finish" or "Next")
  end
  f:Hide()
  return f
end

function UI.ShowWizard()
  wiz = wiz or Build()
  draft = {}
  for _, key in ipairs(IRL.DisciplineOrder) do
    local tier = IRL.db.disciplines[key].tier or 0
    draft[key] = { value = IRL.db.disciplines[key].lastDay and tier + 1 or nil }
  end
  for _, key in ipairs(IRL.SupportOrder) do draft[key] = {} end
  wiz.step = nil
  wiz:Show()
  wiz:Go(1, true)
end
