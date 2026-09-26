-- Categories, the tests you can pick for each, and tooltip exercise lists.
--
-- Values are stored in canonical units (seconds, cm, m, kg, reps, ms,
-- ml/kg/min, or a skill-ladder level) and converted for display by
-- Core/Units.lua according to the profile's imperial/metric setting.
--
-- Test fields:
--   label   shown in pickers and the Goals tab
--   unit    a unit type from Core/Units.lua
--   lower   true when lower is better (times)
--   phrase  requirement phrase; %s is the formatted value
--   levels  skill ladders only: ordered level names, value = index
--   norm    key into Data/Norms.lua for 90th-percentile goal pre-fill
local _, IRL = ...

IRL.CategoryOrder = { "speed", "agility", "power", "body", "grip", "core", "conditioning", "mobility" }

IRL.Categories = {
  speed = {
    label = "Speed",
    tests = { "dash40", "sprint100", "sprint10" },
    exercises = { "Sprint intervals", "Sled pushes", "A-skips" },
  },
  agility = {
    label = "Agility and reaction",
    tests = { "proagility", "ttest", "reaction" },
    exercises = { "Ladder drills", "Shuffle-to-sprint", "Partner ball drops" },
  },
  power = {
    label = "Explosive power",
    tests = { "broadjump", "vertjump" },
    exercises = { "Box jumps", "Depth jumps", "Trap bar jumps" },
  },
  body = {
    label = "Body control",
    tests = { "planche", "handstand", "frontlever" },
    exercises = { "Pull-ups", "Pike push-ups", "Hollow holds", "Bouldering" },
  },
  grip = {
    label = "Grip and pull",
    tests = { "grip", "deadhang", "pullups" },
    exercises = { "Farmer carries", "Towel hangs", "Heavy rows" },
  },
  core = {
    label = "Rotational core",
    tests = { "rotthrow", "landmine", "pallof" },
    exercises = { "Pallof press", "Cable chops", "Med ball slams" },
  },
  conditioning = {
    label = "Conditioning",
    tests = { "vo2max", "cooper", "row2k" },
    exercises = { "30/30 intervals", "Tempo runs" },
  },
  mobility = {
    label = "Mobility",
    tests = { "frontsplit", "middlesplit", "deepsquat", "pike" },
    exercises = { "Hip openers", "Cossack squats", "Split progressions" },
  },
}

IRL.Tests = {
  -- Speed
  dash40     = { label = "40-yard dash",   unit = "seconds", lower = true, phrase = "a %s 40-yard dash" },
  sprint100  = { label = "100 m sprint",   unit = "seconds", lower = true, phrase = "a %s 100 m sprint" },
  sprint10   = { label = "10 m sprint",    unit = "seconds", lower = true, phrase = "a %s 10 m sprint" },

  -- Agility and reaction
  proagility = { label = "5-10-5 pro agility", unit = "seconds", lower = true, phrase = "a %s 5-10-5 shuttle" },
  ttest      = { label = "T-test",             unit = "seconds", lower = true, phrase = "a %s T-test" },
  reaction   = { label = "Reaction time (click test)", unit = "ms", lower = true, phrase = "a %s reaction time" },

  -- Explosive power
  broadjump  = { label = "Standing broad jump", unit = "jump", phrase = "a %s broad jump" },
  vertjump   = { label = "Vertical jump",       unit = "jump", phrase = "a %s vertical jump", norm = "vertjump" },

  -- Body control (skill ladders)
  planche = {
    label = "Planche progression", unit = "level", phrase = "%s",
    levels = { "No planche work yet", "Frog stand", "Planche lean", "Tuck planche",
               "Advanced tuck planche", "Straddle planche", "Half-lay planche", "Full planche" },
  },
  handstand = {
    label = "Handstand progression", unit = "level", phrase = "%s",
    levels = { "No handstand work yet", "Wall plank 30 s", "Chest-to-wall handstand 30 s",
               "Freestanding handstand 5 s", "Freestanding handstand 15 s",
               "Freestanding handstand 30 s", "Freestanding handstand 60 s",
               "Freestanding handstand push-up" },
  },
  frontlever = {
    label = "Front lever progression", unit = "level", phrase = "%s",
    levels = { "No front lever work yet", "Tuck front lever", "Advanced tuck front lever",
               "One-leg front lever", "Straddle front lever", "Half-lay front lever",
               "Full front lever" },
  },

  -- Grip and pull
  grip     = { label = "Grip strength (best hand)", unit = "mass", phrase = "%s grip strength", norm = "grip" },
  deadhang = { label = "Dead hang",                 unit = "seconds", phrase = "a %s dead hang" },
  pullups  = { label = "Max strict pull-ups",       unit = "reps", phrase = "%s strict pull-ups" },

  -- Rotational core
  rotthrow = { label = "Rotational med ball throw (4 kg)", unit = "throw", phrase = "a %s rotational med ball throw" },
  landmine = { label = "Landmine rotation 5RM",            unit = "mass", phrase = "a %s landmine rotation" },
  pallof   = { label = "Pallof press hold (per side)",     unit = "seconds", phrase = "a %s Pallof hold" },

  -- Conditioning
  vo2max = { label = "VO2max (lab or watch estimate)", unit = "vo2", phrase = "a VO2max of %s", norm = "vo2max" },
  cooper = { label = "Cooper 12-minute run",           unit = "run", phrase = "%s in 12 minutes" },
  row2k  = { label = "2,000 m row",                    unit = "seconds", lower = true, phrase = "a %s 2,000 m row" },

  -- Mobility (skill ladders)
  frontsplit = {
    label = "Front split", unit = "level", phrase = "%s",
    levels = { "Front split: hips 30 cm+ off floor", "Front split: 20-30 cm off", "Front split: 10-20 cm off",
               "Front split: under 10 cm", "Flat front split", "Front oversplit (front foot on block)" },
  },
  middlesplit = {
    label = "Middle split", unit = "level", phrase = "%s",
    levels = { "Middle split: under 90 degrees", "Middle split: 90-120 degrees", "Middle split: 120-150 degrees",
               "Middle split: 150-170 degrees", "Flat middle split", "Middle split with chest to floor" },
  },
  deepsquat = {
    label = "Squat depth", unit = "level", phrase = "%s",
    levels = { "Can't reach parallel", "Parallel, heels lifting", "Deep squat holding a support",
               "Deep squat 1 min unassisted", "Cossack squat both sides, heel down",
               "Deep Cossack with straight leg toes up" },
  },
  pike = {
    label = "Pike fold (standing)", unit = "level", phrase = "%s",
    levels = { "Fingertips to shins", "Fingertips to ankles", "Fingertips to toes", "Palms flat on floor",
               "Chest to thighs" },
  },
}

-- Which way is better for a test.
function IRL.IsLowerBetter(testKey)
  local t = IRL.Tests[testKey]
  return t ~= nil and t.lower == true
end
