-- Smoke test: loads every file in IRLStats.toc order against a mocked WoW
-- API and drives the real flow: login, talent-tree reading (sections,
-- capstone, apex, hero), the Test Day wizard, casts, a failed retest,
-- flying, tabs, tooltips and slash commands. It catches nil errors and
-- wiring mistakes; it does not replace testing in the game client.
--   lua5.1 tests/smoke.lua
date, time = os.date, os.time

------------------------------------------------------------------------
-- Mock widgets: unknown methods are no-ops; a few return real values.
------------------------------------------------------------------------
local allFrames = {}
local Mock = {}
local function NewWidget(kind, name)
  local w = { __kind = kind, __scripts = {}, __hooks = {}, __shown = kind ~= "Frame", __text = "",
              __name = name, __events = {}, __checked = false }
  table.insert(allFrames, w)
  return setmetatable(w, Mock)
end
local methods = {
  SetText = function(self, t) self.__text = t end,
  GetText = function(self) return self.__text end,
  SetScript = function(self, s, fn) self.__scripts[s] = fn end,
  GetScript = function(self, s) return self.__scripts[s] end,
  HookScript = function(self, s, fn) self.__hooks[s] = self.__hooks[s] or {}; table.insert(self.__hooks[s], fn) end,
  Show = function(self) self.__shown = true; local f = self.__scripts.OnShow; if f then f(self) end end,
  Hide = function(self) self.__shown = false end,
  SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
  IsShown = function(self) return self.__shown end,
  IsVisible = function(self) return self.__shown end,
  SetChecked = function(self, v) self.__checked = v and true or false end,
  GetChecked = function(self) return self.__checked end,
  CreateTexture = function() return NewWidget("Texture") end,
  CreateFontString = function() return NewWidget("FontString") end,
  GetStringHeight = function() return 12 end,
  GetWidth = function() return 140 end,
  GetCenter = function() return 0, 0 end,
  GetEffectiveScale = function() return 1 end,
  IsOwned = function() return true end,
  GetName = function(self) return self.__name end,
  RegisterEvent = function(self, e) self.__events[e] = true end,
  RegisterUnitEvent = function(self, e) self.__events[e] = true end,
  GetAttribute = function() return nil end,
}
-- Unknown methods (Capitalized) are no-ops; unknown fields are nil, as on real frames.
Mock.__index = function(_, k)
  if methods[k] then return methods[k] end
  if type(k) == "string" and k:match("^%u") then return function() end end
end

local function Fire(frame, script, ...)
  if frame.__scripts[script] then frame.__scripts[script](frame, ...) end
  for _, fn in ipairs(frame.__hooks[script] or {}) do fn(frame, ...) end
end
local function FireEvent(event, ...)
  for _, f in ipairs(allFrames) do
    if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
end

------------------------------------------------------------------------
-- Mock API
------------------------------------------------------------------------
local timers = {}
C_Timer = {
  After = function(_, fn) table.insert(timers, fn) end,
  NewTicker = function() return {} end,
}
local function RunTimers()
  for _ = 1, 6 do
    local list = timers; timers = {}
    for _, fn in ipairs(list) do fn() end
  end
end

local SPELLS = {
  [107] = "Tiger Palm", [113656] = "Fists of Fury", [900] = "Big Capstone", [108] = "Tigereye Brew",
  [901] = "Flurry Strikes", [101643] = "Transcendence", [116841] = "Tiger's Lust",
}
C_Spell = {
  GetSpellName = function(id) return SPELLS[id] end,
  GetSpellTexture = function() return 1 end,
  GetOverrideSpell = function(id) return id end,
  GetSpellInfo = function(name) for _, n in pairs(SPELLS) do if n == name then return {} end end end,
}
local inCombat, flying, level = false, false, 90
function InCombatLockdown() return inCombat end
function UnitAffectingCombat() return inCombat end
function UnitClass() return "Monk", "MONK" end
function UnitName() return "Sportacus" end
function UnitLevel() return level end
function IsFlying() return flying end
C_SpecializationInfo = { GetSpecialization = function() return 3 end, GetSpecializationInfo = function() return 269 end }
local clock = 0
function GetTime() return clock end
function GetRealZoneText() return "Dornogal" end
function GetCursorPosition() return 0, 0 end
function HasAction(slot) return slot == 1 or slot == 2 end
function GetActionInfo(slot)
  if slot == 1 then return "spell", 113656 elseif slot == 2 then return "spell", 101643 end
