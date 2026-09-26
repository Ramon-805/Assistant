-- Formatting and parsing of test values. Values are stored canonically
-- (see Data/Tests.lua) and shown in the profile's unit system.
local _, IRL = ...

local Units = {}
IRL.Units = Units

local CM_PER_IN = 2.54
local M_PER_FT = 0.3048
local M_PER_MI = 1609.344
local LB_PER_KG = 2.20462

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Rounding precision in canonical units; milestone values snap to these.
Units.precision = {
  seconds = 0.01, ms = 1, jump = 1, throw = 0.1, run = 10, mass = 0.5, reps = 1, vo2 = 0.1, level = 1,
}

local function isImperial()
  local p = IRLStatsDB and IRLStatsDB.profile
  return not p or p.units ~= "metric"
end
Units.IsImperial = isImperial

function Units.Round(unit, v)
  local p = Units.precision[unit] or 0.01
  return math.floor(v / p + 0.5) * p
end

local function formatSeconds(v)
  if v >= 60 then
    local m = math.floor(v / 60)
    local s = v - m * 60
    return string.format("%d:%04.1f", m, s)
  end
  return string.format("%.2f s", v)
end

-- Short value, e.g. "4.95 s", "7 ft 6 in", "Tuck planche".
function Units.Format(testKey, v)
  if v == nil then return "--" end
  local test = IRL.Tests[testKey]
  local unit = test and test.unit or "seconds"
  if unit == "seconds" then
    return formatSeconds(v)
  elseif unit == "ms" then
    return string.format("%d ms", math.floor(v + 0.5))
  elseif unit == "jump" then
    if isImperial() then
      local inches = math.floor(v / CM_PER_IN + 0.5)
      local ft, inch = math.floor(inches / 12), inches % 12
      if ft == 0 then return string.format("%d in", inch) end
      return string.format("%d ft %d in", ft, inch)
    end
    return string.format("%d cm", math.floor(v + 0.5))
  elseif unit == "throw" then
    if isImperial() then return string.format("%.1f ft", v / M_PER_FT) end
    return string.format("%.1f m", v)
  elseif unit == "run" then
    if isImperial() then return string.format("%.2f mi", v / M_PER_MI) end
    return string.format("%d m", math.floor(v + 0.5))
  elseif unit == "mass" then
    if isImperial() then return string.format("%d lb", math.floor(v * LB_PER_KG + 0.5)) end
    return string.format("%.1f kg", v)
  elseif unit == "reps" then
    return string.format("%d", math.floor(v + 0.5))
  elseif unit == "vo2" then
    return string.format("%.1f", v)
  elseif unit == "level" then
    local levels = test.levels
    local i = math.floor(v + 0.5)
    return levels[i] or ("Level " .. i)
  end
  return tostring(v)
end

-- The requirement phrase, e.g. "a 7 ft 6 in broad jump".
function Units.Phrase(testKey, v)
  local test = IRL.Tests[testKey]
  local phrase = test and test.phrase or "%s"
  return string.format(phrase, Units.Format(testKey, v))
end

-- Hint shown next to an input box.
function Units.InputHint(testKey)
  local test = IRL.Tests[testKey]
  local unit = test and test.unit
  local imp = isImperial()
  if unit == "seconds" then return "seconds (or m:ss)"
  elseif unit == "ms" then return "milliseconds"
  elseif unit == "jump" then return imp and "inches, or 7'6\"" or "cm"
  elseif unit == "throw" then return imp and "feet" or "meters"
  elseif unit == "run" then return imp and "miles" or "meters"
  elseif unit == "mass" then return imp and "lb" or "kg"
  elseif unit == "reps" then return "reps"
  elseif unit == "vo2" then return "ml/kg/min"
  end
  return ""
end

-- Value as it should appear in an edit box (no unit suffix).
function Units.EditText(testKey, v)
  if v == nil then return "" end
  local unit = IRL.Tests[testKey].unit
  local imp = isImperial()
  if unit == "seconds" then
    if v >= 60 then return formatSeconds(v) end
    return string.format("%.2f", v)
  elseif unit == "jump" then
    return imp and string.format("%d", math.floor(v / CM_PER_IN + 0.5)) or string.format("%d", math.floor(v + 0.5))
  elseif unit == "throw" then
    return string.format("%.1f", imp and v / M_PER_FT or v)
  elseif unit == "run" then
    return imp and string.format("%.2f", v / M_PER_MI) or string.format("%d", math.floor(v + 0.5))
  elseif unit == "mass" then
    return imp and string.format("%d", math.floor(v * LB_PER_KG + 0.5)) or string.format("%.1f", v)
  elseif unit == "vo2" then
    return string.format("%.1f", v)
  end
  return string.format("%d", math.floor(v + 0.5))
end

-- Parse user text into a canonical value. Returns value or nil, error.
function Units.Parse(testKey, text)
  local test = IRL.Tests[testKey]
  if not test then return nil, "Pick a test first." end
  text = trim(tostring(text or ""))
  if text == "" then return nil, "Enter a value." end
  local unit = test.unit
  local imp = isImperial()
  local v

  if unit == "seconds" then
    local m, s = text:match("^(%d+):(%d+%.?%d*)$")
    if m then v = tonumber(m) * 60 + tonumber(s) else v = tonumber((text:gsub("%s*s$", ""))) end
  elseif unit == "jump" then
    if imp then
      local ft, inch = text:match("^(%d+)%s*['f][^%d]*(%d*%.?%d*)")
      if ft then
        v = (tonumber(ft) * 12 + (tonumber(inch) or 0)) * CM_PER_IN
      else
        local n = tonumber((text:gsub("%s*in.*$", ""):gsub("\"$", "")))
        v = n and n * CM_PER_IN
      end
    else
      v = tonumber((text:gsub("%s*cm$", "")))
    end
  elseif unit == "throw" then
    local n = tonumber((text:gsub("%s*[fm]t?$", "")))
    v = n and (imp and n * M_PER_FT or n)
  elseif unit == "run" then
    local n = tonumber((text:gsub("%s*mi?$", "")))
    v = n and (imp and n * M_PER_MI or n)
  elseif unit == "mass" then
    local n = tonumber((text:gsub("%s*[lk][bg]s?$", "")))
    v = n and (imp and n / LB_PER_KG or n)
  elseif unit == "level" then
    v = tonumber(text)
    if v and (v < 1 or v > #test.levels) then return nil, "Pick a level." end
  else
    v = tonumber((text:gsub("%s*%a+.*$", "")))
  end

  if not v then return nil, "Couldn't read that value (" .. Units.InputHint(testKey) .. ")." end
  if v <= 0 and unit ~= "level" then return nil, "Value must be above zero." end
  return v
end

-- Is value a at least as good as b for this test?
function Units.AtLeast(testKey, a, b)
  local eps = (Units.precision[IRL.Tests[testKey].unit] or 0.01) / 2
  if IRL.IsLowerBetter(testKey) then return a <= b + eps end
  return a >= b - eps
end

function Units.Better(testKey, a, b)
  if b == nil then return true end
  if IRL.IsLowerBetter(testKey) then return a < b end
  return a > b
end
