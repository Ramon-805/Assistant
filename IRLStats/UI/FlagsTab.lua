-- Flags tab: this character's flag log, newest first. Read-only.
local _, IRL = ...
local UI = IRL.UI

local function FlagLine(f)
  local when = date("%Y-%m-%d %H:%M", f.t)
  local what = f.name .. (f.detail and (" (" .. f.detail .. ")") or "")
  local kind = f.kind == "talent" and "|cffc080fftalent|r" or "|cffff8040cast|r"
  local where = (f.zone ~= "" and f.zone or "unknown zone") .. (f.combat and ", in combat" or "")
  return string.format("|cff999999%s|r  %s  %s  |cff999999- %s|r", when, kind, what, where)
end

UI.RegisterPage("Flags", function(page)
  page.count = UI.Text(page, "GameFontNormalLarge")
  page.count:SetPoint("TOPLEFT", 12, -10)
  page.current = UI.Text(page, "GameFontHighlightSmall")
  page.current:SetPoint("TOPLEFT", page.count, "BOTTOMLEFT", 0, -6)
  page.current:SetWidth(730)

  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 10, -60)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(720, 10)
  scroll:SetScrollChild(content)
  page.text = UI.Text(content, "GameFontHighlightSmall")
  page.text:SetPoint("TOPLEFT")
  page.text:SetWidth(720)
  page.text:SetSpacing(3)

  function page:Refresh()
    local flags = IRL.char.flags
    self.count:SetText(string.format("%d flag%s on %s", #flags, #flags == 1 and "" or "s", UnitName("player") or "this character"))

    local lockedNow = {}
    if IRL.loadout and IRL.state then
      for _, l in ipairs(IRL.LockedSelections(IRL.loadout.selected, IRL.loadout.heroTree)) do
        table.insert(lockedNow, l.name .. (l.detail and (" " .. l.detail) or ""))
      end
    end
    self.current:SetText(#lockedNow > 0
      and ("|cffff6040Locked in your current loadout:|r " .. table.concat(lockedNow, ", "))
      or "|cff4dff4dNothing locked in your current loadout.|r")

    local lines = {}
    for i = #flags, 1, -1 do table.insert(lines, FlagLine(flags[i])) end
    self.text:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff999999No flags yet.|r")
    content:SetHeight(math.max(10, self.text:GetStringHeight() + 10))
  end
end)
