-- Gymlocke (IRL Stats addon): namespace, config and small shared utilities.
-- The rules themselves live in Data/Rulebook.lua.
-- Everything in this file (and in Data/ and Core/) is plain Lua with no WoW
-- API calls, so it can be unit-tested outside the game (see tests/run.lua).
local ADDON, IRL = ...
IRL.name = ADDON or "IRLStats"

-- Version from the TOC (## Version), shown in the window title and /irl version.
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
IRL.version = (getMeta and getMeta(IRL.name, "Version")) or "dev"

IRL.Config = {
  flagCooldown = 60,      -- seconds; same locked spell flags at most once per window
  warningSound = true,
}

--------------------------------------------------------------------------
-- Secret values (Midnight). Never compare, index with, or tostring a value
-- before this says it is safe.
--------------------------------------------------------------------------
function IRL.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

--------------------------------------------------------------------------
-- Local calendar days. A day index is the day number of local noon, so DST
-- shifts never move a date across a boundary. Only differences between
-- indices matter.
--------------------------------------------------------------------------
function IRL.DayIndex(t)
  local d = date("*t", t)
  return math.floor(time({ year = d.year, month = d.month, day = d.day, hour = 12 }) / 86400)
end

function IRL.DayString(t)
  return date("%Y-%m-%d", t)
end

-- Overridable clock so tests can move time forward.
IRL.Now = function() return time() end
function IRL.Today() return IRL.DayIndex(IRL.Now()) end

--------------------------------------------------------------------------
-- Tiny event bus between modules.
--------------------------------------------------------------------------
IRL.listeners = {}
function IRL.On(event, fn)
  IRL.listeners[event] = IRL.listeners[event] or {}
  table.insert(IRL.listeners[event], fn)
end
function IRL.Fire(event, ...)
  local list = IRL.listeners[event]
  if not list then return end
  for i = 1, #list do list[i](...) end
end

function IRL.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Gymlocke|r: " .. tostring(msg))
  else
    print("IRL Stats: " .. tostring(msg))
  end
end

function IRL.CopyTable(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = IRL.CopyTable(v) end
  return out
end
