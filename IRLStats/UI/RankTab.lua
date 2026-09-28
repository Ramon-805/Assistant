-- Rank tab: current rank, the gate map (what each gate needs, your progress,
-- what it opens) and the content ceilings table.
local _, IRL = ...
local UI = IRL.UI
local R = IRL.Rules

local function Color(hex, text) return "|c" .. hex .. text .. "|r" end
local GREEN, RED, GREY, GOLD = "ff4dff4d", "ffff6040", "ff999999", "ffffd100"

-- Progress toward a gate's own condition, e.g. "4/6 at Bronze".
local function GateProgress(g)
  local db, def = IRL.db, IRL.GateDefs[g]
  local parts = {}
  if def.testDay then
    local n = 0
    for _, key in ipairs(IRL.DisciplineOrder) do if db.disciplines[key].lastDay then n = n + 1 end end
    table.insert(parts, n .. "/6 filmed")
  end
  if def.need then
    table.insert(parts, string.format("%d/%d at %s", math.min(R.CountAtLeast(db, def.need[1]), def.need[2]),
      def.need[2], IRL.Tiers[def.need[1]]))
  end
  if def.level then
    table.insert(parts, string.format("level %d/%d", math.min(IRL.PlayerLevelSafe(), def.level), def.level))
  end
  if def.key then
    table.insert(parts, IRL.Disciplines[def.key[1]].label .. " " .. R.TierName(R.Tier(db, def.key[1])))
  end
  return table.concat(parts, ", ")
end

local function NextRankText(rank)
  local nextDef = IRL.Ranks[rank + 1]
  if not nextDef then return Color(GOLD, "Top rank reached.") end
  local need = {}
  if nextDef.gate and not IRL.state.open[nextDef.gate] then table.insert(need, R.GateText(nextDef.gate)) end
  if nextDef.need then table.insert(need, R.NeedText(nextDef.need)) end
  return "Next: " .. nextDef.name .. " - needs " .. table.concat(need, " + ")
end

UI.RegisterPage("Rank", function(page)
  page.rank = UI.Text(page, "GameFontNormalHuge")
  page.rank:SetPoint("TOPLEFT", 14, -10)
  page.next = UI.Text(page, "GameFontHighlight")
  page.next:SetPoint("TOPLEFT", page.rank, "BOTTOMLEFT", 0, -6)

  local header = UI.Text(page, "GameFontNormal", "Windwalker gate map")
  header:SetPoint("TOPLEFT", 14, -70)
  page.gates = {}
  for g = 0, IRL.GateCount do
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(750, 34)
    row:SetPoint("TOPLEFT", 10, -90 - g * 36)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, g % 2 == 0 and 0.04 or 0.02)
    row.status = UI.Text(row, "GameFontNormal")
    row.status:SetPoint("TOPLEFT", 6, -4)
    row.status:SetWidth(70)
    row.name = UI.Text(row, "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", 80, -4)
    row.need = UI.Text(row, "GameFontHighlightSmall")
    row.need:SetPoint("TOPLEFT", 80, -19)
    row.opens = UI.Text(row, "GameFontHighlightSmall")
    row.opens:SetPoint("TOPLEFT", 380, -4)
    row.opens:SetWidth(360)
    page.gates[g] = row
  end

  local ceilHeader = UI.Text(page, "GameFontNormal", "Rank ceilings (shown for reference; enforcement comes in a later update)")
  ceilHeader:SetPoint("TOPLEFT", 14, -312)
  local cols = { { "Rank", 0 }, { "Raid", 100 }, { "Mythic+", 220 }, { "PvP", 310 }, { "Delves", 460 }, { "Gear cap", 560 } }
  for _, c in ipairs(cols) do
    local fs = UI.Text(page, "GameFontNormalSmall", c[1])
    fs:SetPoint("TOPLEFT", 16 + c[2], -332)
  end
  page.ceilings = {}
  for i, def in ipairs(IRL.Ranks) do
    local cells = {}
    local values = { def.name, def.raid, def.mplus, def.pvp, def.delves, def.gear }
    for j, c in ipairs(cols) do
      local fs = UI.Text(page, "GameFontHighlightSmall", values[j])
      fs:SetPoint("TOPLEFT", 16 + c[2], -332 - i * 18)
      cells[j] = fs
    end
    page.ceilings[i] = cells
  end
  page.note = UI.Text(page, "GameFontDisableSmall",
    "Once you're Adept, content above your rank can be played with friends but earns no gymlocke credit.")
  page.note:SetPoint("TOPLEFT", 16, -432)

  function page:Refresh()
    local state = IRL.state
    local rank = state.rank
    self.rank:SetText("Rank: " .. Color(GOLD, IRL.Ranks[rank].name))
    self.next:SetText(NextRankText(rank))
    for g = 0, IRL.GateCount do
      local row, def = self.gates[g], IRL.GateDefs[g]
      local open = state.open[g]
      local blocked = g > 0 and not state.open[g - 1]
      row.status:SetText(open and Color(GREEN, "OPEN") or Color(blocked and GREY or RED, "LOCKED"))
      row.name:SetText(string.format("Gate %d - %s", g, def.name))
      row.need:SetText(def.requirement .. (open and "" or ("  |cff999999(" .. GateProgress(g) .. ")|r")))
      row.opens:SetText((open and "" or "|cff999999") .. def.opens .. (open and "" or "|r"))
    end
    for i, cells in ipairs(self.ceilings) do
      for _, fs in ipairs(cells) do
        if i == rank then fs:SetTextColor(1, 0.82, 0) else fs:SetTextColor(0.7, 0.7, 0.7) end
      end
    end
  end
end)
