-- AscensionSuite: tests/test_desired_sync.lua
-- Desired marks made in Ascension's own windows reach the Suite wishlist, and
-- the Character Advancement hook marks without touching learn / unlearn / lock.

unpack = unpack or table.unpack

local function RepoRoot()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local dir = src:match("^(.*)/")
    if dir and dir:match("/tests$") then
        return dir:gsub("/tests$", "")
    end
    return "."
end

local ROOT = RepoRoot()

AscensionSuite = {}
AscensionSuiteDB = {}

------------------------------------------------------------------------
-- Client stubs
------------------------------------------------------------------------

local frames = {}

local function NewFrame()
    local frame = { _events = {}, _scripts = {}, _shown = true }

    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end

    frames[#frames + 1] = frame
    return frame
end

CreateFrame = function() return NewFrame() end

local function FireEvent(event, ...)
    for index = 1, #frames do
        local frame = frames[index]
        if frame._events[event] and frame._scripts.OnEvent then
            frame._scripts.OnEvent(frame, event, ...)
        end
    end
end

local function PumpUpdates()
    for index = 1, #frames do
        local frame = frames[index]
        if frame._shown and frame._scripts.OnUpdate then
            frame._scripts.OnUpdate(frame, 0.1)
        end
    end
end

-- Both call shapes the addon uses: hooksecurefunc("Global", fn) and
-- hooksecurefunc(table, "method", fn), post-hooks that keep the original body.
function hooksecurefunc(arg1, arg2, arg3)
    local host, name, hook
    if type(arg1) == "table" then
        host, name, hook = arg1, arg2, arg3
    else
        host, name, hook = _G, arg1, arg2
    end

    local original = host[name]
    assert(type(original) == "function", "cannot hook missing " .. tostring(name))
    host[name] = function(...)
        local results = { original(...) }
        hook(...)
        return unpack(results)
    end
end

local clock = 1000
function GetTime() return clock end

local altDown = false
function IsAltKeyDown() return altDown end

local menuCloses = 0
function CloseDropDownMenus() menuCloses = menuCloses + 1 end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }

function GetSpellInfo(spellId)
    return "Spell " .. tostring(spellId), "Rank 1", "Interface\\Icons\\Test"
end

------------------------------------------------------------------------
-- Advancement data
------------------------------------------------------------------------

-- 2004 is a deliberate id-space collision: an entry whose internal ID is also
-- another entry's spell ID. Resolving it the wrong way round silently tracks the
-- wrong spell.
local ENTRIES = {
    [2001] = { ID = 2001, Type = "Ability", Spells = { 133 }, Name = "Fireball" },
    [2002] = { ID = 2002, Type = "Talent", Spells = { 116 }, Name = "Ice Block" },
    [2003] = { ID = 2003, Type = "Ability", Spells = { 118 }, Name = "Polymorph" },
    [2004] = { ID = 2004, Type = "Ability", Spells = { 5143 }, Name = "Arcane Missiles" },
    [2005] = { ID = 2005, Type = "Ability", Spells = { 2004 }, Name = "Decoy" },
}

local BY_SPELL = {}
for _, entry in pairs(ENTRIES) do
    BY_SPELL[entry.Spells[1]] = entry
end

-- Filter order of the Rapid window's Desired *candidate* list. Being a candidate
-- says nothing about being selected: only IsDesiredID answers that.
local candidates = { ENTRIES[2001], ENTRIES[2002], ENTRIES[2003] }
local desired = {}
local scans = 0

local function Key(entryId, entryType)
    return tostring(entryId) .. "/" .. tostring(entryType)
end

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

-- Counters for the destructive calls the book hook must never make.
local lockCalls = 0
local unlearnCalls = 0

C_CharacterAdvancement = {
    GetEntryByInternalID = function(_, id) return ENTRIES[id] end,
    GetEntryBySpellID = function(_, id) return BY_SPELL[id] end,
    LockID = function() lockCalls = lockCalls + 1 end,
    UnlockID = function() lockCalls = lockCalls + 1 end,
    UnlearnID = function() unlearnCalls = unlearnCalls + 1 end,
}

C_Wildcard = {
    GetNumFilteredDesiredEntries = function()
        scans = scans + 1
        return #candidates
    end,
    GetFilteredDesiredEntryAtIndex = function(_, index) return candidates[index] end,
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, id, entryType)
        return desired[Key(id, entryType)] == true
    end,
}

------------------------------------------------------------------------
-- Ascension frames, with the methods copied on as the client's Mixin does
------------------------------------------------------------------------

local rapidSaves = 0
local rapidRemoves = 0

WildCardRapidRollingFrame = {
    SaveDesiredEntry = function(_, entryId, entryType)
        rapidSaves = rapidSaves + 1
        desired[Key(entryId, entryType)] = true
    end,
    RemoveDesiredEntry = function(_, entryId, entryType)
        rapidRemoves = rapidRemoves + 1
        desired[Key(entryId, entryType)] = nil
    end,
}

local menuOpens = 0