end
function GetMacroSpell() end
function PlaySound() end
function hooksecurefunc() end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function GameTooltip_Hide() end
function tinsert(t, v) table.insert(t, v) end
function CreateFrame(kind, name)
  local f = NewWidget(kind, name)
  if name then _G[name] = f end
  return f
end
SOUNDKIT = { RAID_WARNING = 1 }
Enum = { TooltipDataType = { Spell = 1 }, TraitNodeType = { SubTreeSelection = 3 } }
local tooltipPostCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) table.insert(tooltipPostCalls, fn) end }
local tooltipLines = {}
UIParent, Minimap = NewWidget("Frame"), NewWidget("Frame")
GameTooltip = NewWidget("GameTooltip")
function GameTooltip:AddLine(t) table.insert(tooltipLines, t) end
ItemRefTooltip = NewWidget("GameTooltip")
UISpecialFrames = {}
SlashCmdList = {}
local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(chat, m) end }
local menuItems
MenuUtil = { CreateContextMenu = function(owner, gen)
  menuItems = {}
  local root; root = {
    CreateTitle = function() end,
    CreateButton = function(_, text, cb) table.insert(menuItems, { text = text, cb = cb }); return root end,
  }
  gen(owner, root)
end }
EventUtil = { ContinueOnAddOnLoaded = function() end }
for i = 1, 12 do _G["ActionButton" .. i] = CreateFrame("CheckButton"); _G["ActionButton" .. i].action = i end

-- A small Windwalker tree. Currency 1 = class, 2 = spec. Section gates start
-- at nodes 2 (y 1300) and 3 (y 2600) on the spec side.
local nodes = {
  [1] = { ID = 1, posY = 100,  cur = 1, activeRank = 1, maxRanks = 1, entry = 11, spell = 107 },    -- class top
  [2] = { ID = 2, posY = 1300, cur = 2, activeRank = 1, maxRanks = 1, entry = 12, spell = 113656 }, -- spec middle, keyed
  [3] = { ID = 3, posY = 2600, cur = 2, activeRank = 1, maxRanks = 1, entry = 13, spell = 900 },    -- spec bottom row
  [4] = { ID = 4, posY = 3000, cur = 2, activeRank = 2, maxRanks = 4, entry = 14, spell = 108 },    -- apex
  [5] = { ID = 5, posY = 100,  activeRank = 1, maxRanks = 1, entry = 15, spell = 901, subTreeID = 50, subTreeActive = true },
}
for _, n in pairs(nodes) do n.activeEntry = { entryID = n.entry }; n.entryIDs = { n.entry } end
local entrySpell = {}
for _, n in pairs(nodes) do entrySpell[n.entry] = n.spell end
C_ClassTalents = {
  GetActiveConfigID = function() return 77 end,
  GetActiveHeroTalentSpec = function() return 50 end,
  GetHeroTalentSpecsForClassSpec = function() return { 50 } end,
}
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 5 } } end,
  GetTreeNodes = function() return { 1, 2, 3, 4, 5 } end,
  GetNodeInfo = function(_, id) return nodes[id] end,
  GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
  GetDefinitionInfo = function(defID) return { spellID = entrySpell[defID] } end,
  GetSubTreeInfo = function() return { name = "Shado-Pan" } end,
  GetTreeInfo = function() return { gates = { { topLeftNodeID = 2 }, { topLeftNodeID = 3 } } } end,
  GetNodeCost = function(_, id) return nodes[id].cur and { { ID = nodes[id].cur, amount = 1 } } or {} end,
  GetTreeCurrencyInfo = function() return { { traitCurrencyID = 1 }, { traitCurrencyID = 2 } } end,
}

