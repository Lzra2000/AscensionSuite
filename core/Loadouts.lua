-- AscensionSuite: core/Loadouts.lua
-- Named loadouts: snapshot the wishlist (+ optional Known marks), load, apply to
-- Desired, and share via the ASUITE1 text format.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local Loadouts = {}
AscensionSuite.Loadouts = Loadouts

local MAX_LOADOUTS = 50
local MAX_ENTRIES = 300
local SHARE_PREFIX = "ASUITE1"

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

local function GetWishlist()
    return AscensionSuite.Wishlist
end

local function NormalizeId(value)
    local id = tonumber(value)
    if not id then
        return nil
    end
    return math.floor(id)
end

local function NormalizeEntryType(value)
    if type(value) == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            return trimmed
        end
        return nil
    end
    if value ~= nil then
        local text = tostring(value)
        if text ~= "" then
            return text
        end
    end
    return nil
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

local function Now()
    if type(_G.time) == "function" then
        return _G.time()
    end
    return 0
end

local function PlayerName()
    if type(_G.UnitName) == "function" then
        local name = _G.UnitName("player")
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    return "shared"
end

local function SlugFromName(name)
    local slug = name:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    if slug == "" then
        slug = "build"
    end
    return slug
end

local function UniqueId(name)
    return SlugFromName(name) .. "-" .. tostring(Now()) .. "-" .. tostring(math.random(1000, 9999))
end

local function GetStore()
    local data = GetDB()
    if type(data.loadouts) ~= "table" then
        data.loadouts = {}
    end
    return data.loadouts
end

local function CountLoadouts()
    local store = GetStore()
    local count = 0
    for _ in pairs(store) do
        count = count + 1
    end
    return count
end

local function ResolveRow(item)
    local Wishlist = GetWishlist()
    if Wishlist and Wishlist.ResolveItemPair then
        local entryId, entryType, err = Wishlist.ResolveItemPair(item)
        if entryId and entryType then
            return entryId, entryType, item, err
        end
        return nil, nil, item, err
    end
    if type(item) == "table" and item.entryId and type(item.entryType) == "string" then
        return item.entryId, item.entryType, item, nil
    end
    return nil, nil, item, "unresolved"
end

local function WishlistRowToEntry(item, markDesired)
    local entryId, entryType, resolved, _ = ResolveRow(item)
    local row = {
        entryId = entryId,
        entryType = entryType,
        spellId = resolved and resolved.spellId or (item and item.spellId),
        name = resolved and resolved.name or (item and item.name),
        desired = markDesired == true,
    }
    return row
end

local function EntryCount(loadout)
    if type(loadout) ~= "table" or type(loadout.entries) ~= "table" then
        return 0
    end
    return #loadout.entries
end

------------------------------------------------------------------------
-- Store
------------------------------------------------------------------------

