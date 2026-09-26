-- 90th-percentile norms used to pre-fill goals in the setup wizard.
-- Each list is { minimum age, value } in ascending age order; the last band
-- whose minimum age is <= your age applies.
--
-- IMPORTANT: these values were transcribed approximately and must be checked
-- against the sources before relying on them (see the build spec's open
-- questions). The wizard labels them as approximate and they are editable.
--   vertjump  cm          Canadian Health Measures Survey (ages 8-69)
--   grip      kg          International handgrip norms (Tomkinson et al., 2.4M adults, 69 countries)
--   vo2max    ml/kg/min   FRIEND registry, treadmill
local _, IRL = ...

IRL.Norms = {
  vertjump = {
    male   = { { 8, 30 }, { 10, 36 }, { 12, 44 }, { 15, 60 }, { 20, 63 }, { 30, 57 }, { 40, 51 }, { 50, 44 }, { 60, 37 } },
    female = { { 8, 28 }, { 10, 33 }, { 12, 38 }, { 15, 43 }, { 20, 43 }, { 30, 38 }, { 40, 33 }, { 50, 28 }, { 60, 23 } },
    maxAge = 69,
  },
  grip = {
    male   = { { 18, 56 }, { 20, 60 }, { 30, 61 }, { 40, 59 }, { 50, 55 }, { 60, 49 }, { 70, 42 }, { 80, 35 } },
    female = { { 18, 36 }, { 20, 37 }, { 30, 38 }, { 40, 37 }, { 50, 34 }, { 60, 30 }, { 70, 26 }, { 80, 21 } },
  },
  vo2max = {
    male   = { { 20, 61.8 }, { 30, 56.5 }, { 40, 52.1 }, { 50, 45.6 }, { 60, 40.3 }, { 70, 36.6 } },
    female = { { 20, 51.3 }, { 30, 41.4 }, { 40, 38.4 }, { 50, 32.0 }, { 60, 27.0 }, { 70, 23.1 } },
  },
}

-- Returns the 90th-percentile value for a test, or nil when there is no norm
-- for this test, sex or age.
function IRL.NormFor(testKey, age, sex)
  local test = IRL.Tests[testKey]
  if not test or not test.norm or type(age) ~= "number" then return nil end
  local norm = IRL.Norms[test.norm]
  local bands = norm and norm[sex]
  if not bands then return nil end
  if norm.maxAge and age > norm.maxAge then return nil end
  local value
  for i = 1, #bands do
    if age >= bands[i][1] then value = bands[i][2] end
  end
  return value
end
