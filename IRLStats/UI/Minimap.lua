-- Minimap button: left-click opens /irl, right-click opens the Today tab,
-- drag to move around the minimap edge.
local _, IRL = ...

function IRL.CreateMinimapButton()
  if IRL.minimapButton then return end
  local settings = IRL.db.minimap
  local b = CreateFrame("Button", "IRLStatsMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture(136477)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetSize(20, 20)
  bg:SetTexture(136467)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture("Interface\\Icons\\ClassIcon_Monk")
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture(136430)
  border:SetPoint("TOPLEFT")

  local function Place()
    local a = math.rad(settings.angle or 215)
    local r = Minimap:GetWidth() / 2 + 5
    b:ClearAllPoints()
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  end

  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      settings.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      Place()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then IRL.ToggleMain("Today") else IRL.ToggleMain() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("IRL Stats", 1, 1, 1)
    GameTooltip:AddLine("Left-click: goals and flags", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: today's check-ins", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)

  Place()
  b:SetShown(not settings.hide)
  IRL.minimapButton = b
end
