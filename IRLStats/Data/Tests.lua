-- Categories, the tests you can pick for each, and tooltip exercise lists.
--
-- Every category's picker leads with tests you can run alone with at most a
-- pull-up bar, the floor, a wall and a phone (timer, GPS or reaction app).
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
--   how     one-line self-test instructions, shown when logging a result
--   levels  skill ladders only: ordered level names, value = index
--   norm    key into Data/Norms.lua for 90th-percentile goal pre-fill
--   legacy  no longer offered in pickers; kept so saved data still displays
local _, IRL = ...

IRL.CategoryOrder = { "speed", "agility", "power", "body", "grip", "core", "conditioning", "mobility" }

IRL.Categories = {
  speed = {
    label = "Speed",
    tests = { "burpees60", "climbers30", "run1k" },
    exercises = { "Burpee intervals", "Sprint intervals", "A-skips" },
  },
  agility = {
    label = "Agility and reaction",
    tests = { "reaction", "linehops30", "skaters30" },
    exercises = { "Reaction drills (phone app)", "Line hops", "Skater jumps" },
  },
  power = {
    label = "Explosive power",
    tests = { "broadjump", "vertjump", "clappushups" },
    exercises = { "Squat jumps", "Broad jumps", "Clap push-ups" },
  },
  body = {
    label = "Body control",
    tests = { "lsit", "handstand", "planche", "frontlever" },
    exercises = { "Hollow holds", "Pike push-ups", "L-sit tucks", "Wall handstands" },
  },
  grip = {
    label = "Grip and pull",
    tests = { "deadhang", "pullups", "grip" },
    exercises = { "Dead hangs", "Towel hangs", "Pull-up negatives" },
  },
  core = {
    label = "Rotational core",
    tests = { "sideplank", "plank", "windshield" },
    exercises = { "Side planks", "Russian twists", "Hanging knee raises" },
  },
  conditioning = {
    label = "Conditioning",
    tests = { "pushups", "burpees3", "mile", "cooper", "vo2max" },
    exercises = { "30/30 intervals", "Burpee ladders", "Tempo runs" },
  },
  mobility = {
    label = "Mobility",
    tests = { "deepsquat", "pike", "frontsplit", "middlesplit" },
    exercises = { "Hip openers", "Cossack squats", "Split progressions" },
  },
}

