-- Streaks with strikes (pure functions). Shape:
--   { current = 0, strikes = 0, best = 0, last = "YYYY-MM-DD", lastDay = <day index> }
-- Each full calendar day without a session adds a strike; the Nth strike
-- (Config.maxStrikes) ends the streak. Strikes are "lives" used over a
-- streak's lifetime and are only reset when a dead streak restarts. Strikes
-- are derived lazily from lastDay, so nothing needs to run at midnight.
local _, IRL = ...

local S = {}
IRL.Streaks = S

function S.New()
  return { current = 0, strikes = 0, best = 0 }
end

-- Returns alive, current count, strikes used (capped at max).
function S.Evaluate(streak, today, maxStrikes)
  maxStrikes = maxStrikes or 3
  if not streak or not streak.lastDay then return false, 0, 0 end
  local missed = math.max(0, today - streak.lastDay - 1)
  local strikes = (streak.strikes or 0) + missed
  if strikes >= maxStrikes then return false, 0, maxStrikes end
  return true, streak.current or 0, strikes
end

-- Record a session today. Returns true if anything changed.
function S.Log(streak, today, dayString, maxStrikes)
  if streak.lastDay == today then return false end
  local alive, _, strikes = S.Evaluate(streak, today, maxStrikes)
  if alive then
    streak.current = (streak.current or 0) + 1
    streak.strikes = strikes
  else
    streak.current = 1
    streak.strikes = 0
  end
  streak.lastDay = today
  streak.last = dayString
  if streak.current > (streak.best or 0) then streak.best = streak.current end
  return true
end
