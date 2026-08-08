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

local wildcard = true

local altDown = false
function IsAltKeyDown() return altDown end

local menuCloses = 0
function CloseDropDownMenus() menuCloses = menuCloses + 1 end

local messages = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text)
        messages[#messages + 1] = tostring(text)
    end,
}

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
    IsGameModeActive = function(_, mode) return wildcard and mode == "WildCard" end,
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

assert(Wishlist.HasEntry(2001, "Ability"), "the rescan tracks confirmed selections")
assert(Wishlist.CountDesired() == 1, "Auto-Roll's gate now sees the native mark")

local foundOnList = false
for _, row in ipairs(Wishlist.GetItems()) do
    if row.spellId == 133 then
        foundOnList = true
    end
end
assert(foundOnList, "a tracked mark also shows up on the wishlist with its spell")

-- Candidates that are not selected must not be tracked: GetNumFilteredDesiredEntries
-- counts the filtered universe, not the player's selections.
assert(not Wishlist.HasEntry(2002, "Talent"), "candidates are not selections")
assert(not Wishlist.HasEntry(2003, "Ability"), "candidates are not selections")

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
assert(Wishlist.HasEntry(2002, "Talent"), "SaveDesiredEntry feeds the wishlist")
assert(Wishlist.CountDesired() == 2, "both marks count")

WildCardRapidRollingFrame:RemoveDesiredEntry(2002, "Talent")
assert(rapidRemoves == 1, "the native handler still runs")
assert(not Wishlist.HasEntry(2002, "Talent"), "RemoveDesiredEntry prunes the registry")
assert(Wishlist.CountDesired() == 1, "an unmarked entry stops counting")

-- The hook hands over an advancement internal ID, so the spell behind it has to
-- be looked up in that id space.
WildCardRapidRollingFrame:SaveDesiredEntry(2004, "Ability")
local tracked = Wishlist.GetItems()
local collided
for index = 1, #tracked do
    if tracked[index].entryId == 2004 then
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
assert(not Wishlist.HasEntry(2003, "Ability"), "an unmodified right-click marks nothing")

-- Alt + right-click marks Desired and closes the menu it just opened.
altDown = true
CharacterAdvancement:ShowSpellDropDownMenu(spellButton)
assert(menuOpens == 2, "the hook runs after the native handler, never instead of it")
assert(menuCloses == closesBefore + 1, "Alt + right-click reads as a mark, not a menu")
assert(desired[Key(2003, "Ability")] == true, "the entry is Desired in the client")
assert(Wishlist.HasEntry(2003, "Ability"), "and tracked by the Suite")
assert(Wishlist.CountDesired() == 2, "Auto-Roll's gate counts the book mark")

-- Alt + right-click again is the way back out.
CharacterAdvancement:ShowSpellDropDownMenu(spellButton)
assert(desired[Key(2003, "Ability")] == nil, "second Alt + right-click un-desires")
assert(not Wishlist.HasEntry(2003, "Ability"), "and untracks")
assert(Wishlist.CountDesired() == 1, "back to the single mark")

assert(lockCalls == 0, "marking Desired must never lock or unlock an entry")
assert(unlearnCalls == 0, "marking Desired must never unlearn an entry")

------------------------------------------------------------------------
-- Profiles carry the tracked registry, not just the grid
------------------------------------------------------------------------

