-- AscensionSuite: tests/test_sync_filter.lua
-- Sync from Rapid must see every Desired mark, not just the ones the Rapid
-- window's search box happens to be showing -- and must hand the player's search
-- back exactly as they left it.

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

CreateFrame = function()
    local frame = { _scripts = {}, _shown = true, _events = {} }
    function frame:RegisterEvent(event) self._events[event] = true end
    function frame:UnregisterEvent(event) self._events[event] = nil end
    function frame:SetScript(script, fn) self._scripts[script] = fn end
    function frame:GetScript(script) return self._scripts[script] end
    function frame:Show() self._shown = true end
    function frame:Hide() self._shown = false end
    function frame:IsShown() return self._shown end
    return frame
end

function GetSpellInfo(spellId)
    return "Spell " .. tostring(spellId), "Rank 1", "Interface\\Icons\\Test"
end

------------------------------------------------------------------------
-- Advancement data and the Desired selections behind it
------------------------------------------------------------------------

local ENTRIES = {
    [3001] = { ID = 3001, Type = "Ability", Spells = { 133 }, Name = "Fireball" },
    [3002] = { ID = 3002, Type = "Ability", Spells = { 116 }, Name = "Ice Block" },
    [3003] = { ID = 3003, Type = "Talent", Spells = { 118 }, Name = "Polymorph" },
    [3004] = { ID = 3004, Type = "Ability", Spells = { 122 }, Name = "Frost Nova" },
}

local BY_SPELL = {}
for _, entry in pairs(ENTRIES) do
    BY_SPELL[entry.Spells[1]] = entry
end

local ALL_CANDIDATES = { ENTRIES[3001], ENTRIES[3002], ENTRIES[3003], ENTRIES[3004] }

-- The client keeps a server-side filtered view of the candidate list; the Rapid
-- window sets it from its search box. This mirrors that: the filter is state, and
-- GetNumFilteredDesiredEntries only ever reports what the last search left behind.
local filteredCandidates = {}
local setFilterCalls = 0

local function ApplyFilter(text)
    setFilterCalls = setFilterCalls + 1
    filteredCandidates = {}
    local needle = (text or ""):lower()
    for index = 1, #ALL_CANDIDATES do
        local entry = ALL_CANDIDATES[index]
        if needle == "" or entry.Name:lower():find(needle, 1, true) then
            filteredCandidates[#filteredCandidates + 1] = entry
        end
    end
end

local desired = {}
local function Key(entryId, entryType)
    return tostring(entryId) .. "/" .. tostring(entryType)
end

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryByInternalID = function(_, id) return ENTRIES[id] end,
    GetEntryBySpellID = function(_, id) return BY_SPELL[id] end,
}

C_Wildcard = {
    GetNumFilteredDesiredEntries = function() return #filteredCandidates end,
    GetFilteredDesiredEntryAtIndex = function(_, index) return filteredCandidates[index] end,
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, id, entryType) return desired[Key(id, entryType)] == true end,
}

------------------------------------------------------------------------
-- The Rapid window, with the two members the widen path uses
------------------------------------------------------------------------

local searchText = ""
local searchCalls = {}

