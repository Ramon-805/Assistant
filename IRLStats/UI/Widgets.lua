-- Shared UI pieces: on-screen warning, unlock toasts, value inputs, a
-- prompt dialog and context menus. All frames here are non-secure.
local _, IRL = ...

local UI = {}
IRL.UI = UI

UI.RED = { 1, 0.25, 0.2 }
UI.GREEN = { 0.3, 1, 0.3 }
UI.GOLD = { 1, 0.82, 0 }

--------------------------------------------------------------------------
-- Fading message frames (warning = red, toast = green)
--------------------------------------------------------------------------
local function MessageFrame(yOffset, font)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(800, 90)
  f:SetPoint("TOP", UIParent, "TOP", 0, yOffset)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(false)
  f.text = f:CreateFontString(nil, "OVERLAY", font)
  f.text:SetPoint("TOP")
  f.text:SetWidth(800)
  f.text:SetJustifyH("CENTER")
  f:Hide()
  f:SetScript("OnUpdate", function(self, elapsed)
    self.age = self.age + elapsed
    local hold, fade = self.hold or 3, 1
    if self.age > hold + fade then self:Hide()
    elseif self.age > hold then self:SetAlpha(1 - (self.age - hold) / fade) end
  end)
  function f:Show3(text, r, g, b, hold)
    self.text:SetText(text)
    self.text:SetTextColor(r, g, b)
    self.age, self.hold = 0, hold
    self:SetAlpha(1)
    self:Show()
  end
  return f
end

local warningFrame, toastFrame

function IRL.ShowWarning(text)
  warningFrame = warningFrame or MessageFrame(-160, "GameFontNormalLarge")
  warningFrame:Show3(text, UI.RED[1], UI.RED[2], UI.RED[3], 3)
  if IRL.Config.warningSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING)
  end
end

-- gained / lost: lists of names from IRL.Recompute
function IRL.ShowUnlockToast(gained, lost)
  if IRL.suppressToasts then return end
  local lines = {}
  for _, n in ipairs(gained or {}) do table.insert(lines, "|cff4dff4dUnlocked: " .. n .. "|r") end
  for _, n in ipairs(lost or {}) do table.insert(lines, "|cffff6040Locked again: " .. n .. "|r") end
  if #lines == 0 then return end
  if #lines > 6 then
    local extra = #lines - 5
    for i = #lines, 6, -1 do lines[i] = nil end
    table.insert(lines, "|cffffffff+" .. extra .. " more (see /irl)|r")
  end
  toastFrame = toastFrame or MessageFrame(-220, "GameFontNormalLarge")
  toastFrame:Show3(table.concat(lines, "\n"), 1, 1, 1, 4)
  if #gained > 0 and SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST) end
end

--------------------------------------------------------------------------
-- Basic widgets
--------------------------------------------------------------------------
function UI.Button(parent, text, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, height or 22)
  b:SetText(text)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Text(parent, font, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if text then fs:SetText(text) end
  fs:SetJustifyH("LEFT")
  return fs
end

-- build(root) receives a MenuUtil root description.
function UI.Menu(owner, build)
  MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
end

function UI.Tooltip(frame, title, body)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", GameTooltip_Hide)
end

--------------------------------------------------------------------------
-- Value input: an edit box with a unit hint, or a level picker for skill
-- ladders. :SetTest(key), :SetValue(v), :GetValue() -> value | nil, err
--------------------------------------------------------------------------
function UI.ValueInput(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width or 260, 24)

  f.edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.edit:SetSize(90, 20)
  f.edit:SetPoint("LEFT", 6, 0)
  f.edit:SetAutoFocus(false)
  f.edit:SetScript("OnEscapePressed", f.edit.ClearFocus)
  f.edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if f.onEnter then f.onEnter() end
  end)

  f.hint = UI.Text(f, "GameFontDisableSmall")
  f.hint:SetPoint("LEFT", f.edit, "RIGHT", 8, 0)

  f.level = UI.Button(f, "Pick a level", width or 260, 22, function(self)
    local test = IRL.Tests[f.test]
    UI.Menu(self, function(root)
      root:CreateTitle(test.label)
      for i, name in ipairs(test.levels) do
        root:CreateButton(i .. ". " .. name, function() f:SetValue(i) end)
      end
    end)
  end)
  f.level:SetPoint("LEFT")
  f.level:Hide()

  function f:SetTest(testKey)
    self.test, self.levelValue = testKey, nil
    local test = testKey and IRL.Tests[testKey]
    local isLevel = test and test.unit == "level"
    self.level:SetShown(isLevel)
    self.edit:SetShown(not isLevel)
    self.hint:SetShown(not isLevel)
    self.edit:SetText("")
    self.level:SetText("Pick a level")
    if test and not isLevel then self.hint:SetText(IRL.Units.InputHint(testKey)) end
  end

  function f:SetValue(v)
    if not self.test then return end
    if IRL.Tests[self.test].unit == "level" then
      self.levelValue = v
      self.level:SetText(v and IRL.Units.Format(self.test, v) or "Pick a level")
    else
      self.edit:SetText(v and IRL.Units.EditText(self.test, v) or "")
    end
  end

  function f:GetValue()
    if not self.test then return nil, "Pick a test first." end
    if IRL.Tests[self.test].unit == "level" then
      if not self.levelValue then return nil, "Pick a level." end
      return self.levelValue
    end
    return IRL.Units.Parse(self.test, self.edit:GetText())
  end

  return f
