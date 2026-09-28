-- IRL Stats: namespace, tunable config and small shared utilities.
-- Everything in this file (and in Data/ and Core/) is plain Lua with no WoW
-- API calls, so it can be unit-tested outside the game (see tests/run.lua).
local ADDON, IRL = ...
IRL.name = ADDON or "IRLStats"

IRL.Config = {
  -- Step per milestone, by category. Percent steps are applied to the
  -- baseline in the "better" direction (up for higher-is-better tests, down
  -- for times). Skill ladders (body control, mobility) always step one level.
  steps = {
    speed        = 0.015,
    agility      = 0.015,
    power        = 0.05,
    body         = 1,
    grip         = 0.10,
    core         = 0.10,
    conditioning = 0.05,
    mobility     = 1,
  },
  -- Rep counts and timed holds climb faster than times and distances, so
  -- they use this step instead of the category's.
  countStep = 0.10,
  reservedTopRungs = 3,   -- gates sit below these; apex ranks sit on them
  maxRungs = 30,          -- far-away goals get bigger steps rather than 100 rungs
  flagCooldown = 60,      -- seconds; same locked spell flags at most once per window
  maxStrikes = 3,         -- third missed day ends a streak
  exercisesShown = 3,     -- exercises listed in a locked tooltip
  warningSound = true,
  -- Build 1 is Windwalker only. These specs are never enforced so a
  -- Brewmaster or Mistweaver alt isn't flagged before its gate table exists.
  -- Low-level monks without a spec (and the "initial" spec) are enforced.
  exemptSpecs = { [268] = true, [270] = true },
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
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99IRL Stats|r: " .. tostring(msg))
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
