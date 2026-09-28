-- Monk (Windwalker) gate table. Keyed by English spell/talent name; the
-- addon matches casts, action buttons, tooltips and talents by resolving
-- their spellID to a name at runtime, so no hard-coded 12.1 IDs are needed.
-- Run /irl verify in game to check every name against your spellbook and
-- talent trees.
--
-- Order within a category = unlock order (earliest-needed first).
local _, IRL = ...

IRL.Gates = {
  speed        = { abilities = { "Tiger's Lust" } },
  agility      = { abilities = { "Roll", "Spear Hand Strike", "Paralysis", "Chi Torpedo" } },
  power        = { abilities = { "Flying Serpent Kick", "Strike of the Windlord" } },
  body         = {
    abilities = { "Lighter Than Air", "Zenith" },
    apex = { name = "Tigereye Brew", grants = { [3] = "Zenith Stomp" } },
  },
  grip         = { abilities = { "Touch of Death" } },
  core         = { abilities = { "Leg Sweep", "Spinning Crane Kick", "Whirling Dragon Punch" } },
  conditioning = { abilities = { "Fists of Fury" } },
  mobility     = { abilities = { "Rising Sun Kick", "Rushing Wind Kick" } },
}

IRL.SpecialGates = {
  habit    = { abilities = { "Fortifying Brew" } },
  pt       = { abilities = { "Vivify", "Expel Harm" } },
  training = { heroTree = "Shado-Pan" },
  balance  = {
    heroTree = "Conduit of the Celestials",
    -- Xuen, Niuzao, Yu'lon, Chi-Ji
    requires = { "speed", "grip", "mobility", "power" },
  },
}

-- Known spell IDs (pre-Midnight values; may have changed in 12.1). Used only
-- by /irl verify: an ID's name can be read whether or not you've learned the
-- spell, so this checks names at any level. If an ID now resolves to a
-- different name, verify prints it so the gate table can be corrected.
-- Gating itself never uses these: it matches the name of whatever you cast.
IRL.SpellIDHints = {
  ["Roll"] = 109132,
  ["Chi Torpedo"] = 115008,
  ["Tiger's Lust"] = 116841,
  ["Spear Hand Strike"] = 116705,
  ["Paralysis"] = 115078,
  ["Flying Serpent Kick"] = 101545,
  ["Strike of the Windlord"] = 392983,
  ["Touch of Death"] = 322109,
  ["Leg Sweep"] = 119381,
  ["Spinning Crane Kick"] = 101546,
  ["Whirling Dragon Punch"] = 152175,
  ["Fists of Fury"] = 113656,
  ["Rising Sun Kick"] = 107428,
  ["Fortifying Brew"] = 115203,
  ["Vivify"] = 116670,
  ["Expel Harm"] = 322101,
}
