-- Flying / Skyriding needs Mile Silver (any gate). Addons can't stop you
-- taking off, so this checks every couple of seconds and flags each flight
-- that starts before the key is earned.
local _, IRL = ...

local wasFlying = false

function IRL.CheckFlying()
  if not IRL.state or not IRL.enforced then return end
  local flying = IsFlying and IsFlying()
  if IRL.IsSecret(flying) then return end
  flying = flying and true or false
  if flying and not wasFlying and not IRL.state.flying then
    local _, keyText = IRL.Rules.FlyingAllowed(IRL.state.ctx)
    if IRL.AddFlag("Flying", "flight", keyText) then
      IRL.ShowWarning("Locked: Flying - needs " .. keyText)
    end
  end
  wasFlying = flying
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function() C_Timer.NewTicker(2, IRL.CheckFlying) end)
