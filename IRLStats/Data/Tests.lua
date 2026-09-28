-- Loggable tests, in the shape Core/Units.lua and the input widgets use.
--   d_<discipline>  skill ladder: value 1 = not yet Bronze, 2..5 = Bronze..Legendary
--   mile, reaction  supporting tests, lower is better
local _, IRL = ...

IRL.Tests = {
  mile = {
    label = "Mile run", unit = "seconds", lower = true, phrase = "a %s mile",
    how = "Same flat route every time, phone GPS or watch. Same time of day and warm-up.",
  },
  reaction = {
    label = "Reaction time", unit = "ms", lower = true, phrase = "a %s reaction time",
    how = "Average of 5 attempts on humanbenchmark.com.",
  },
}

for _, key in ipairs(IRL.DisciplineOrder) do
  local d = IRL.Disciplines[key]
  local levels = { "Not yet Bronze" }
  for i, text in ipairs(d.tiers) do levels[i + 1] = IRL.Tiers[i] .. ": " .. text end
  IRL.Tests["d_" .. key] = {
    label = d.label, unit = "level", phrase = "%s", levels = levels,
    how = d.form .. " Equipment: " .. d.equipment .. ".",
  }
end

function IRL.IsLowerBetter(testKey)
  local t = IRL.Tests[testKey]
  return t ~= nil and t.lower == true
end
