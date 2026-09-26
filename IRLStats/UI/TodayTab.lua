-- Today tab: the daily habit check-in and the PT and training streaks.
local _, IRL = ...
local UI = IRL.UI

local function Section(page, y, title, gates)
  local s = CreateFrame("Frame", nil, page)
  s:SetSize(740, 130)
  s:SetPoint("TOPLEFT", 10, y)

  local bg = s:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.03)

  s.title = UI.Text(s, "GameFontNormalLarge", title)
  s.title:SetPoint("TOPLEFT", 12, -12)
  s.gates = UI.Text(s, "GameFontHighlightSmall", "Gates: " .. gates)
  s.gates:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -6)
  s.status = UI.Text(s, "GameFontHighlight")
  s.status:SetPoint("TOPLEFT", s.gates, "BOTTOMLEFT", 0, -12)
  s.status:SetWidth(460)
  s.detail = UI.Text(s, "GameFontHighlightSmall")
  s.detail:SetPoint("TOPLEFT", s.status, "BOTTOMLEFT", 0, -6)
  return s
end

local function Pips(s)
  s.pipLabel = UI.Text(s, "GameFontNormalSmall", "Strikes")
  s.pipLabel:SetPoint("TOPRIGHT", -200, -80)
  s.pips = {}
  for i = 1, IRL.Config.maxStrikes do
    local p = s:CreateTexture(nil, "ARTWORK")
    p:SetSize(14, 14)
    p:SetPoint("LEFT", s.pipLabel, "RIGHT", 6 + (i - 1) * 18, 0)
    s.pips[i] = p
  end
end

local function SetPips(s, used)
  for i, p in ipairs(s.pips) do
    if i <= used then p:SetColorTexture(0.9, 0.15, 0.1, 1) else p:SetColorTexture(0.25, 0.25, 0.25, 1) end
  end
end

local function StreakSection(page, y, which, title, gates, buttonText)
  local s = Section(page, y, title, gates)
  Pips(s)
  s.button = UI.Button(s, buttonText, 170, 26, function() IRL.LogSession(which) end)
  s.button:SetPoint("TOPRIGHT", -14, -14)
  s.best = UI.Text(s, "GameFontNormalSmall")
  s.best:SetPoint("TOPRIGHT", -14, -80)

  function s:Refresh()
    local streak = IRL.db.streaks[which]
    local alive, current, strikes = IRL.StreakStatus(which)
    local doneToday = streak.lastDay == IRL.Today()
    if alive then
      self.status:SetText(string.format("|cff4dff4dStreak alive:|r %d session%s", current, current == 1 and "" or "s"))
    elseif streak.lastDay then
      self.status:SetText("|cffff6040Streak ended.|r Log a session to start a fresh one.")
    else
      self.status:SetText("|cffff6040No streak yet.|r Log your first session to start one.")
    end
    self.detail:SetText(streak.last and ("Last session: " .. streak.last) or "")
    self.best:SetText("Best: " .. (streak.best or 0))
    SetPips(self, strikes)
    self.button:SetEnabled(not doneToday)
    self.button:SetText(doneToday and "Done today" or buttonText)
  end
  return s
end

UI.RegisterPage("Today", function(page)
  local habit = Section(page, -8, "Daily habit", table.concat(IRL.SpecialGates.habit.abilities, ", "))
  habit.button = UI.Button(habit, "Took my supplements", 170, 26, function() IRL.CheckIn() end)
  habit.button:SetPoint("TOPRIGHT", -14, -14)
  function habit:Refresh()
    local done = IRL.HabitDoneToday()
    local names = table.concat(IRL.SpecialGates.habit.abilities, ", ")
    self.status:SetText(done and ("|cff4dff4dChecked in today.|r " .. names .. " unlocked until midnight.")
      or ("|cffff6040Not yet today.|r " .. names .. " stays locked until you check in."))
    self.detail:SetText(IRL.db.habit.last and ("Last check-in: " .. IRL.db.habit.last) or "")
    self.button:SetEnabled(not done)
    self.button:SetText(done and "Done today" or "Took my supplements")
  end

  local pt = StreakSection(page, -146, "pt", "Mobility / PT streak",
    table.concat(IRL.SpecialGates.pt.abilities, ", ") .. " (self-heals)", "Did mobility/PT")
  local training = StreakSection(page, -284, "training", "Training streak",
    IRL.SpecialGates.training.heroTree .. " hero tree", "Trained today")

  local note = UI.Text(page, "GameFontDisableSmall",
    "Each calendar day without a session uses a strike; strike " .. IRL.Config.maxStrikes
    .. " ends the streak. Your best streak is never reduced.")
  note:SetPoint("TOPLEFT", 14, -426)

  function page:Refresh()
    habit:Refresh(); pt:Refresh(); training:Refresh()
  end
end)
