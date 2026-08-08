-- AscensionSuite: core/Wishlist.lua
-- Sync Suite wishlist entries to Ascension Desired via AscensionAPI.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local Wishlist = {}
AscensionSuite.Wishlist = Wishlist

-- Both stores are bounded so a long session of marking and unmarking in the
-- native Rapid window cannot grow SavedVariables without limit.
local MAX_TRACKED_ENTRIES = 300
local MAX_TRACKED_SPELL_IDS = 200

local function GetDB()
    local DB = AscensionSuite.Database
    if DB and DB.Get then
        return DB.Get()
    end
    return AscensionSuiteDB
end

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function CopyTable(source)
    local out = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            out[key] = CopyTable(value)
        else
            out[key] = value
        end
    end
    return out
end

local function NormalizeSpellId(spellId)
    local id = tonumber(spellId)
    if not id then
        return nil
    end
    return math.floor(id)
end

local function ResolveEntryPair(spellOrEntryId)
    local api = GetAPI()
    if not api then
        return nil, nil
    end

    local entry = api.ResolveEntry(spellOrEntryId)
    if not entry then
        return nil, nil
    end

    local entryId = entry.ID or entry.Id or entry.id or entry.internalID or entry.InternalID
    local entryType = entry.Type or entry.type or entry.entryType or entry.EntryType
    entryId = tonumber(entryId)
    if not entryId or not entryType then
        return nil, nil
    end
    return entryId, entryType
end

function Wishlist.GetSpellIds()
    local data = GetDB()
    if type(data.wishlistSpellIds) ~= "table" then
        return {}
    end
    return data.wishlistSpellIds
end