assert(Wishlist.SaveProfile("native-marks", false), "save profile")
local profile = AscensionSuiteDB.desiredProfiles["native-marks"]
assert(#profile.entries == 1 and profile.entries[1].id == 2001, "profile records the tracked mark")

AscensionSuiteDB.wishlist = {}
assert(Wishlist.LoadProfile("native-marks", true), "load profile")
assert(Wishlist.HasEntry(2001, "Ability"), "loading a profile re-tracks its Desired set")
assert(Wishlist.CountDesired() == 1, "and Auto-Roll can verify it again")

------------------------------------------------------------------------
-- Alt + right-click outside Wildcard
--
-- The 0.2.1 behaviour was a refusal ("Desired marks only exist in Wildcard
-- mode") once per click, which read as an error for what is a perfectly
-- reasonable thing to do between Wildcard runs. It now edits the Suite
-- wishlist and says so.
------------------------------------------------------------------------

wildcard = false
local iceBlock = { entry = ENTRIES[2002], spellID = 116 }

messages = {}
altDown = true
CharacterAdvancement:ShowSpellDropDownMenu(iceBlock)

assert(Wishlist.HasEntry(2002, "Talent"), "a book mark outside Wildcard lands on the wishlist")
assert(desired[Key(2002, "Talent")] == nil, "and marks nothing Desired, because Desired is Wildcard-only")

for index = 1, #messages do
    assert(not messages[index]:find("only exist in Wildcard"),
        "the Wildcard-only refusal must not be printed for a successful wishlist mark")
end
assert(#messages == 1, "one line per click, not a warning plus a result")
assert(messages[1]:find("Wishlist: Ice Block"), "the line names what was saved")
assert(messages[1]:find("Wildcard"), "and explains the Desired sync the first time")

-- Building a list is many clicks. The explanation is a hint, not a per-spell
-- warning, so it is shown once and then dropped.
messages = {}
CharacterAdvancement:ShowSpellDropDownMenu({ entry = ENTRIES[2003], spellID = 118 })
assert(#messages == 1 and messages[1]:find("Wishlist: Polymorph"), "the second mark still confirms")
assert(not messages[1]:find("Wildcard"), "but does not repeat the hint")

messages = {}
CharacterAdvancement:ShowSpellDropDownMenu(iceBlock)
assert(not Wishlist.HasEntry(2002, "Talent"), "Alt + right-click again removes it from the wishlist")
assert(#messages == 1 and messages[1]:find("Removed from wishlist"), "and says so plainly")

-- A row typed into the panel while the book was unavailable carries a spell id
-- and no (id, type) pair. Alt + right-clicking that spell has to recognise it as
-- already on the list, or the first click reads as an add and does nothing.
AscensionSuiteDB.wishlist = { { spellId = 116 } }
messages = {}
CharacterAdvancement:ShowSpellDropDownMenu(iceBlock)
assert(Wishlist.Count() == 0, "the pairless row is the one that gets removed")
assert(messages[1]:find("Removed from wishlist"), "on the first click, not the second")

assert(lockCalls == 0, "editing the wishlist must never lock or unlock an entry")
assert(unlearnCalls == 0, "editing the wishlist must never unlearn an entry")

------------------------------------------------------------------------
-- The panel hears about edits made outside it
--
-- A mark made with Alt + right-click in the Character Advancement book happens
-- with the Suite window somewhere behind it. The row is where the confirmation
-- goes -- nothing may be drawn on Ascension's own widgets -- so the panel has to
-- be told which row.
------------------------------------------------------------------------

local touched = {}
local refreshes = 0
AscensionSuite.WishlistPanel = {
    NoteTouched = function(entryId, entryType, spellId)
        touched[#touched + 1] = { entryId, entryType, spellId }
        return true
    end,
    Refresh = function() end,
}
AscensionSuite.MainWindow = {
    RefreshWishlist = function() refreshes = refreshes + 1 end,
}

altDown = true
CharacterAdvancement:ShowSpellDropDownMenu({ entry = ENTRIES[2001], spellID = 133 })
assert(#touched == 1, "the panel is told which row a book mark landed on")
assert(touched[1][1] == 2001 and touched[1][2] == "Ability", "and it is the right one")
assert(refreshes > 0, "and asked to redraw")

------------------------------------------------------------------------
-- Rows waiting on the advancement book refresh when it finally loads
--
-- A row typed in while Ascension_CharacterAdvancement was unloaded has an id and
-- nothing else, and draws as a placeholder until something re-describes it.
------------------------------------------------------------------------

refreshes = 0
FireEvent("ADDON_LOADED", "Ascension_CharacterAdvancement")
assert(refreshes > 0, "the wishlist is redrawn once the book's data exists")

refreshes = 0
FireEvent("ADDON_LOADED", "SomeOtherAddon")
assert(refreshes == 0, "but not for every addon that happens to load")

print("OK: AscensionSuite desired sync test passed")
