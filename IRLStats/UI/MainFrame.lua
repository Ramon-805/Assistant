-- The /irl window: a portrait frame styled like the character pane, with
-- Rank, Disciplines and Flags tabs. Each tab registers a page builder with
-- UI.RegisterPage(name, build); a page exposes :Refresh().
local _, IRL = ...
local UI = IRL.UI

UI.pageDefs = {}
function UI.RegisterPage(name, build)
  table.insert(UI.pageDefs, { name = name, build = build })
end

local main

local function SelectTab(index)
  PanelTemplates_SetTab(main, index)
  for i, page in ipairs(main.pages) do page:SetShown(i == index) end
  main.selected = index
  main.pages[index]:Refresh()
end

local function RefreshHeader()
  local name = UnitName("player") or ""
  local enforced = IRL.enforced and ("|cff4dff4d" .. IRL.rb.label .. " gates active|r")
    or "|cff999999not enforced on this character|r"
  main.status:SetText(name .. " - " .. enforced)
  local view = IRL.ViewRulebook()
  main.spec:SetText("Showing: " .. view.label .. (view == IRL.rb and "" or " (not your spec)"))
end

local function Build()
  local f = CreateFrame("Frame", "IRLStatsFrame", UIParent, "PortraitFrameTemplate")
  f:SetSize(800, 580)
  f:SetPoint("CENTER")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  tinsert(UISpecialFrames, "IRLStatsFrame")

  if f.SetTitle then f:SetTitle("Gymlocke") elseif f.TitleText then f.TitleText:SetText("Gymlocke") end
  if f.SetPortraitToUnit then f:SetPortraitToUnit("player") end

  f.status = UI.Text(f, "GameFontHighlightSmall")
  f.status:SetPoint("TOPLEFT", 70, -34)

  f.setup = UI.Button(f, "Test Day / retest", 130, 22, function() IRL.UI.ShowWizard() end)
  f.setup:SetPoint("TOPRIGHT", -12, -28)

  -- Each spec has its own ladder; view either one, whatever you're playing.
  f.spec = UI.Button(f, "", 210, 22, function(self)
    UI.Menu(self, function(root)
      root:CreateTitle("Rulebook")
      for _, key in ipairs(IRL.RulebookOrder) do
        local rb = IRL.Rulebooks[key]
        root:CreateButton(rb.label .. (rb == IRL.rb and " (your spec)" or ""), function() IRL.SetViewRulebook(rb) end)
      end
    end)
  end)
  f.spec:SetPoint("RIGHT", f.setup, "LEFT", -6, 0)

  f.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  f.inset:SetPoint("TOPLEFT", 4, -60)
  f.inset:SetPoint("BOTTOMRIGHT", -6, 4)

  f.pages, f.Tabs = {}, {}
  for i, def in ipairs(UI.pageDefs) do
    local page = CreateFrame("Frame", nil, f.inset)
    page:SetPoint("TOPLEFT", 4, -4)
    page:SetPoint("BOTTOMRIGHT", -4, 4)
    page:Hide()
    def.build(page)
    f.pages[i] = page

    local tab = CreateFrame("Button", "IRLStatsFrameTab" .. i, f, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(def.name)
    tab:SetScript("OnClick", function() SelectTab(i) end)
    if i == 1 then
      tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
    else
      tab:SetPoint("TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", 3, 0)
    end
    f.Tabs[i] = tab
  end
  PanelTemplates_SetNumTabs(f, #f.pages)

  f:SetScript("OnShow", function()
    RefreshHeader()
    SelectTab(f.selected or 1)
  end)
  f:Hide()
  return f
end

function UI.RefreshMain()
  if main and main:IsShown() then
    RefreshHeader()
    main.pages[main.selected or 1]:Refresh()
  end
end

-- tab: optional page name ("Rank", "Disciplines", "Flags")
function IRL.ToggleMain(tab)
  main = main or Build()
  local index
  for i, def in ipairs(UI.pageDefs) do
    if tab and def.name:lower() == tab:lower() then index = i end
  end
  if main:IsShown() and not index then main:Hide() return end
  if index then main.selected = index end
  if main:IsShown() then SelectTab(main.selected) else main:Show() end
end

IRL.On("STATE_CHANGED", UI.RefreshMain)
IRL.On("VIEW_CHANGED", UI.RefreshMain)
IRL.On("FLAG_ADDED", UI.RefreshMain)
IRL.On("LOADOUT_READ", UI.RefreshMain)