IRL.Tests = {
  -- Speed
  burpees60  = { label = "Burpees in 1 minute", unit = "reps", phrase = "%s burpees in 1 minute",
                 how = "Set a 1-minute timer. Chest to floor, then jump with hands overhead. Count full reps." },
  climbers30 = { label = "Mountain climbers in 30 s", unit = "reps", phrase = "%s mountain climbers in 30 s",
                 how = "Set a 30-second timer in a push-up position. Count each time your left knee comes forward." },
  run1k      = { label = "1 km run (phone GPS)", unit = "seconds", lower = true, phrase = "a %s 1 km run",
                 how = "Run 1 km as fast as you can with a running app tracking it. Log the time." },

  -- Agility and reaction
  reaction   = { label = "Reaction time (phone or web app)", unit = "ms", lower = true, phrase = "a %s reaction time",
                 how = "Use a reaction-time app or site (e.g. humanbenchmark.com). Log the average of 5 tries." },
  linehops30 = { label = "Lateral line hops in 30 s", unit = "reps", phrase = "%s line hops in 30 s",
                 how = "Hop side to side over a line with feet together for 30 s. Count every crossing." },
  skaters30  = { label = "Skater jumps in 30 s", unit = "reps", phrase = "%s skater jumps in 30 s",
                 how = "Bound side to side, landing on one foot, for 30 s. Count every landing." },

  -- Explosive power
  broadjump   = { label = "Standing broad jump", unit = "jump", phrase = "a %s broad jump",
                  how = "Toes on a line, jump forward with both feet. Measure to your rearmost heel. Best of 3." },
  vertjump    = { label = "Vertical jump (wall reach)", unit = "jump", phrase = "a %s vertical jump", norm = "vertjump",
                  how = "Mark your standing reach on a wall, then jump and touch as high as you can. Log the difference. Best of 3." },
  clappushups = { label = "Max clap push-ups", unit = "reps", phrase = "%s clap push-ups",
                  how = "Push off hard enough to clap between reps. Stop at the first rep without a clap." },

  -- Body control (holds and skill ladders)
  lsit = { label = "L-sit hold", unit = "hold", phrase = "a %s L-sit",
           how = "Hands on the floor or two chairs, legs straight out, hips off the floor. Time until anything touches down." },
  planche = {
    label = "Planche progression", unit = "level", phrase = "%s",
    how = "Pick the hardest level you can hold for 5 seconds with good form.",
    levels = { "No planche work yet", "Frog stand", "Planche lean", "Tuck planche",
               "Advanced tuck planche", "Straddle planche", "Half-lay planche", "Full planche" },
  },
  handstand = {
    label = "Handstand progression", unit = "level", phrase = "%s",
    how = "Pick the hardest level you can do with good form.",
    levels = { "No handstand work yet", "Wall plank 30 s", "Chest-to-wall handstand 30 s",
               "Freestanding handstand 5 s", "Freestanding handstand 15 s",
               "Freestanding handstand 30 s", "Freestanding handstand 60 s",
               "Freestanding handstand push-up" },
  },
  frontlever = {
    label = "Front lever progression", unit = "level", phrase = "%s",
    how = "On the pull-up bar, pick the hardest level you can hold for 5 seconds.",
    levels = { "No front lever work yet", "Tuck front lever", "Advanced tuck front lever",
               "One-leg front lever", "Straddle front lever", "Half-lay front lever",
               "Full front lever" },
  },

  -- Grip and pull
  deadhang = { label = "Dead hang", unit = "hold", phrase = "a %s dead hang",
               how = "Hang from the pull-up bar with straight arms. Stop the timer when you let go." },
  pullups  = { label = "Max strict pull-ups", unit = "reps", phrase = "%s strict pull-ups",
               how = "From a dead hang, chin over the bar, no kipping. Count clean reps." },
  grip     = { label = "Grip strength (needs a dynamometer)", unit = "mass", phrase = "%s grip strength", norm = "grip",
               how = "Squeeze a hand dynamometer with your stronger hand. Best of 3." },

  -- Rotational core
  sideplank  = { label = "Side plank (weaker side)", unit = "hold", phrase = "a %s side plank",
                 how = "On your forearm, body in a straight line. Test both sides and log the weaker one." },
  plank      = { label = "Plank hold", unit = "hold", phrase = "a %s plank",
                 how = "On your forearms, body in a straight line. Stop when your hips sag or rise." },
  windshield = { label = "Hanging windshield wipers", unit = "reps", phrase = "%s windshield wipers",
                 how = "Hang from the bar and raise your legs toward it, then sweep side to side. Count each side touched." },

  -- Conditioning
  pushups  = { label = "Max push-ups", unit = "reps", phrase = "%s push-ups",
               how = "Chest to a fist's height off the floor, full lockout, no resting on the floor. Count clean reps." },
  burpees3 = { label = "Burpees in 3 minutes", unit = "reps", phrase = "%s burpees in 3 minutes",
               how = "Set a 3-minute timer and pace yourself. Count full burpees." },
  mile     = { label = "1 mile run (phone GPS)", unit = "seconds", lower = true, phrase = "a %s mile",
               how = "Run 1 mile at your best effort with a running app tracking it. Log the time." },
  cooper   = { label = "Cooper 12-minute run (phone GPS)", unit = "run", phrase = "%s in 12 minutes",
               how = "Run as far as you can in 12 minutes with a running app tracking it. Log the distance." },
  vo2max   = { label = "VO2max (watch estimate)", unit = "vo2", phrase = "a VO2max of %s", norm = "vo2max",
               how = "Read the VO2max estimate from your fitness watch or app." },

  -- Mobility (skill ladders)
  deepsquat = {
    label = "Squat depth", unit = "level", phrase = "%s",
    how = "Pick the deepest level you can hold for 30 seconds.",
    levels = { "Can't reach parallel", "Parallel, heels lifting", "Deep squat holding a support",
               "Deep squat 1 min unassisted", "Cossack squat both sides, heel down",
               "Deep Cossack with straight leg toes up" },
  },
  pike = {
    label = "Pike fold (standing)", unit = "level", phrase = "%s",
    how = "Stand with straight legs and fold forward. Pick the lowest level you reach.",
    levels = { "Fingertips to shins", "Fingertips to ankles", "Fingertips to toes", "Palms flat on floor",
               "Chest to thighs" },
  },
  frontsplit = {
    label = "Front split", unit = "level", phrase = "%s",
    how = "Slide into a front split with your weaker leg forward. Measure hips to floor.",
    levels = { "Front split: hips 30 cm+ off floor", "Front split: 20-30 cm off", "Front split: 10-20 cm off",
               "Front split: under 10 cm", "Flat front split", "Front oversplit (front foot on block)" },
  },
  middlesplit = {
    label = "Middle split", unit = "level", phrase = "%s",
    how = "Slide your feet apart with a straight torso. Estimate the angle between your legs.",
    levels = { "Middle split: under 90 degrees", "Middle split: 90-120 degrees", "Middle split: 120-150 degrees",
               "Middle split: 150-170 degrees", "Flat middle split", "Middle split with chest to floor" },
  },

  -- Legacy: hard to self-test solo, no longer offered.
  dash40     = { legacy = true, label = "40-yard dash", unit = "seconds", lower = true, phrase = "a %s 40-yard dash" },
  sprint100  = { legacy = true, label = "100 m sprint", unit = "seconds", lower = true, phrase = "a %s 100 m sprint" },
  sprint10   = { legacy = true, label = "10 m sprint", unit = "seconds", lower = true, phrase = "a %s 10 m sprint" },
  proagility = { legacy = true, label = "5-10-5 pro agility", unit = "seconds", lower = true, phrase = "a %s 5-10-5 shuttle" },
  ttest      = { legacy = true, label = "T-test", unit = "seconds", lower = true, phrase = "a %s T-test" },
  rotthrow   = { legacy = true, label = "Rotational med ball throw (4 kg)", unit = "throw", phrase = "a %s rotational med ball throw" },
  landmine   = { legacy = true, label = "Landmine rotation 5RM", unit = "mass", phrase = "a %s landmine rotation" },
  pallof     = { legacy = true, label = "Pallof press hold (per side)", unit = "hold", phrase = "a %s Pallof hold" },
  row2k      = { legacy = true, label = "2,000 m row", unit = "seconds", lower = true, phrase = "a %s 2,000 m row" },
}

-- Which way is better for a test.
function IRL.IsLowerBetter(testKey)
  local t = IRL.Tests[testKey]
  return t ~= nil and t.lower == true
end
