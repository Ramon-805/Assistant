-- Smoke test: loads every file in IRLStats.toc order against a mocked WoW
-- API and drives the real event flow (login, casts, talent walk, action bar
-- overlays, tooltips, UI tabs, wizard, prompts). It catches nil errors and
-- wiring mistakes; it does not replace testing in the game client.
--   lua5.1 tests/smoke.lua
date, time = os.date, os.time

------------------------------------------------------------------------
-- Mock widgets: any unknown method is a no-op; a few return real values.
------------------------------------------------------------------------
local allFrames = {}
local Mock = {}
local function NewWidget(kind, name)
  local w = { __kind = kind, __scripts = {}, __hooks = {}, __shown = kind ~= "Frame", __text = "", __name = name, __events = {} }
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

function Fire(frame, script, ...)
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
  NewTicker = function(_, fn) return {} end,
}
local function RunTimers()
  for _ = 1, 5 do
    local list = timers; timers = {}
    for _, fn in ipairs(list) do fn() end
  end
end

local SPELLS = {
  [101] = "Roll", [102] = "Tiger's Lust", [103] = "Rising Sun Kick", [104] = "Rushing Wind Kick",
  [105] = "Fortifying Brew", [106] = "Vivify", [107] = "Tiger Palm", [108] = "Tigereye Brew",
  [109] = "Strike of the Windlord",
}
C_Spell = {
  GetSpellName = function(id) return SPELLS[id] end,
  GetSpellTexture = function() return 1 end,
  GetOverrideSpell = function(id) if id == 103 then return 104 end return id end,
  GetSpellInfo = function(name) for _, n in pairs(SPELLS) do if n == name then return {} end end end,
}
local inCombat = false
function InCombatLockdown() return inCombat end
function UnitAffectingCombat() return inCombat end
function UnitClass() return "Monk", "MONK" end
function UnitName() return "Ray" end
function UnitLevel() return 12 end
C_SpecializationInfo = { GetSpecialization = function() return 3 end, GetSpecializationInfo = function() return 269 end }
local clock = 0
function GetTime() return clock end
function GetRealZoneText() return "Dornogal" end
function GetCursorPosition() return 0, 0 end
function HasAction(slot) return slot == 1 or slot == 2 or slot == 3 end
function GetActionInfo(slot)
  if slot == 1 then return "spell", 101 elseif slot == 2 then return "spell", 107 elseif slot == 3 then return "spell", 103 end
end
function GetMacroSpell() end
function PlaySound() end
function hooksecurefunc() end
function PanelTemplates_SetNumTabs() end
function PanelTemplates_SetTab() end
function GameTooltip_Hide() end
function tinsert(t, v) table.insert(t, v) end
function CreateFrame(kind, name, parent, template)
  local f = NewWidget(kind, name)
  if name then _G[name] = f end
  if template == "InputBoxTemplate" then f.__text = "" end
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
EventUtil = { ContinueOnAddOnLoaded = function(_, fn) end }
for i = 1, 12 do _G["ActionButton" .. i] = CreateFrame("CheckButton"); _G["ActionButton" .. i].action = i end

-- Talents: loadout with Tiger Palm (ungated), Strike of the Windlord (locked), Tigereye Brew rank 2
C_ClassTalents = {
  GetActiveConfigID = function() return 77 end,
  GetActiveHeroTalentSpec = function() return 900 end,
  GetHeroTalentSpecsForClassSpec = function() return { 900 } end,
}
local nodes = {
  [1] = { ID = 1, activeRank = 1, activeEntry = { entryID = 11 }, entryIDs = { 11 } },
  [2] = { ID = 2, activeRank = 1, activeEntry = { entryID = 12 }, entryIDs = { 12 } },
  [3] = { ID = 3, activeRank = 2, activeEntry = { entryID = 13 }, entryIDs = { 13 } },
}
local entrySpell = { [11] = 107, [12] = 109, [13] = 108 }
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 5 } } end,
  GetTreeNodes = function() return { 1, 2, 3 } end,
  GetNodeInfo = function(_, id) return nodes[id] end,
  GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
  GetDefinitionInfo = function(defID) return { spellID = entrySpell[defID] } end,
  GetSubTreeInfo = function() return { name = "Shado-Pan" } end,
}

