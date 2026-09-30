-- The per-character flag log. Flags are append-only; the addon never
-- deletes them.
local _, IRL = ...

IRL.lastFlagAt = {}

local function inCombat()
  local c = UnitAffectingCombat and UnitAffectingCombat("player")
  if IRL.IsSecret(c) then c = nil end
  if c == nil and InCombatLockdown then c = InCombatLockdown() end
  return c == true
end

local function zoneText()
  local z = GetRealZoneText and GetRealZoneText()
  if z == nil or IRL.IsSecret(z) then return "" end
  return z
end

-- Record a flag. kind is "cast" or "talent". Casts are rate-limited per
-- name (Config.flagCooldown); talent flags are de-duplicated by the loadout
-- signature in Detect/Talents.lua instead. Returns true if a flag was written.
function IRL.AddFlag(name, kind, detail)
  if kind == "cast" then
    local now = GetTime()
    local last = IRL.lastFlagAt[name]
    if last and now - last < IRL.Config.flagCooldown then return false end
    IRL.lastFlagAt[name] = now
  end
  local flag = {
    t = IRL.Now(), name = name, kind = kind, detail = detail,
    zone = zoneText(), combat = inCombat(),
  }
  table.insert(IRL.char.flags, flag)
  IRL.Fire("FLAG_ADDED", flag)
  return true
end

-- Text for the on-screen warning / chat, e.g.
-- "Locked: Fists of Fury - needs Key: Push Silver (35 push-ups)".
function IRL.LockedMessage(gate)
  local missing = gate.missing or {}
  if #missing == 0 then return "Locked: " .. gate.name end
  local more = #missing > 1 and string.format(" (+%d more, see tooltip)", #missing - 1) or ""
  return "Locked: " .. gate.name .. " - needs " .. missing[1] .. more
end
