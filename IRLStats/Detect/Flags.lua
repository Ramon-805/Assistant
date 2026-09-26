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
-- "Locked: Tiger's Lust — next milestone 4.95 s 40-yard dash".
function IRL.LockedMessage(gate)
  local msg = "Locked: " .. gate.name
  if gate.kind == "milestone" or gate.kind == "apex" then
    local cs = IRL.state.categories[gate.category]
    local c = IRL.db.categories[gate.category]
    if cs and cs.nextValue and c and c.test then
      msg = msg .. " - next milestone " .. IRL.Units.Format(c.test, cs.nextValue) .. " "
        .. IRL.Tests[c.test].label:gsub(" %(.*%)$", "")
    end
  elseif gate.kind == "habit" then
    msg = msg .. " - do today's check-in (/irl)"
  elseif gate.kind == "pt" then
    msg = msg .. " - log a mobility/PT session (/irl)"
  elseif gate.kind == "unset" then
    msg = msg .. " - set up " .. IRL.Categories[gate.category].label:lower() .. " in /irl"
  end
  return msg
end