------------------------------------------------------------------------
-- Load the addon
------------------------------------------------------------------------
local IRL = {}
for line in io.lines("IRLStats.toc") do
  if line:match("%.lua$") then assert(loadfile((line:gsub("\\", "/"))))("IRLStats", IRL) end
end

local failures = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else failures = failures + 1; print("FAIL " .. msg) end
end
local function flagNames(from)
  local out = {}
  for i = (from or 1), #IRL.char.flags do
    local f = IRL.char.flags[i]
    out[#out + 1] = f.name .. "/" .. f.kind
  end
  return table.concat(out, ",")
end

FireEvent("ADDON_LOADED", "IRLStats")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")
RunTimers()
check(IRL.enforced, "Windwalker monk is enforced")

-- Tree reading
local m = IRL.nodeMetaByID
check(m[1].section == 1 and not m[1].isSpec, "class node in the top section")
check(m[2].section == 2 and m[2].isSpec, "spec node below the first gate is in the middle section")
check(m[3].section == 3 and m[3].isCapstone, "bottom spec row is section 3 and a capstone")
check(m[4].isApex and not m[4].isCapstone, "4-rank Tigereye Brew is the apex, not a capstone")
check(m[5].heroTree == "Shado-Pan" and m[5].isHeroFinal, "hero node knows its tree and final row")

-- Before Test Day every selection is locked.
local s = flagNames()
check(s:find("Tiger Palm/talent") and s:find("Fists of Fury/talent") and s:find("Big Capstone/talent")
  and s:find("Tigereye Brew/talent") and s:find("Flurry Strikes/talent"), "pre-Test-Day loadout flags: " .. s)
local n = #IRL.char.flags
IRL.CheckTalents()
check(#IRL.char.flags == n, "re-check of the same loadout writes nothing")

-- Test Day wizard
local wiz = _G.IRLStatsWizard
check(wiz and wiz:IsShown(), "Test Day wizard opens at login")
Fire(wiz.next, "OnClick") -- past the intro
check(wiz.step == 2, "wizard on Pull")
local page = wiz.page
local tiers = { pull = 2, push = 2, press = 2, legs = 2, core = 1, flex = 2 }
page.input:SetValue(tiers.pull + 1)
Fire(wiz.next, "OnClick")
check(wiz.step == 2 and wiz.error:GetText():find("No video"), "no video, no credit")
page.video:SetChecked(true)
Fire(wiz.next, "OnClick")
for i = 2, 6 do
  local key = IRL.DisciplineOrder[i]
  page.input:SetValue(tiers[key] + 1)
  page.video:SetChecked(true)
  Fire(wiz.next, "OnClick")
end
check(wiz.step == 8 and page.heading:GetText():find("Reaction"), "wizard reaches reaction time")
Fire(wiz.skip, "OnClick")
page.input.edit:SetText("8:00")
page.video:SetChecked(true)
local beforeFinish = #IRL.char.flags
Fire(wiz.next, "OnClick")
RunTimers()
check(not wiz:IsShown(), "wizard finishes")
check(IRL.Rules.TestDayDone(IRL.db) and IRL.db.disciplines.core.tier == 1, "Test Day logged")
check(IRL.db.supports.mile.baseline == 480, "mile baseline 8:00")
check(IRL.state.rank == 2, "rank Adept (Silver in 5)")
check(IRL.FindGate("Fists of Fury").unlocked, "Fists of Fury unlocked (Gate 1 + Push Silver)")
check(not IRL.FindGate("Transcendence").unlocked, "Transcendence locked (Mile Bronze)")

-- Finishing re-judged the loadout: only the still-locked ones flag again.
s = flagNames(beforeFinish + 1)
check(not s:find("Fists of Fury") and s:find("Big Capstone") and s:find("Tigereye Brew") and s:find("Flurry Strikes"),
  "post-Test-Day flags: " .. s)

-- Casts
local castFrame
for _, f in ipairs(allFrames) do if f.__events.UNIT_SPELLCAST_SUCCEEDED then castFrame = f end end
local function cast(id) castFrame.__scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "g", id) end
inCombat = true
n = #IRL.char.flags
cast(113656)
check(#IRL.char.flags == n, "unlocked Fists of Fury cast writes nothing")
cast(101643)
check(#IRL.char.flags == n + 1, "locked Transcendence cast writes a flag")
clock = clock + 10
cast(101643)
check(#IRL.char.flags == n + 1, "repeat within 60 s writes nothing")
issecretvalue = function(v) return v == 666 end
cast(666)
check(#IRL.char.flags == n + 1, "secret spellID ignored")
inCombat = false

-- Overlays and tooltips
check(IRL.LockedGateForSpell(101643) ~= nil and IRL.LockedGateForSpell(113656) == nil, "action bar lock check")
for _, fn in ipairs(tooltipPostCalls) do fn(GameTooltip, { id = 101643 }) end
local tip = table.concat(tooltipLines, "|")
check(tip:find("Gymlocke: Locked") and tip:find("needs: Key: Mile run Silver"), "tooltip lists unmet key: " .. tip)

-- Main window
local main = _G.IRLStatsFrame
check(main and main:IsShown(), "main window opens on the Rank tab after Test Day")
local rank = main.pages[1]
check(rank.rank:GetText():find("Adept"), "rank tab shows Adept")
check(rank.gates[3].status:GetText():find("OPEN"), "Gate 3 row shows OPEN")
check(rank.next:GetText():find("Master"), "next rank shown: " .. rank.next:GetText())
Fire(main.Tabs[2], "OnClick")
local disc = main.pages[2]
check(disc.rows[1].tier:GetText():find("Silver"), "Pull row shows Silver")
check(disc.rows[1].keys:GetText():find("Strike of the Windlord"), "Pull row lists what it keys")

-- Failed retest through the Log test dialog
Fire(disc.rows[1].log, "OnClick")
local prompt = _G.IRLStatsPrompt
prompt.input:SetValue(2) -- Bronze
Fire(prompt.ok, "OnClick")
check(prompt.error:GetText():find("No video"), "log dialog requires the video checkbox")
prompt.video:SetChecked(true)
Fire(prompt.ok, "OnClick")
check(IRL.db.disciplines.pull.tier == 1, "Pull dropped to Bronze")
check(disc.rows[1].retest:GetText():find("Lost Silver"), "retry window shown: " .. disc.rows[1].retest:GetText())
check(not IRL.FindGate("Strike of the Windlord").unlocked, "Strike of the Windlord relocked")

-- Flying: flagged until Mile Silver
flying = true
IRL.CheckFlying()
check(flagNames(#IRL.char.flags):find("Flying/flight"), "flight before Mile Silver is flagged")
flying = false; IRL.CheckFlying()
IRL.LogSupport("mile", 450)
flying = true
n = #IRL.char.flags
IRL.CheckFlying()
check(#IRL.char.flags == n, "flight after Mile Silver is fine")
flying = false

-- Flags tab
Fire(main.Tabs[3], "OnClick")
check(main.pages[3].count:GetText():find("flags on Sportacus"), "flags tab header")

-- Slash commands
for _, cmd in ipairs({ "", "rank", "disciplines", "flags", "verify", "minimap", "help", "testday" }) do
  SlashCmdList.IRLSTATS(cmd)
end
RunTimers()
check(true, "all slash commands run")

print(failures == 0 and "\nsmoke OK" or ("\n" .. failures .. " smoke failures"))
os.exit(failures == 0 and 0 or 1)