WildCardRapidRollingFrame = {
    DesiredSearchBox = {
        GetText = function() return searchText end,
        SetText = function(_, value) searchText = value or "" end,
    },
    DesiredSearch = function(self, text)
        -- Ascension reads the box when it is handed no text, which is exactly why
        -- widening can leave the box alone and still be undone.
        if text == nil then
            text = searchText
        end
        searchCalls[#searchCalls + 1] = text
        ApplyFilter(text)
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

------------------------------------------------------------------------
-- Four Desired marks, a search box narrowed to one of them
------------------------------------------------------------------------

desired[Key(3001, "Ability")] = true
desired[Key(3002, "Ability")] = true
desired[Key(3003, "Talent")] = true

WildCardRapidRollingFrame.DesiredSearchBox:SetText("ice")
WildCardRapidRollingFrame:DesiredSearch()
assert(#filteredCandidates == 1, "the search box narrows the candidate list to Ice Block")

-- The old behaviour, kept as an API and asserted so the regression is visible:
-- the filtered scan on its own finds one of the three marks.
local narrow = API.CollectDesiredSelections()
assert(#narrow == 1, "the filtered scan sees only what the search admits (got " .. #narrow .. ")")

local added, scanned, widened = Wishlist.SyncFromNative()
assert(widened == true, "the sync reports that it had to widen the search")
assert(added == 3, "all three Desired marks reach the wishlist (got " .. tostring(added) .. ")")
assert(scanned == 4, "the widened scan walked the whole candidate list (got " .. tostring(scanned) .. ")")

assert(Wishlist.HasEntry(3001, "Ability"), "Fireball was marked Desired and is now on the list")
assert(Wishlist.HasEntry(3003, "Talent"), "so is the talent the search hid")
assert(not Wishlist.HasEntry(3004, "Ability"), "a candidate nobody marked is still not on the list")

------------------------------------------------------------------------
-- The player's search survives the scan
------------------------------------------------------------------------

assert(searchText == "ice", "the search box is never written to")
assert(searchCalls[#searchCalls] == "ice", "and the filter is restored from it afterwards")
assert(#filteredCandidates == 1, "so the Rapid list looks exactly as the player left it")

------------------------------------------------------------------------
-- Nothing to widen: an empty search box is left entirely alone
------------------------------------------------------------------------

Wishlist.Clear()
WildCardRapidRollingFrame.DesiredSearchBox:SetText("")
WildCardRapidRollingFrame:DesiredSearch()

local callsBefore = #searchCalls
added, scanned, widened = Wishlist.SyncFromNative()
assert(widened == false, "an empty search box needs no widening")
assert(#searchCalls == callsBefore, "and the client's filter is not touched at all")
assert(added == 3, "the scan still finds every mark")

------------------------------------------------------------------------
-- Ascension's own saved Desired table as a second source
--
-- RapidRollDesired is where the Rapid window records each toggle. Reading it
-- finds marks the candidate list cannot show at all -- an entry filtered out by
-- something other than the search box, or one saved in an earlier session.
------------------------------------------------------------------------

Wishlist.Clear()
desired[Key(3004, "Ability")] = true

-- Candidate list narrowed to nothing by a filter this addon cannot clear.
ALL_CANDIDATES = {}
ApplyFilter("")
assert(API.GetNumFilteredDesiredEntries() == 0, "no candidates at all")

RapidRollDesired = {
    [7] = {
        Ability = { [3004] = true, [3001] = true },
        Talent = { [3003] = true },
    },
}
SpecializationUtil = { GetActiveSpecialization = function() return 7 end }

added, scanned = Wishlist.SyncFromNative()
assert(scanned == 0, "the candidate scan found nothing to walk")
assert(added == 3, "the saved table still recovers the confirmed marks (got " .. tostring(added) .. ")")

-- A saved row for something that is not actually Desired any more contributes
-- nothing: the table is a hint, IsDesiredID is the authority.
Wishlist.Clear()
desired[Key(3001, "Ability")] = nil
added = Wishlist.SyncFromNative()
assert(added == 2, "an unmarked saved row is ignored (got " .. tostring(added) .. ")")
assert(not Wishlist.HasEntry(3001, "Ability"), "and does not reach the wishlist")

-- No spec id: every bucket is fair game, since IsDesiredID answers for the spec
-- that is actually active.
Wishlist.Clear()
SpecializationUtil = { GetActiveSpecialization = function() return nil end }
added = Wishlist.SyncFromNative()
assert(added == 2, "buckets are scanned even without an active spec id")

------------------------------------------------------------------------
-- DesiredSync passes the widened flag through to its callers
------------------------------------------------------------------------

Wishlist.Clear()
ALL_CANDIDATES = { ENTRIES[3002], ENTRIES[3003], ENTRIES[3004] }
RapidRollDesired = nil
WildCardRapidRollingFrame.DesiredSearchBox:SetText("frost")
WildCardRapidRollingFrame:DesiredSearch()

local syncAdded, syncScanned, syncWidened = DesiredSync.Sync()
assert(syncWidened == true, "DesiredSync reports the widening so the UI can say so")
assert(syncAdded == 3, "and finds every mark (got " .. tostring(syncAdded) .. ")")
assert(syncScanned == 3, "having scanned the full candidate list")

print("OK: AscensionSuite sync filter test passed")