function Wishlist.TrackSpellId(spellId)
    local id = NormalizeSpellId(spellId)
    if not id then
        return false
    end

    local spellIds = Wishlist.GetSpellIds()
    for index = 1, #spellIds do
        if spellIds[index] == id then
            return true
        end
    end
    spellIds[#spellIds + 1] = id
    while #spellIds > MAX_TRACKED_SPELL_IDS do
        table.remove(spellIds, 1)
    end

    local DB = AscensionSuite.Database
    if DB and DB.SetWishlistSpellIds then
        DB.SetWishlistSpellIds(spellIds)
    end
    return true
end

------------------------------------------------------------------------
-- Tracked Desired entries
--
-- The spell-id grid is the player's own watch list. This second store is the
-- registry of advancement entries the addon has *seen* marked Desired, whether
-- that happened in the overlay, in Ascension's Rapid window, or in the
-- Character Advancement book. It exists because the client offers IsDesiredID
-- per entry and nothing that enumerates selections, so Auto-Roll can only
-- verify targets it already knows an (id, type) pair for.
------------------------------------------------------------------------

function Wishlist.GetEntries()
    local data = GetDB()
    if type(data.wishlistEntries) ~= "table" then
        data.wishlistEntries = {}
    end
    return data.wishlistEntries
end

local function FindEntryIndex(entries, entryId, entryType)
    for index = 1, #entries do
        local row = entries[index]
        if type(row) == "table" and row.id == entryId and row.type == entryType then
            return index
        end
    end
    return nil
end

-- Records an (id, type) pair as a wishlist target and mirrors its spell into the
-- grid so a mark made in a native window shows up in the overlay too. Tracking
-- says nothing about whether the entry is Desired right now; CountDesired asks
-- the client about that every time.
function Wishlist.TrackEntry(entryId, entryType, spellId, name)
    local id = tonumber(entryId)
    if not id or type(entryType) ~= "string" or entryType == "" then
        return false, "invalid_entry"
    end

    local api = GetAPI()
    local resolvedSpellId = NormalizeSpellId(spellId)
    if not resolvedSpellId and api and api.GetEntrySpellID then
        resolvedSpellId = NormalizeSpellId(api.GetEntrySpellID(id))
    end

    local entries = Wishlist.GetEntries()
    local index = FindEntryIndex(entries, id, entryType)
    local isNew = index == nil

    if isNew then
        entries[#entries + 1] = {
            id = id,
            type = entryType,
            spellId = resolvedSpellId,
            name = name,
        }
        while #entries > MAX_TRACKED_ENTRIES do
            table.remove(entries, 1)
        end
    else
        local row = entries[index]
        row.spellId = row.spellId or resolvedSpellId
        row.name = row.name or name
    end

    if resolvedSpellId then
        Wishlist.TrackSpellId(resolvedSpellId)
    end
    return true, isNew
end

function Wishlist.UntrackEntry(entryId, entryType)
    local id = tonumber(entryId)
    if not id or type(entryType) ~= "string" then
        return false
    end

    local entries = Wishlist.GetEntries()
    local index = FindEntryIndex(entries, id, entryType)
    if not index then
        return false
    end

    -- Only the Desired registry is pruned. The spell stays in the grid so a
    -- cell the player toggled off is still there to toggle back on.
    table.remove(entries, index)
    return true
end

function Wishlist.IsTracked(entryId, entryType)
    return FindEntryIndex(Wishlist.GetEntries(), tonumber(entryId), entryType) ~= nil
end

-- Every (id, type) pair the addon can ask IsDesiredID about: the tracked entry
-- registry first, then whatever the grid's spell ids still resolve to.
function Wishlist.CollectTracked()
    local rows = {}
    local seen = {}

    local entries = Wishlist.GetEntries()
    for index = 1, #entries do
        local row = entries[index]
        if type(row) == "table" and row.id and row.type then
            local key = row.type .. ":" .. tostring(row.id)
            if not seen[key] then
                seen[key] = true
                rows[#rows + 1] = { id = row.id, type = row.type, spellId = row.spellId, name = row.name }
            end
        end
    end

    local spellIds = Wishlist.GetSpellIds()
    for index = 1, #spellIds do
        local entryId, entryType = ResolveEntryPair(spellIds[index])
        if entryId and entryType then
            local key = entryType .. ":" .. tostring(entryId)
            if not seen[key] then
                seen[key] = true
                rows[#rows + 1] = { id = entryId, type = entryType, spellId = spellIds[index] }
            end
        end
    end

    return rows
end

-- Pulls Desired selections the player made in a native window into the tracked
-- registry. The scan universe is the Rapid window's filtered candidate list, so
-- a narrow search box hides selections from it; each candidate is confirmed with
-- IsDesiredID rather than assumed to be selected.
function Wishlist.SyncFromNative()
    local api = GetAPI()
    if not api or not api.CollectDesiredSelections then
        return 0, 0
    end

    local selections, scanned = api.CollectDesiredSelections()
    local added = 0
    for index = 1, #selections do
        local row = selections[index]
        local ok, isNew = Wishlist.TrackEntry(row.id, row.type, row.spellId, row.name)
        if ok and isNew then
            added = added + 1
        end
    end
    return added, scanned or 0
end

function Wishlist.AddToDesired(spellOrEntryId)
    local api = GetAPI()
    if not api then
        return false, "no_api"
    end

    local entryId, entryType = ResolveEntryPair(spellOrEntryId)
    if not entryId then
        return false, "unresolved_entry"
    end

    if not api.CanAddDesiredID(entryId, entryType) and not api.IsDesiredID(entryId, entryType) then
        return false, "cannot_add"
    end

    local ok, reason = api.AddDesiredID(entryId, entryType)
    if not ok then
        return false, reason or "add_failed"
    end

    local spellId = api.GetEntrySpellID(spellOrEntryId) or tonumber(spellOrEntryId)
    Wishlist.TrackEntry(entryId, entryType, spellId)
    return true
end

function Wishlist.RemoveFromDesired(spellOrEntryId)
    local api = GetAPI()
    if not api then
        return false
    end

    local entryId, entryType = ResolveEntryPair(spellOrEntryId)
    if not entryId then
        return false
    end

    local removed = api.RemoveDesiredID(entryId, entryType)
    Wishlist.UntrackEntry(entryId, entryType)
    return removed
end

function Wishlist.IsDesired(spellOrEntryId)
    local api = GetAPI()
    if not api then
        return false
    end

    local entryId, entryType = ResolveEntryPair(spellOrEntryId)
    if not entryId then
        return false
    end
    return api.IsDesiredID(entryId, entryType)
end

-- How many tracked wishlist entries are currently marked Desired in Ascension.
-- The client offers IsDesiredID per entry but no count or listing of Desired
-- selections, so this only sees entries the addon has a tracked (id, type) pair
-- for. DesiredSync keeps that registry fed from the native windows; a mark made
-- while the addon was unloaded stays invisible until the next sync.
function Wishlist.CountDesired()
    local api = GetAPI()
    if not api then
        return 0
    end

    local count = 0
    local tracked = Wishlist.CollectTracked()
    for index = 1, #tracked do
        local row = tracked[index]
        if api.IsDesiredID(row.id, row.type) then
            count = count + 1
        end
    end
    return count
end

function Wishlist.SaveProfile(name, includeKnownSnapshot)
    if type(name) ~= "string" then
        return false, "invalid name"
    end

    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return false, "empty name"
    end

    local api = GetAPI()
    if not api then
        return false, "no_api"
    end

    -- entries is the Desired set to restore; spellIds is the whole tracked
    -- wishlist. Keeping them apart matters because tracking a spell in the grid
    -- is not the same as marking it Desired, and loading a profile must not
    -- desire everything the player merely kept an eye on.
    local entries = {}
    local tracked = Wishlist.CollectTracked()
    for index = 1, #tracked do
        local row = tracked[index]
        if api.IsDesiredID(row.id, row.type) then
            entries[#entries + 1] = {
                id = row.id,
                type = row.type,
                spellId = row.spellId,
            }
        end
    end

    local spellIds = Wishlist.GetSpellIds()

    local profile = {
        entries = entries,
        spellIds = CopyTable(spellIds),
    }

    if includeKnownSnapshot then
        profile.knownSnapshot = api.CaptureKnownSnapshot()
    end

    local data = GetDB()
    if type(data.desiredProfiles) ~= "table" then
        data.desiredProfiles = {}
    end
    data.desiredProfiles[name] = profile
    return true
end

function Wishlist.LoadProfile(name, reapplyDesired)
    if type(name) ~= "string" then
        return false, "invalid name"
    end

    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return false, "empty name"
    end

    local data = GetDB()
    if type(data.desiredProfiles) ~= "table" then
        return false, "no profiles"
    end

    local profile = data.desiredProfiles[name]
    if type(profile) ~= "table" then
        return false, "profile not found"
    end

    if type(profile.spellIds) == "table" then
        data.wishlistSpellIds = CopyTable(profile.spellIds)
    end

    -- The profile's Desired set replaces the tracked registry outright: the
    -- entries it names are exactly the targets Auto-Roll should verify next.
    data.wishlistEntries = {}
    if type(profile.entries) == "table" then
        for index = 1, #profile.entries do
            local row = profile.entries[index]
            if type(row) == "table" and row.id and row.type then
                Wishlist.TrackEntry(row.id, row.type, row.spellId)
            end
        end
    end

    if reapplyDesired ~= false then
        local api = GetAPI()
        if api and api.ClearDesiredSpells then
            api.ClearDesiredSpells()
            if type(profile.entries) == "table" then
                for index = 1, #profile.entries do
                    local row = profile.entries[index]
                    if type(row) == "table" and row.id and row.type then
                        api.AddDesiredID(row.id, row.type)
                    end
                end
            end
        end
    end

    return true, profile.knownSnapshot
end

function Wishlist.ListProfiles()
    local data = GetDB()
    local names = {}
    if type(data.desiredProfiles) == "table" then
        for profileName in pairs(data.desiredProfiles) do
            names[#names + 1] = profileName
        end
        table.sort(names)
    end
    return names
end