------------------------------------------------------------------------
-- Load the addon
------------------------------------------------------------------------
local IRL = {}
for line in io.lines("IRLStats.toc") do
  if line:match("%.lua$") then
    local path = line:gsub("\\", "/")
    assert(loadfile(path))("IRLStats", IRL)
  end
end

local failures = 0
local function check(cond, msg)
  if cond then print("ok   " .. msg) else failures = failures + 1; print("FAIL " .. msg) end
end

FireEvent("ADDON_LOADED", "IRLStats")
FireEvent("PLAYER_LOGIN")
FireEvent("PLAYER_ENTERING_WORLD")
RunTimers()
check(IRL.enforced == true, "Windwalker monk is enforced")
check(IRL.state ~= nil, "state computed at login")

-- Wizard opens on first login; walk it with a profile and one category.
local wiz = _G.IRLStatsWizard
check(wiz and wiz:IsShown(), "setup wizard shown on first login")

-- Talent walk: locked Strike of the Windlord, Tigereye Brew rank 2, Shado-Pan
local names = {}
for _, f in ipairs(IRL.char.flags) do names[#names + 1] = f.name .. "/" .. f.kind end
local s = table.concat(names, ",")
check(s:find("Strike of the Windlord/talent") and s:find("Tigereye Brew/talent") and s:find("Shado%-Pan/talent"),
  "talent walk flags locked talents and hero tree: " .. s)
local n = #IRL.char.flags
IRL.CheckTalents()
check(#IRL.char.flags == n, "re-check with the same loadout writes no new flags")
nodes[1].activeEntry.entryID = 11; nodes[1].activeRank = 1; nodes[3].activeRank = 1
IRL.CheckTalents()
check(#IRL.char.flags == n + 3, "loadout change re-flags locked selections once")

-- Casts
local castFrame
for _, f in ipairs(allFrames) do if f.__events.UNIT_SPELLCAST_SUCCEEDED then castFrame = f end end
inCombat = true
n = #IRL.char.flags
castFrame.__scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 101)
check(#IRL.char.flags == n + 1 and IRL.char.flags[#IRL.char.flags].combat == true, "locked cast in combat writes a flag")
clock = clock + 10
castFrame.__scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 101)
check(#IRL.char.flags == n + 1, "same cast within 60 s writes nothing")
castFrame.__scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 107)
check(#IRL.char.flags == n + 1, "ungated spell is ignored")
issecretvalue = function(v) return v == 666 end
castFrame.__scripts.OnEvent(castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 666)
check(#IRL.char.flags == n + 1, "secret spellID is ignored without error")

-- Overlays: deferred in combat, applied after
IRL.RefreshOverlays()
FireEvent("PLAYER_REGEN_ENABLED")
inCombat = false
FireEvent("PLAYER_REGEN_ENABLED")
RunTimers()
check(IRL.LockedGateForSpell(101) ~= nil, "Roll button is locked")
check(IRL.LockedGateForSpell(107) == nil, "Tiger Palm button is not gated")
check(IRL.LockedGateForSpell(103) and IRL.LockedGateForSpell(103).name == "Rushing Wind Kick",
  "Rising Sun Kick button checks its Rushing Wind Kick override")

-- Tooltips
for _, fn in ipairs(tooltipPostCalls) do fn(GameTooltip, { id = 102 }) end
check(tooltipLines[1] and tooltipLines[1]:find("Set a test"), "locked tooltip explains the requirement: " .. tostring(tooltipLines[1]))

-- Complete setup through the wizard UI.
wiz.profile.age:SetText("34")
wiz.profile.weight:SetText("180")
Fire(wiz.next, "OnClick")
check(wiz.step == 1, "wizard advances past profile")
-- category 1 (speed): pick a test via its menu
Fire(wiz.category.test, "OnClick")
menuItems[1].cb()
check(wiz.category.how:GetText():find("^How: Set a 1%-minute timer"), "wizard shows how to self-test")
wiz.category.pr.edit:SetText("20")
wiz.category.goal.edit:SetText("30")
Fire(wiz.next, "OnClick")
check(wiz.step == 2, "wizard advances past speed: " .. tostring(wiz.error:GetText()))
-- skip the rest
for _ = 2, 8 do Fire(wiz.skip, "OnClick") end
check(IRL.db.setupDone and IRL.db.categories.speed.goal == 30 and IRL.db.profile.age == 34, "wizard saved profile and speed")
check(math.abs(IRL.db.profile.weight - 180 / 2.20462) < 0.01, "bodyweight stored in kg")

-- Main window tabs and PR logging
RunTimers()
local main = _G.IRLStatsFrame
check(main and main:IsShown(), "main window opens after setup")
for i = 1, 3 do Fire(main.Tabs[i], "OnClick") end
Fire(main.Tabs[1], "OnClick")
local goals = main.pages[1]
local speedRow = goals.rows[1]
Fire(speedRow.log, "OnClick")
local prompt = _G.IRLStatsPrompt
check(prompt.how:GetText():find("^How: "), "Log PR prompt shows how to self-test")
prompt.input.edit:SetText("22")
Fire(prompt.ok, "OnClick")
check(IRL.db.categories.speed.pr == 22, "Log PR via the Goals tab")
check(IRL.FindGate("Tiger's Lust").unlocked, "Tiger's Lust unlocked by the new PR")
check(speedRow.bar.text:GetText() == "Next: 24  (1/5)", "progress bar text: " .. speedRow.bar.text:GetText())
check(speedRow.pr:GetText() == "22", "PR column updated")

-- Today tab buttons
local today = main.pages[2]
IRL.ToggleMain("Today")
check(IRL.FindGate("Fortifying Brew").unlocked == false, "Fortifying Brew locked before check-in")
IRL.CheckIn()
check(IRL.FindGate("Fortifying Brew").unlocked, "check-in unlocks Fortifying Brew")
IRL.LogSession("pt")
IRL.LogSession("training")
IRL.ToggleMain("Flags")
check(main.pages[3].count:GetText():find("flags on Ray"), "flags tab header: " .. main.pages[3].count:GetText())

-- /irl verify: loadout path, view-only fallback, renamed ID
local function verifyOutput()
  chat = {}
  SlashCmdList.IRLSTATS("verify")
  return table.concat(chat, "\n")
end
local out = verifyOutput()
check(out:find("talents read from your talent loadout"), "verify reads the active loadout")
check(out:find("Not found: Chi Torpedo"), "verify lists names it can't find")
C_ClassTalents.GetActiveConfigID = function() return nil end
C_ClassTalents.InitializeViewLoadout = function() end
Constants = { TraitConsts = { VIEW_TRAIT_CONFIG_ID = -3 } }
out = verifyOutput()
check(out:find("a view%-only Windwalker tree"), "verify falls back to a view-only tree below level 10")
SPELLS[116841], SPELLS[102] = "Tiger's Dash", nil
out = verifyOutput()
check(out:find("Tiger's Lust: spell 116841 is now called \"Tiger's Dash\""), "verify reports a renamed spell ID")
SPELLS[116841], SPELLS[102] = nil, "Tiger's Lust"
C_Traits.GetConfigInfo = function() return nil end
out = verifyOutput()
check(out:find("nowhere"), "verify says when talent data is unavailable")

-- Slash commands
for _, cmd in ipairs({ "", "today", "flags", "checkin", "pt", "trained", "verify", "minimap", "help", "setup" }) do
  SlashCmdList.IRLSTATS(cmd)
end
check(true, "all slash commands run")
RunTimers()

print(failures == 0 and "\nsmoke OK" or ("\n" .. failures .. " smoke failures"))
os.exit(failures == 0 and 0 or 1)