CharacterAdvancement = {
    ShowSpellDropDownMenu = function(_, spellButton)
        menuOpens = menuOpens + 1
        return spellButton
    end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/integration/DesiredSync.lua")

AscensionSuite.Database.Init()

local API = AscensionSuite.AscensionAPI
local Wishlist = AscensionSuite.Wishlist
local DesiredSync = AscensionSuite.DesiredSync
assert(DesiredSync, "DesiredSync module missing")

DesiredSync.Init()

local hookedRapid, hookedBook = DesiredSync.IsAttached()
assert(hookedRapid, "Rapid Desired toggles must be hooked")
assert(hookedBook, "Character Advancement dropdown must be hooked")

------------------------------------------------------------------------
-- An entry whose spell id is only reachable through Spells[rank]
------------------------------------------------------------------------

assert(API.GetEntrySpellID(2001) == 133,
    "entries carry Spells as a per-rank array, not a scalar Spell field")

------------------------------------------------------------------------
-- The v0.2.0 gap: a mark the addon never saw being made
------------------------------------------------------------------------

desired[Key(2001, "Ability")] = true
assert(Wishlist.CountDesired() == 0, "an untracked native mark is invisible, as before")

FireEvent("WILDCARD_DESIRED_ENTRIES_CHANGED")
PumpUpdates()

assert(Wishlist.IsTracked(2001, "Ability"), "the rescan tracks confirmed selections")
assert(Wishlist.CountDesired() == 1, "Auto-Roll's gate now sees the native mark")

local gridIds = Wishlist.GetSpellIds()
local foundInGrid = false
for index = 1, #gridIds do
    if gridIds[index] == 133 then
        foundInGrid = true
    end
end
assert(foundInGrid, "a tracked mark also shows up in the overlay grid")

-- Candidates that are not selected must not be tracked: GetNumFilteredDesiredEntries
-- counts the filtered universe, not the player's selections.
assert(not Wishlist.IsTracked(2002, "Talent"), "candidates are not selections")
assert(not Wishlist.IsTracked(2003, "Ability"), "candidates are not selections")

------------------------------------------------------------------------
-- Rate limiting: a bulk desire fires the change event once per entry
------------------------------------------------------------------------

local scansBefore = scans
FireEvent("WILDCARD_DESIRED_ENTRIES_CHANGED")
FireEvent("WILDCARD_DESIRED_ENTRIES_CHANGED")
PumpUpdates()
assert(scans == scansBefore, "a rescan inside the interval is deferred, not run")

clock = clock + 5
PumpUpdates()
assert(scans > scansBefore, "the deferred rescan still runs once the interval passes")

------------------------------------------------------------------------
-- Toggling Desired in the native Rapid window
------------------------------------------------------------------------

WildCardRapidRollingFrame:SaveDesiredEntry(2002, "Talent")
assert(rapidSaves == 1, "the native handler still runs")
assert(Wishlist.IsTracked(2002, "Talent"), "SaveDesiredEntry feeds the wishlist")
assert(Wishlist.CountDesired() == 2, "both marks count")

WildCardRapidRollingFrame:RemoveDesiredEntry(2002, "Talent")
assert(rapidRemoves == 1, "the native handler still runs")
assert(not Wishlist.IsTracked(2002, "Talent"), "RemoveDesiredEntry prunes the registry")
assert(Wishlist.CountDesired() == 1, "an unmarked entry stops counting")

-- The hook hands over an advancement internal ID, so the spell behind it has to
-- be looked up in that id space.
WildCardRapidRollingFrame:SaveDesiredEntry(2004, "Ability")
local tracked = Wishlist.GetEntries()
local collided
for index = 1, #tracked do
    if tracked[index].id == 2004 then
        collided = tracked[index]
    end
end
assert(collided, "the colliding entry is tracked")
assert(collided.spellId == 5143,
    "internal ID 2004 must resolve as an entry id, not as spell 2004 (got "
        .. tostring(collided.spellId) .. ")")
WildCardRapidRollingFrame:RemoveDesiredEntry(2004, "Ability")

------------------------------------------------------------------------
-- Marking from the Character Advancement book
------------------------------------------------------------------------

local spellButton = { entry = ENTRIES[2003], spellID = 118 }

-- A plain right-click is Ascension's own dropdown and must stay that way.
altDown = false
local closesBefore = menuCloses
CharacterAdvancement:ShowSpellDropDownMenu(spellButton)
assert(menuOpens == 1, "the native dropdown still opens")
assert(menuCloses == closesBefore, "an unmodified right-click is left alone")
assert(not Wishlist.IsTracked(2003, "Ability"), "an unmodified right-click marks nothing")

-- Alt + right-click marks Desired and closes the menu it just opened.
altDown = true
CharacterAdvancement:ShowSpellDropDownMenu(spellButton)
assert(menuOpens == 2, "the hook runs after the native handler, never instead of it")
assert(menuCloses == closesBefore + 1, "Alt + right-click reads as a mark, not a menu")
assert(desired[Key(2003, "Ability")] == true, "the entry is Desired in the client")
assert(Wishlist.IsTracked(2003, "Ability"), "and tracked by the Suite")
assert(Wishlist.CountDesired() == 2, "Auto-Roll's gate counts the book mark")

-- Alt + right-click again is the way back out.
CharacterAdvancement:ShowSpellDropDownMenu(spellButton)
assert(desired[Key(2003, "Ability")] == nil, "second Alt + right-click un-desires")
assert(not Wishlist.IsTracked(2003, "Ability"), "and untracks")
assert(Wishlist.CountDesired() == 1, "back to the single mark")

assert(lockCalls == 0, "marking Desired must never lock or unlock an entry")
assert(unlearnCalls == 0, "marking Desired must never unlearn an entry")

------------------------------------------------------------------------
-- Profiles carry the tracked registry, not just the grid
------------------------------------------------------------------------

assert(Wishlist.SaveProfile("native-marks", false), "save profile")
local profile = AscensionSuiteDB.desiredProfiles["native-marks"]
assert(#profile.entries == 1 and profile.entries[1].id == 2001, "profile records the tracked mark")

AscensionSuiteDB.wishlistEntries = {}
assert(Wishlist.LoadProfile("native-marks", true), "load profile")
assert(Wishlist.IsTracked(2001, "Ability"), "loading a profile re-tracks its Desired set")
assert(Wishlist.CountDesired() == 1, "and Auto-Roll can verify it again")

print("OK: AscensionSuite desired sync test passed")
