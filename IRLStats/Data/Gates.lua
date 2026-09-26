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
