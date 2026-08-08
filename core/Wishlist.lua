-- AscensionSuite: core/Wishlist.lua
-- Sync Suite wishlist entries to Ascension Desired via AscensionAPI.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local Wishlist = {}
AscensionSuite.Wishlist = Wishlist

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

    local DB = AscensionSuite.Database
    if DB and DB.SetWishlistSpellIds then
        DB.SetWishlistSpellIds(spellIds)
    end
    return true
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
    if spellId then
        Wishlist.TrackSpellId(spellId)
    end
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
    return api.RemoveDesiredID(entryId, entryType)
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

    local entries = {}
    local spellIds = Wishlist.GetSpellIds()
    for index = 1, #spellIds do
        local entryId, entryType = ResolveEntryPair(spellIds[index])
        if entryId and entryType then
            entries[#entries + 1] = {
                id = entryId,
                type = entryType,
                spellId = spellIds[index],
            }
        end
    end

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