end

--------------------------------------------------------------------------
-- "No video, no credit" confirmation: a checkbox with its own label.
--------------------------------------------------------------------------
UI.NO_VIDEO = "No video, no credit: film it uncut with a timer visible."

function UI.VideoCheck(parent)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c.label = UI.Text(c, "GameFontHighlightSmall", "Filmed uncut, timer visible, saved in today's folder")
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
  return c
end

--------------------------------------------------------------------------
-- Prompt dialog: UI.Prompt{ title, text, test, value, onAccept = fn(v) }
--------------------------------------------------------------------------
local prompt
local function BuildPrompt()
  local f = CreateFrame("Frame", "IRLStatsPrompt", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(340, 150)
  f:SetPoint("CENTER", 0, 120)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "IRLStatsPrompt")

  f.title = UI.Text(f, "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.text = UI.Text(f, "GameFontNormal")
  f.text:SetPoint("TOPLEFT", 16, -34)
  f.text:SetWidth(308)
  f.how = UI.Text(f, "GameFontHighlightSmall")
  f.how:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -6)
  f.how:SetWidth(308)
  f.input = UI.ValueInput(f, 300)
  f.input:SetPoint("TOPLEFT", f.how, "BOTTOMLEFT", -2, -8)
  f.video = UI.VideoCheck(f)
  f.video:SetPoint("TOPLEFT", f.input, "BOTTOMLEFT", 0, -4)
  f.error = UI.Text(f, "GameFontRedSmall")
  f.error:SetPoint("TOPLEFT", f.video, "BOTTOMLEFT", 2, -4)

  local function accept()
    local v, err = f.input:GetValue()
    if not v then f.error:SetText(err) return end
    if f.video:IsShown() and not f.video:GetChecked() then f.error:SetText(UI.NO_VIDEO) return end
    f:Hide()
    if f.onAccept then f.onAccept(v) end
  end
  f.input.onEnter = accept
  f.ok = UI.Button(f, OKAY or "OK", 100, 22, accept)
  f.ok:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
  f.cancel = UI.Button(f, CANCEL or "Cancel", 100, 22, function() f:Hide() end)
  f.cancel:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
  f:Hide()
  return f
end

function UI.Prompt(opts)
  prompt = prompt or BuildPrompt()
  prompt.title:SetText(opts.title or "Gymlocke")
  prompt.text:SetText(opts.text or "")
  local how = opts.showHow and IRL.Tests[opts.test].how
  prompt.how:SetText(how and ("How: " .. how) or "")
  -- Grow to fit the instructions: title, text, how, input, error, buttons.
  prompt.video:SetShown(opts.requireVideo and true or false)
  prompt.video:SetChecked(false)
  prompt:SetHeight(130 + prompt.text:GetStringHeight() + (how and prompt.how:GetStringHeight() or 0)
    + (opts.requireVideo and 26 or 0))
  prompt.error:SetText("")
  prompt.input:SetTest(opts.test)
  prompt.input:SetValue(opts.value)
  prompt.onAccept = opts.onAccept
  prompt:Show()
  if IRL.Tests[opts.test].unit ~= "level" then prompt.input.edit:SetFocus() end
end
