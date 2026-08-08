-- AscensionSuite: core/Wishlist.lua
-- The player-owned wishlist.
--
-- One ordered list of advancement targets that can be built and edited at any
-- time, in any game mode. Ascension "Desired" is a separate, Wildcard-only
-- concept layered on top: while Wildcard is active the two are kept in step
-- (a Desired toggle in a native window edits this list, and this list can be
-- pushed back into Desired), and outside Wildcard the list simply persists.
--
-- Rows carry both id spaces because they answer different questions:
--   spellId  -- what the player sees: icon, name, tooltip, and what they type.
--   entryId + entryType -- the pair every C_Wildcard Desired call needs, which
--                          a spell id alone cannot always produce.
-- A row may start with only one of them; the missing half is resolved lazily
-- and cached, because an id the client cannot resolve in one mode may resolve
-- in another.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local Wishlist = {}
AscensionSuite.Wishlist = Wishlist

-- Bounded so a long session of marking and unmarking in the native Rapid window
-- cannot grow SavedVariables without limit.
local MAX_ITEMS = 300

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

local function NormalizeId(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return math.floor(id)
end

------------------------------------------------------------------------
-- Store
------------------------------------------------------------------------

function Wishlist.GetItems()
    local data = GetDB()
    if type(data.wishlist) ~= "table" then
        data.wishlist = {}
    end
    return data.wishlist
end

function Wishlist.Count()
    return #Wishlist.GetItems()
end

local function FindByPair(items, entryId, entryType)
    if not entryId or type(entryType) ~= "string" then
        return nil
    end
    for index = 1, #items do
        local item = items[index]
        if type(item) == "table" and item.entryId == entryId and item.entryType == entryType then
            return index
        end
    end
    return nil
end

local function FindBySpell(items, spellId)
    if not spellId then
        return nil
    end
    for index = 1, #items do
        local item = items[index]
        if type(item) == "table" and item.spellId == spellId then
            return index
        end
    end
    return nil
end

local function Trim(items)
    while #items > MAX_ITEMS do
        table.remove(items, 1)
    end
end

-- The (entryId, entryType) pair every Desired call needs. Resolved from the
-- spell id when the row does not carry one yet and cached on the row, so a list
-- of a few hundred rows costs one lookup each rather than one per refresh.
local function ItemPair(item)
    if type(item) ~= "table" then
        return nil, nil
    end
    if item.entryId and type(item.entryType) == "string" then
        return item.entryId, item.entryType
    end

    local api = GetAPI()
    if not api or not item.spellId then
        return nil, nil
    end

    local entry = api.ResolveEntry(item.spellId)
    if type(entry) ~= "table" then
        return nil, nil
    end

    local entryId = NormalizeId(entry.ID or entry.Id or entry.id or entry.internalID or entry.InternalID)
    local entryType = entry.Type or entry.type or entry.entryType or entry.EntryType
    if not entryId or type(entryType) ~= "string" or entryType == "" then
        return nil, nil
    end

    item.entryId = entryId
    item.entryType = entryType
    return entryId, entryType
end

Wishlist.GetItemPair = ItemPair

------------------------------------------------------------------------
-- Editing (always allowed, in any game mode)
------------------------------------------------------------------------

local function Upsert(items, spellId, entryId, entryType, name)
    local index = FindByPair(items, entryId, entryType) or FindBySpell(items, spellId)
    if index then
        local item = items[index]
        item.spellId = item.spellId or spellId
        item.entryId = item.entryId or entryId
        item.entryType = item.entryType or entryType
        item.name = item.name or name
        return item, false
    end

    local item = {
        spellId = spellId,
        entryId = entryId,
        entryType = entryType,
        name = name,
    }
    items[#items + 1] = item
    Trim(items)
    return item, true
end

-- Add by whatever the player typed: a spell id or an advancement internal id.
-- An id the client cannot resolve is still stored -- Character Advancement data
-- is not always loaded, and an id that resolves in Wildcard may not outside it,
-- so rejecting it here would silently lose a legitimate wishlist entry.
function Wishlist.Add(spellOrEntryId)
    local id = NormalizeId(spellOrEntryId)
    if not id then
        return false, "invalid_id"
    end

    local api = GetAPI()
    local spellId, entryId, entryType, name = id, nil, nil, nil

    if api then
        local entry = api.ResolveEntry(id)
        if type(entry) == "table" then
            entryId = NormalizeId(entry.ID or entry.Id or entry.id or entry.internalID or entry.InternalID)
            local resolvedType = entry.Type or entry.type or entry.entryType or entry.EntryType
            if type(resolvedType) == "string" and resolvedType ~= "" then
                entryType = resolvedType
            end
            spellId = NormalizeId(api.GetEntrySpellID(id)) or id
            name = api.GetEntryName(id)
        end
    end

    local _, isNew = Upsert(Wishlist.GetItems(), spellId, entryId, entryType, name)
    return true, isNew and "added" or "exists"
end

-- Add from an advancement entry the caller already holds a pair for -- the
-- Character Advancement book hook and the native Rapid list both do.
function Wishlist.AddEntry(entryId, entryType, spellId, name)
    local id = NormalizeId(entryId)
    if not id or type(entryType) ~= "string" or entryType == "" then
        return false, "invalid_entry"
    end

    -- The id is always an advancement internal ID here, so it has to be resolved
    -- in that id space: a spell-first lookup can land on an unrelated entry whose
    -- spell ID collides with this internal ID.
    local api = GetAPI()
    local resolvedSpellId = NormalizeId(spellId)
    if not resolvedSpellId and api and api.GetEntrySpellIDByInternalID then
        resolvedSpellId = NormalizeId(api.GetEntrySpellIDByInternalID(id))
    end

    local _, isNew = Upsert(Wishlist.GetItems(), resolvedSpellId, id, entryType, name)
    return true, isNew
end

function Wishlist.RemoveItem(item)
    if type(item) ~= "table" then
        return false
    end
    local items = Wishlist.GetItems()
    for index = 1, #items do
        if items[index] == item then
            table.remove(items, index)
            return true
        end
    end
    return false
end

-- Which row an advancement entry belongs to. The spell id is checked as well as
-- the (id, type) pair because a row the player added by typing a spell id has no
-- pair until something resolves it -- without this, Alt + right-clicking a spell
-- already on the list would read as an add and take two clicks to remove.
local function FindEntryIndex(items, entryId, entryType, spellId)
    local index = FindByPair(items, entryId, entryType)
    if index then
        return index
    end
    return FindBySpell(items, NormalizeId(spellId))
end

function Wishlist.RemoveEntry(entryId, entryType, spellId)
    local id = NormalizeId(entryId)
    if not id or type(entryType) ~= "string" then
        return false
    end

    local items = Wishlist.GetItems()
    local index = FindEntryIndex(items, id, entryType, spellId)
    if not index then
        return false
    end
    table.remove(items, index)
    return true
end

function Wishlist.Remove(spellOrEntryId)
    local id = NormalizeId(spellOrEntryId)
    if not id then
        return false
    end

    local items = Wishlist.GetItems()
    local index = FindBySpell(items, id)
    if not index then
        for scan = 1, #items do
            if items[scan].entryId == id then
                index = scan
                break
            end
        end
    end
    if not index then
        return false
    end
    table.remove(items, index)
    return true
end

function Wishlist.Contains(spellOrEntryId)
    local id = NormalizeId(spellOrEntryId)
    if not id then
        return false
    end

    local items = Wishlist.GetItems()
    if FindBySpell(items, id) then
        return true
    end
    for index = 1, #items do
        if items[index].entryId == id then
            return true
        end
    end
    return false
end

function Wishlist.HasEntry(entryId, entryType, spellId)
    return FindEntryIndex(Wishlist.GetItems(), NormalizeId(entryId), entryType, spellId) ~= nil
end

function Wishlist.Clear()
    local items = Wishlist.GetItems()
    local removed = #items
    for index = removed, 1, -1 do
        table.remove(items, index)
    end
    return removed
end

------------------------------------------------------------------------
-- Presentation
------------------------------------------------------------------------

-- Everything one list row needs. Name and icon come from AscensionAPI 1:1 and
-- fall back to GetSpellInfo inside the seam; a row the client cannot resolve at
-- all still describes itself by id rather than disappearing.
function Wishlist.Describe(item)
    if type(item) ~= "table" then
        return nil
    end

    local api = GetAPI()
    local lookupId = item.spellId or item.entryId
    local icon = item.icon

    -- Presentation is cached on the row once the client actually resolves it,
    -- because a search keystroke re-describes the whole list. Only a real
    -- resolution is cached: an id the book cannot resolve today may resolve in
    -- another game mode, and caching the placeholder would make that permanent.
    if (not item.name or not icon) and api and lookupId then
        local resolvedName = api.GetEntryName(lookupId)
        local resolvedIcon = api.GetEntryIcon(lookupId)
        if resolvedName and resolvedName ~= "Unknown"
            and resolvedName ~= ("Spell " .. tostring(lookupId)) then
            item.name = resolvedName
            item.icon = resolvedIcon
        end
        icon = resolvedIcon
    end

    return {
        item = item,
        spellId = item.spellId,
        entryId = item.entryId,
        entryType = item.entryType,
        displayId = lookupId,
        name = item.name or ("Entry " .. tostring(lookupId or "?")),
        icon = icon,
        resolved = item.name ~= nil,
        desired = Wishlist.IsItemDesired(item),
    }
end

-- Case-insensitive match on name or id. An empty filter returns everything, in
-- list order, so the panel can use one path for both.
function Wishlist.Search(filter)
    local needle = nil
    if type(filter) == "string" then
        needle = filter:match("^%s*(.-)%s*$")
        if needle == "" then
            needle = nil
        else
            needle = needle:lower()
        end
    end

    local rows = {}
    local items = Wishlist.GetItems()
    for index = 1, #items do
        local row = Wishlist.Describe(items[index])
        if row then
            local keep = true
            if needle then
                local haystack = (row.name or ""):lower() .. " " .. tostring(row.displayId or "")
                keep = haystack:find(needle, 1, true) ~= nil
            end
            if keep then
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

------------------------------------------------------------------------
-- Ascension Desired (Wildcard only)
------------------------------------------------------------------------

function Wishlist.IsItemDesired(item)
    local api = GetAPI()
    if not api then
        return false
    end
    local entryId, entryType = ItemPair(item)
    if not entryId then
        return false
    end
    return api.IsDesiredID(entryId, entryType) == true
end

-- Every (entryId, entryType) pair the addon can ask IsDesiredID about. The
-- client exposes no way to enumerate Desired selections, so this list is the
-- whole universe Auto-Roll can verify against.
function Wishlist.CollectTracked()
    local rows = {}
    local seen = {}
    local items = Wishlist.GetItems()

    for index = 1, #items do
        local item = items[index]
        local entryId, entryType = ItemPair(item)
        if entryId and entryType then
            local key = entryType .. ":" .. tostring(entryId)
            if not seen[key] then
                seen[key] = true
                rows[#rows + 1] = {
                    id = entryId,
                    type = entryType,
                    spellId = item.spellId,
                    name = item.name,
                }
            end
        end
    end

    return rows
end

-- How many wishlist rows Ascension confirms are Desired right now. Asked live
-- every time: the player can edit Desired in Ascension's own windows, and a
-- stored flag would go stale the moment they do.
function Wishlist.CountDesired()
    local api = GetAPI()
    if not api then
        return 0
    end

    local count = 0
    local items = Wishlist.GetItems()
    for index = 1, #items do
        if Wishlist.IsItemDesired(items[index]) then
            count = count + 1
        end
    end
    return count
end

-- Mark every wishlist row Desired. Wildcard-gated because Desired does not
-- exist outside it; returns the breakdown so the panel can say what happened
-- rather than just "done".
function Wishlist.PushToDesired()
    local api = GetAPI()
    if not api then
        return 0, 0, 0, "no_api"
    end
    if not api.IsWildcardModeActive() then
        return 0, 0, 0, "not_wildcard"
    end

    local pushed, already, failed = 0, 0, 0
    local items = Wishlist.GetItems()
    for index = 1, #items do
        local entryId, entryType = ItemPair(items[index])
        if not entryId then
            failed = failed + 1
        elseif api.IsDesiredID(entryId, entryType) then
            already = already + 1
        elseif not api.CanAddDesiredID(entryId, entryType) then
            failed = failed + 1
        elseif api.AddDesiredID(entryId, entryType) then
            pushed = pushed + 1
        else
            failed = failed + 1
        end
    end
    return pushed, already, failed
end

function Wishlist.AddToDesired(spellOrEntryId)
    local ok, reason = Wishlist.Add(spellOrEntryId)
    if not ok then
        return false, reason
    end

    local api = GetAPI()
    if not api then
        return false, "no_api"
    end

    local items = Wishlist.GetItems()
    local id = NormalizeId(spellOrEntryId)
    local index = FindBySpell(items, id)
    if not index then
        for scan = 1, #items do
            if items[scan].entryId == id then
                index = scan
                break
            end
        end
    end
    if not index then
        return false, "unresolved_entry"
    end

    local entryId, entryType = ItemPair(items[index])
    if not entryId then
        return false, "unresolved_entry"
    end

    if api.IsDesiredID(entryId, entryType) then
        return true
    end
    if not api.CanAddDesiredID(entryId, entryType) then
        return false, "cannot_add"
    end

    local added, reasonText = api.AddDesiredID(entryId, entryType)
    if not added then
        return false, reasonText or "add_failed"
    end
    return true
end

function Wishlist.RemoveFromDesired(spellOrEntryId)
    local api = GetAPI()
    if not api then
        return false
    end

    local id = NormalizeId(spellOrEntryId)
    local items = Wishlist.GetItems()
    local index = FindBySpell(items, id)
    if not index then
        for scan = 1, #items do
            if items[scan].entryId == id then
                index = scan
                break
            end
        end
    end
    if not index then
        return false
    end

    local entryId, entryType = ItemPair(items[index])
    if not entryId then
        return false
    end

    local removed = api.RemoveDesiredID(entryId, entryType)
    table.remove(items, index)
    return removed
end

function Wishlist.IsDesired(spellOrEntryId)
    local id = NormalizeId(spellOrEntryId)
    if not id then
        return false
    end

    local api = GetAPI()
    if not api then
        return false
    end

    local items = Wishlist.GetItems()
    local index = FindBySpell(items, id)
    if index then
        return Wishlist.IsItemDesired(items[index])
    end

    local entry = api.ResolveEntry(id)
    if type(entry) ~= "table" then
        return false
    end
    local entryId = NormalizeId(entry.ID or entry.Id or entry.id or entry.internalID or entry.InternalID)
    local entryType = entry.Type or entry.type or entry.entryType or entry.EntryType
    if not entryId or type(entryType) ~= "string" then
        return false
    end
    return api.IsDesiredID(entryId, entryType) == true
end

-- Pulls Desired selections the player made in a native window into the wishlist.
-- The seam widens the Rapid window's Desired search for the duration of the scan
-- and puts it back afterwards, because the candidate list is the scan universe and
-- a typed search narrows it: before that, syncing with "fire" in the search box
-- found only the Desired marks whose names contain "fire". Each candidate is still
-- confirmed with IsDesiredID rather than assumed to be selected.
--
-- Returns how many rows were newly added, how many candidates were scanned, and
-- whether the search box had to be widened.
function Wishlist.SyncFromNative()
    local api = GetAPI()
    if not api then
        return 0, 0, false
    end

    local selections, scanned, widened
    if api.CollectAllDesiredSelections then
        selections, scanned, widened = api.CollectAllDesiredSelections()
    elseif api.CollectDesiredSelections then
        selections, scanned = api.CollectDesiredSelections()
    else
        return 0, 0, false
    end

    local added = 0
    for index = 1, #selections do
        local row = selections[index]
        local ok, isNew = Wishlist.AddEntry(row.id, row.type, row.spellId, row.name)
        if ok and isNew then
            added = added + 1
        end
    end
    return added, scanned or 0, widened == true
end

------------------------------------------------------------------------
-- Profiles
------------------------------------------------------------------------

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

    -- wishlist is the whole list; entries is the subset Ascension confirms is
    -- Desired right now. Keeping them apart matters because having a row on the
    -- list is not the same as having marked it Desired, and loading a profile
    -- must not desire everything the player merely kept an eye on.
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

    local profile = {
        entries = entries,
        wishlist = CopyTable(Wishlist.GetItems()),
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

    data.wishlist = {}
    if type(profile.wishlist) == "table" then
        data.wishlist = CopyTable(profile.wishlist)
    elseif type(profile.spellIds) == "table" then
        -- Profiles saved before 0.2.2 carry a flat spell id list.
        for index = 1, #profile.spellIds do
            Wishlist.Add(profile.spellIds[index])
        end
    end

    if type(profile.entries) == "table" then
        for index = 1, #profile.entries do
            local row = profile.entries[index]
            if type(row) == "table" and row.id and row.type then
                Wishlist.AddEntry(row.id, row.type, row.spellId)
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
