-- Loggable tests, in the shape Core/Units.lua and the input widgets use.
--   d_<discipline>  landmark disciplines: a skill ladder (value 1 = not yet
--                   Bronze, 2..5 = Bronze..Legendary); measured disciplines:
--                   reps or seconds held
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

for _, rbKey in ipairs(IRL.RulebookOrder) do
  local rb = IRL.Rulebooks[rbKey]
  for _, key in ipairs(rb.disciplineOrder) do
    local d = rb.disciplines[key]
    if d.scale == "percent" then
      IRL.Tests["d_" .. key] = {
        label = d.measure, unit = d.unit, lower = d.lower, phrase = d.phrase,
        how = d.form .. " Equipment: " .. d.equipment .. ".",
      }
    else
      local levels = { "Not yet Bronze" }
      for i, text in ipairs(d.tiers) do levels[i + 1] = IRL.Tiers[i] .. ": " .. text end
      IRL.Tests["d_" .. key] = {
        label = d.label, unit = "level", phrase = "%s", levels = levels,
        how = d.form .. " Equipment: " .. d.equipment .. ".",
      }
    end
  end
end

function IRL.IsLowerBetter(testKey)
  local t = IRL.Tests[testKey]
  return t ~= nil and t.lower == true
end