function Loadouts.List()
    local store = GetStore()
    local rows = {}
    for id, loadout in pairs(store) do
        if type(loadout) == "table" then
            rows[#rows + 1] = {
                id = loadout.id or id,
                name = loadout.name or id,
                entryCount = EntryCount(loadout),
                character = loadout.character or "shared",
                updatedAt = loadout.updatedAt or 0,
                loadout = loadout,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.updatedAt ~= b.updatedAt then
            return a.updatedAt > b.updatedAt
        end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

function Loadouts.Get(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local store = GetStore()
    return store[id]
end

function Loadouts.Create(name, notes, shared)
    if type(name) ~= "string" then
        return nil, "invalid_name"
    end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        return nil, "empty_name"
    end

    if CountLoadouts() >= MAX_LOADOUTS then
        return nil, "loadout_limit"
    end

    local id = UniqueId(name)
    local loadout = {
        id = id,
        name = name,
        notes = type(notes) == "string" and notes or "",
        entries = {},
        updatedAt = Now(),
        character = shared == true and "shared" or PlayerName(),
    }

    GetStore()[id] = loadout
    return loadout, id
end

function Loadouts.Delete(id)
    local store = GetStore()
    if not store[id] then
        return false, "not_found"
    end
    store[id] = nil
    return true
end

function Loadouts.Rename(id, name, notes)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then
            loadout.name = name
        end
    end
    if type(notes) == "string" then
        loadout.notes = notes
    end
    loadout.updatedAt = Now()
    return true
end

------------------------------------------------------------------------
-- Snapshot / restore
------------------------------------------------------------------------

function Loadouts.SaveFromWishlist(id, includeKnown, includeDesiredMarks)
    local loadout = id and Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end

    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.GetItems then
        return false, "no_wishlist"
    end

    local api = GetAPI()
    local entries = {}
    local items = Wishlist.GetItems()
    for index = 1, #items do
        local item = items[index]
        local markDesired = false
        if includeDesiredMarks ~= false and api and Wishlist.IsItemDesired then
            markDesired = Wishlist.IsItemDesired(item) == true
        end
        entries[#entries + 1] = WishlistRowToEntry(item, markDesired)
        if #entries >= MAX_ENTRIES then
            break
        end
    end

    loadout.entries = entries
    loadout.updatedAt = Now()
    if includeKnown and api and api.CaptureKnownSnapshot then
        loadout.knownSnapshot = api.CaptureKnownSnapshot()
    end
    return true, #entries
end

function Loadouts.LoadToWishlist(id)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end

    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.GetItems then
        return false, "no_wishlist"
    end

    local items = Wishlist.GetItems()
    for index = #items, 1, -1 do
        table.remove(items, index)
    end

    if type(loadout.entries) ~= "table" then
        return true, 0
    end

    local added = 0
    for index = 1, #loadout.entries do
        local row = loadout.entries[index]
        if type(row) == "table" then
            local entryId = NormalizeId(row.entryId)
            local entryType = NormalizeEntryType(row.entryType)
            if entryId and entryType and Wishlist.AddEntry then
                local ok = Wishlist.AddEntry(entryId, entryType, row.spellId, row.name)
                if ok then
                    added = added + 1
                end
            elseif row.spellId and Wishlist.Add then
                local ok = Wishlist.Add(row.spellId)
                if ok then
                    added = added + 1
                end
            end
        end
    end
    return true, added
end

function Loadouts.Apply(id)
    local ok, count = Loadouts.LoadToWishlist(id)
    if not ok then
        return false, count, nil
    end

    local Wishlist = GetWishlist()
    if not Wishlist or not Wishlist.PushToDesired then
        return false, "no_wishlist", nil
    end

    local pushed, already, failed, gate, refuses = Wishlist.PushToDesired()
    local result = {
        loaded = count,
        pushed = pushed,
        already = already,
        failed = failed,
        refuses = refuses,
        gate = gate,
    }
    return true, result, refuses
end

function Loadouts.CaptureKnown(id)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end
    local api = GetAPI()
    if not api or not api.CaptureKnownSnapshot then
        return false, "no_api"
    end
    loadout.knownSnapshot = api.CaptureKnownSnapshot()
    loadout.updatedAt = Now()
    return true
end

function Loadouts.CountDesiredInLoadout(loadout)
    if type(loadout) ~= "table" or type(loadout.entries) ~= "table" then
        return 0
    end
    local count = 0
    for index = 1, #loadout.entries do
        if loadout.entries[index].desired == true then
            count = count + 1
        end
    end
    return count
end

function Loadouts.DescribeEntry(row)
    if type(row) ~= "table" then
        return nil
    end

    local api = GetAPI()
    local entryId = NormalizeId(row.entryId)
    local entryType = NormalizeEntryType(row.entryType)
    local spellId = NormalizeId(row.spellId)
    local name = row.name
    local icon

    if api then
        if entryId and (not name or not icon) then
            name = name or api.GetEntryName(entryId)
            icon = icon or api.GetEntryIcon(entryId)
        end
        if spellId and (not name or not icon) then
            name = name or api.GetEntryName(spellId)
            icon = icon or api.GetEntryIcon(spellId)
        end
    end

    local Wishlist = GetWishlist()
    local desired = row.desired == true
    if Wishlist and Wishlist.IsItemDesired and entryId and entryType then
        local probe = { entryId = entryId, entryType = entryType, spellId = spellId, name = name }
        desired = Wishlist.IsItemDesired(probe) == true or desired
    end

    return {
        entryId = entryId,
        entryType = entryType,
        spellId = spellId,
        name = name or ("Entry " .. tostring(entryId or spellId or "?")),
        icon = icon,
        desired = desired,
        displayId = entryId and ("e:" .. tostring(entryId)) or tostring(spellId or "?"),
    }
end

------------------------------------------------------------------------
-- Share string (ASUITE1)
------------------------------------------------------------------------

local function EscapeShareName(name)
    if type(name) ~= "string" then
        return "?"
    end
    return name:gsub(";", ",")
end

function Loadouts.ExportString(id)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return nil, "not_found"
    end

    local parts = {}
    local entries = type(loadout.entries) == "table" and loadout.entries or {}
    for index = 1, #entries do
        local row = entries[index]
        if type(row) == "table" then
            local entryType = NormalizeEntryType(row.entryType) or "Ability"
            local entryId = NormalizeId(row.entryId)
            if entryId then
                local name = EscapeShareName(row.name or ("e" .. tostring(entryId)))
                parts[#parts + 1] = entryType .. ":" .. tostring(entryId) .. ":" .. name
            end
        end
    end

    local name = loadout.name or "build"
    local body = table.concat(parts, ";")
    if body == "" then
        body = ""
    end
    return SHARE_PREFIX .. "|" .. name .. "|" .. tostring(#parts) .. "|" .. body
end

local function ParseShareEntry(token)
    if type(token) ~= "string" or token == "" then
        return nil
    end
    local entryType, entryId, name = token:match("^([^:]+):(%d+):(.+)$")
    entryType = NormalizeEntryType(entryType)
    entryId = NormalizeId(entryId)
    if not entryType or not entryId then
        return nil
    end
    return {
        entryType = entryType,
        entryId = entryId,
        name = name,
    }
end

function Loadouts.ImportString(text, shared)
    if type(text) ~= "string" then
        return nil, "invalid"
    end
    text = text:match("^%s*(.-)%s*$")
    if text == "" then
        return nil, "empty"
    end

    local prefix, name, countText, body = text:match("^([^|]+)|([^|]*)|(%d+)|(.*)$")
    if prefix ~= SHARE_PREFIX then
        return nil, "bad_prefix"
    end

    name = name:match("^%s*(.-)%s*$")
    if name == "" then
        name = "Imported build"
    end

    local expected = tonumber(countText) or 0
    local entries = {}
    if body and body ~= "" then
        for token in body:gmatch("[^;]+") do
            local row = ParseShareEntry(token)
            if row then
                entries[#entries + 1] = row
            end
        end
    end

    if expected > 0 and #entries ~= expected then
        return nil, "count_mismatch"
    end

    if CountLoadouts() >= MAX_LOADOUTS then
        return nil, "loadout_limit"
    end

    local loadout, id = Loadouts.Create(name, "Imported from share string.", shared)
    if not loadout then
        return nil, id
    end
    loadout.entries = entries
    loadout.updatedAt = Now()
    return loadout, id
end

function Loadouts.FormatRefuseSummary(refuses, maxNames)
    if type(refuses) ~= "table" or #refuses == 0 then
        return nil
    end
    maxNames = maxNames or 3
    local parts = {}
    for index = 1, math.min(#refuses, maxNames) do
        local row = refuses[index]
        local label = row.name or "?"
        local reason = row.reason or "refused"
        parts[#parts + 1] = label .. " (" .. reason .. ")"
    end
    local tail = ""
    if #refuses > maxNames then
        tail = string.format(" +%d more", #refuses - maxNames)
    end
    return table.concat(parts, ", ") .. tail
end
