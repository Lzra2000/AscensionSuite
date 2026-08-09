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

-- Mirrors BuildCreatorUtil.DescriptionSection keys (read-only reference).
Loadouts.SECTION_ORDER = {
    "OVERVIEW",
    "SPELLS_AND_TALENTS",
    "EQUIPMENT",
    "PROS_AND_CONS",
    "ITEMIZATION",
    "ROTATION",
    "CONSUMABLES",
    "MACROS",
    "WEAKAURAS",
    "NOTES",
}

Loadouts.SECTION_LABELS = {
    OVERVIEW = "Overview",
    SPELLS_AND_TALENTS = "Spells and Talents",
    EQUIPMENT = "Equipment",
    PROS_AND_CONS = "Pros and Cons",
    ITEMIZATION = "Itemization",
    ROTATION = "Rotation",
    CONSUMABLES = "Enchants and Consumables",
    MACROS = "Macros",
    WEAKAURAS = "WeakAuras",
    NOTES = "Additional Notes",
}

Loadouts.SECTION_HINTS = {
    SPELLS_AND_TALENTS = "automation source",
}

Loadouts.CATEGORY_CYCLE = { "PvE", "PvP" }
Loadouts.COMPLEXITY_CYCLE = { "Standard", "Intermediate", "Advanced", "Expert", "Impossible" }

local IMPORT_ERROR_MESSAGES = {
    not_found = "build not found",
    no_api = "Ascension API unavailable",
    no_build = "no importable build — open Archetypes in the editor, draft one, or activate a build first",
    no_spells = "that build has no spells to import",
}

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

local function EmptySections()
    local sections = {}
    for index = 1, #Loadouts.SECTION_ORDER do
        local key = Loadouts.SECTION_ORDER[index]
        sections[key] = ""
    end
    return sections
end

local function NormalizeSections(source, fallbackNotes)
    local sections = EmptySections()
    if type(source) == "table" then
        for key, value in pairs(source) do
            if type(key) == "string" and sections[key] ~= nil and type(value) == "string" then
                sections[key] = value
            end
        end
    end
    if fallbackNotes and fallbackNotes ~= "" and sections.OVERVIEW == "" then
        sections.OVERVIEW = fallbackNotes
    end
    return sections
end

local function NormalizeTags(tags)
    if type(tags) ~= "table" then
        return {}
    end
    return {
        core = tags.core == true,
        optimal = tags.optimal == true,
        empowering = tags.empowering == true,
        synergistic = tags.synergistic == true,
    }
end

local function TagLabel(tags)
    tags = NormalizeTags(tags)
    if tags.core then
        return "Core"
    end
    if tags.optimal then
        return "Optimal"
    end
    if tags.empowering then
        return "Empowering"
    end
    if tags.synergistic then
        return "Synergistic"
    end
    return "Utility"
end

local function EntryPassesFilters(row, filters)
    if type(row) ~= "table" then
        return false
    end
    if type(filters) ~= "table" then
        return true
    end
    local tags = NormalizeTags(row.tags)
    if tags.core and filters.core == false then
        return false
    end
    if tags.optimal and filters.optimal == false then
        return false
    end
    if tags.empowering and filters.empowering == false then
        return false
    end
    if tags.synergistic and filters.synergistic == false then
        return false
    end
    if not tags.core and not tags.optimal and not tags.empowering and not tags.synergistic then
        return true
    end
    return true
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

local function NormalizeEquipmentList(list)
    local rows = {}
    if type(list) ~= "table" then
        return rows
    end
    local api = GetAPI()
    for index = 1, #list do
        local item = list[index]
        local typeKey, comment
        if api and api.NormalizeEquipmentStub then
            typeKey, comment = api.NormalizeEquipmentStub(item)
        elseif type(item) == "table" then
            typeKey = item.type or item.Type
            comment = item.comment or item.Comment or ""
        elseif type(item) == "string" then
            typeKey = item
            comment = ""
        end
        if typeKey then
            rows[#rows + 1] = { type = typeKey, comment = comment or "" }
        end
    end
    return rows
end

local function CycleValue(current, options)
    if type(options) ~= "table" or #options == 0 then
        return nil
    end
    if current == nil or current == "" then
        return options[1]
    end
    for index = 1, #options do
        if options[index] == current then
            if index >= #options then
                return nil
            end
            return options[index + 1]
        end
    end
    return options[1]
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

function Loadouts.ResolveEntryRow(row)
    if type(row) ~= "table" then
        return nil, nil, "invalid_row"
    end
    local entryId, entryType, _, err = ResolveRow(row)
    if entryId and entryType then
        row.entryId = entryId
        row.entryType = entryType
    end
    return entryId, entryType, err
end

local function PushRowsToDesired(rows)
    local api = GetAPI()
    if not api then
        return 0, 0, 0, "no_api", {}
    end
    if not api.IsWildcardModeActive() then
        return 0, 0, 0, "not_wildcard", {}
    end

    local pushed, already, failed = 0, 0, 0
    local refuses = {}
    if type(rows) ~= "table" then
        return pushed, already, failed, nil, refuses
    end

    for index = 1, #rows do
        local row = rows[index]
        if type(row) == "table" then
            local label = row.name or tostring(row.spellId or row.entryId or "?")
            local entryId, entryType, resolveErr = Loadouts.ResolveEntryRow(row)
            if not entryId then
                failed = failed + 1
                refuses[#refuses + 1] = { name = label, reason = resolveErr or "unresolved" }
            elseif api.IsDesiredID(entryId, entryType) then
                already = already + 1
            elseif not api.CanAddDesiredID(entryId, entryType) then
                failed = failed + 1
                refuses[#refuses + 1] = { name = label, reason = "refused" }
            else
                local added, addReason = api.AddDesiredID(entryId, entryType)
                if added then
                    pushed = pushed + 1
                else
                    failed = failed + 1
                    refuses[#refuses + 1] = { name = label, reason = addReason or "add_failed" }
                end
            end
        end
    end
    return pushed, already, failed, nil, refuses
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
    local loadout = store[id]
    if loadout then
        Loadouts.EnsureLoadoutShape(loadout)
    end
    return loadout
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
        sections = EmptySections(),
        author = PlayerName(),
        category = nil,
        complexity = nil,
        equipment = { armorTypes = {}, weaponTypes = {} },
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

function Loadouts.EnsureLoadoutShape(loadout)
    if type(loadout) ~= "table" then
        return loadout
    end
    loadout.sections = NormalizeSections(loadout.sections, loadout.notes)
    if type(loadout.equipment) ~= "table" then
        loadout.equipment = { armorTypes = {}, weaponTypes = {} }
    else
        loadout.equipment.armorTypes = NormalizeEquipmentList(loadout.equipment.armorTypes)
        loadout.equipment.weaponTypes = NormalizeEquipmentList(loadout.equipment.weaponTypes)
    end
    if type(loadout.entries) ~= "table" then
        loadout.entries = {}
    end
    for index = 1, #loadout.entries do
        local row = loadout.entries[index]
        if type(row) == "table" then
            row.tags = NormalizeTags(row.tags)
        end
    end
    return loadout
end

function Loadouts.GetSectionLabel(key)
    return Loadouts.SECTION_LABELS[key] or key
end

function Loadouts.GetSections(loadout)
    if type(loadout) ~= "table" then
        return EmptySections()
    end
    return NormalizeSections(loadout.sections, loadout.notes)
end

function Loadouts.SetSectionText(id, key, text)
    local loadout = Loadouts.Get(id)
    if not loadout or type(key) ~= "string" then
        return false, "not_found"
    end
    Loadouts.EnsureLoadoutShape(loadout)
    if loadout.sections[key] == nil then
        return false, "bad_section"
    end
    loadout.sections[key] = type(text) == "string" and text or ""
    if key == "OVERVIEW" then
        loadout.notes = loadout.sections.OVERVIEW
    end
    loadout.updatedAt = Now()
    return true
end

function Loadouts.UpdateMeta(id, patch)
    local loadout = Loadouts.Get(id)
    if not loadout or type(patch) ~= "table" then
        return false, "not_found"
    end
    Loadouts.EnsureLoadoutShape(loadout)
    if type(patch.name) == "string" then
        local name = patch.name:match("^%s*(.-)%s*$")
        if name ~= "" then
            loadout.name = name
        end
    end
    if patch.author ~= nil then
        loadout.author = tostring(patch.author)
    end
    if patch.category ~= nil then
        loadout.category = patch.category
    end
    if patch.complexity ~= nil then
        loadout.complexity = patch.complexity
    end
    loadout.updatedAt = Now()
    return true
end

function Loadouts.AddEntry(id, row)
    local loadout = Loadouts.Get(id)
    if not loadout or type(row) ~= "table" then
        return false, "not_found"
    end
    Loadouts.EnsureLoadoutShape(loadout)
    if #loadout.entries >= MAX_ENTRIES then
        return false, "entry_limit"
    end

    local entryId = NormalizeId(row.entryId)
    local entryType = NormalizeEntryType(row.entryType)
    local spellId = NormalizeId(row.spellId)
    if not entryId and spellId then
        local api = GetAPI()
        if api and api.ResolveEntry then
            local entry = api.ResolveEntry(spellId)
            if entry then
                entryId = NormalizeId(entry.ID or entry.Id or entry.id)
                entryType = entryType or NormalizeEntryType(entry.Type or entry.type)
            end
        end
    end

    for index = 1, #loadout.entries do
        local existing = loadout.entries[index]
        if existing.entryId == entryId and existing.entryType == entryType then
            return false, "duplicate"
        end
    end

    loadout.entries[#loadout.entries + 1] = {
        entryId = entryId,
        entryType = entryType,
        spellId = spellId,
        name = row.name,
        desired = row.desired == true,
        tags = NormalizeTags(row.tags),
        classGroup = row.classGroup,
    }
    loadout.updatedAt = Now()
    return true
end

function Loadouts.ImportFromArchetype(id)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end
    local api = GetAPI()
    if not api or not api.GetImportableBuild or not api.CollectBuildSpellEntries then
        return false, "no_api"
    end

    local build, source = api.GetImportableBuild()
    if not build then
        local message = source
        if api.DescribeImportableBuildFailure then
            message = api.DescribeImportableBuildFailure(source)
        end
        return false, message or "no_build"
    end

    Loadouts.EnsureLoadoutShape(loadout)
    local entries = api.CollectBuildSpellEntries(build)
    if #entries == 0 then
        return false, "no_spells"
    end

    loadout.entries = {}
    for index = 1, math.min(#entries, MAX_ENTRIES) do
        local row = entries[index]
        loadout.entries[#loadout.entries + 1] = {
            entryId = row.entryId,
            entryType = row.entryType,
            spellId = row.spellId,
            name = row.name,
            desired = row.desired == true,
            tags = NormalizeTags(row.tags),
            classGroup = row.classGroup,
        }
    end

    if api.UnpackBuildDescription and type(build.Description) == "string" then
        local unpacked = api.UnpackBuildDescription(build.Description)
        for key, text in pairs(unpacked) do
            if loadout.sections[key] ~= nil then
                loadout.sections[key] = text
            end
        end
        if loadout.sections.OVERVIEW ~= "" then
            loadout.notes = loadout.sections.OVERVIEW
        end
    end

    if api.CollectBuildEquipmentStubs then
        loadout.equipment = api.CollectBuildEquipmentStubs(build)
    end

    if build.Name and build.Name ~= "" then
        loadout.name = build.Name
    end
    if build.AuthorName and build.AuthorName ~= "" then
        loadout.author = build.AuthorName
    end
    if api.DescribeBuildCategory then
        loadout.category = api.DescribeBuildCategory(build.Category) or loadout.category
    end
    if api.DescribeBuildDifficulty then
        loadout.complexity = api.DescribeBuildDifficulty(build.Difficulty) or loadout.complexity
    end

    loadout.updatedAt = Now()
    return true, #loadout.entries, source
end

function Loadouts.GroupEntries(entries, filters)
    local groups = {}
    local order = {}
    if type(entries) ~= "table" then
        return groups, order, 0
    end

    local total = 0
    for index = 1, #entries do
        local described = Loadouts.DescribeEntry(entries[index])
        if described and EntryPassesFilters(entries[index], filters) then
            total = total + 1
            local label = entries[index].classGroup or described.classGroup or "Other"
            if not groups[label] then
                groups[label] = {}
                order[#order + 1] = label
            end
            described.tagLabel = TagLabel(entries[index].tags)
            groups[label][#groups[label] + 1] = described
        end
    end
    return groups, order, total
end

function Loadouts.ResetToSaved(id)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end
    Loadouts.EnsureLoadoutShape(loadout)
    return true
end

function Loadouts.Rename(id, name, notes)
    local loadout = Loadouts.Get(id)
    if not loadout then
        return false, "not_found"
    end
    Loadouts.EnsureLoadoutShape(loadout)
    if type(name) == "string" then
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then
            loadout.name = name
        end
    end
    if type(notes) == "string" then
        loadout.notes = notes
        loadout.sections.OVERVIEW = notes
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
            Loadouts.ResolveEntryRow(row)
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
                    local items = Wishlist.GetItems()
                    local item = items[#items]
                    if type(item) == "table" then
                        Loadouts.ResolveEntryRow(item)
                    end
                end
            end
        end
    end
    return true, added
end

function Loadouts.PushToDesired(id, filters)
    local loadout = Loadouts.Get(id)
    if not loadout or type(loadout.entries) ~= "table" then
        return 0, 0, 0, "not_found", {}
    end

    local rows = {}
    for index = 1, #loadout.entries do
        local row = loadout.entries[index]
        if type(row) == "table" and EntryPassesFilters(row, filters) then
            rows[#rows + 1] = row
        end
    end
    return PushRowsToDesired(rows)
end

function Loadouts.Apply(id, filters)
    local ok, count = Loadouts.LoadToWishlist(id)
    if not ok then
        return false, count, nil
    end

    local pushed, already, failed, gate, refuses = Loadouts.PushToDesired(id, filters)
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
    local count = type(loadout.knownSnapshot) == "table" and #loadout.knownSnapshot or 0
    return true, count
end

function Loadouts.DescribeImportError(code)
    if type(code) == "string" and IMPORT_ERROR_MESSAGES[code] then
        return IMPORT_ERROR_MESSAGES[code]
    end
    if type(code) == "string" then
        return code
    end
    return "import failed"
end

function Loadouts.CycleCategory(current)
    return CycleValue(current, Loadouts.CATEGORY_CYCLE)
end

function Loadouts.CycleComplexity(current)
    return CycleValue(current, Loadouts.COMPLEXITY_CYCLE)
end

function Loadouts.DescribeEquipmentStub(stub)
    if type(stub) ~= "table" then
        return nil
    end
    local api = GetAPI()
    local typeKey = stub.type or stub.Type
    local name, icon, isArmor
    if api and api.GetEquipmentTypeIconAndName then
        name, icon, isArmor = api.GetEquipmentTypeIconAndName(typeKey)
    end
    name = name or typeKey or "?"
    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    return {
        type = typeKey,
        name = name,
        icon = icon,
        isArmor = isArmor == true,
        comment = stub.comment or stub.Comment or "",
    }
end

function Loadouts.CountFiltered(loadout, filters)
    if type(loadout) ~= "table" or type(loadout.entries) ~= "table" then
        return 0
    end
    local total = 0
    for index = 1, #loadout.entries do
        if EntryPassesFilters(loadout.entries[index], filters) then
            total = total + 1
        end
    end
    return total
end

function Loadouts.CountFilteredDesired(loadout, filters)
    if type(loadout) ~= "table" or type(loadout.entries) ~= "table" then
        return 0, 0
    end

    local Wishlist = GetWishlist()
    local api = GetAPI()
    local desired = 0
    local total = 0

    for index = 1, #loadout.entries do
        local row = loadout.entries[index]
        if type(row) == "table" and EntryPassesFilters(row, filters) then
            total = total + 1
            local entryId, entryType = Loadouts.ResolveEntryRow(row)
            local isDesired = row.desired == true
            if Wishlist and Wishlist.IsItemDesired and entryId and entryType then
                isDesired = Wishlist.IsItemDesired({
                    entryId = entryId,
                    entryType = entryType,
                    spellId = row.spellId,
                    name = row.name,
                }) == true or isDesired
            elseif api and entryId and entryType and api.IsDesiredID then
                isDesired = api.IsDesiredID(entryId, entryType) == true or isDesired
            end
            if isDesired then
                desired = desired + 1
            end
        end
    end
    return desired, total
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
        tagLabel = TagLabel(row.tags),
        classGroup = row.classGroup,
    }
end

------------------------------------------------------------------------
-- Share string (ASUITE1)
------------------------------------------------------------------------

local function EscapeShareName(name)
    if type(name) ~= "string" then
        return "?"
    end
    return name:gsub(";", ","):gsub(":", ",")
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
            local entryId, entryType = Loadouts.ResolveEntryRow(row)
            entryType = NormalizeEntryType(entryType) or "Ability"
            if entryId then
                local name = EscapeShareName(row.name or ("e" .. tostring(entryId)))
                parts[#parts + 1] = entryType .. ":" .. tostring(entryId) .. ":" .. name
            end
        end
    end

    local name = loadout.name or "build"
    local body = table.concat(parts, ";")
    return SHARE_PREFIX .. "|" .. name .. "|" .. tostring(#parts) .. "|" .. body
end

local function ParseShareEntry(token)
    if type(token) ~= "string" or token == "" then
        return nil
    end
    local entryType, entryId, name = token:match("^([^:]+):(%d+):(.+)$")
    entryType = NormalizeEntryType(entryType)
    entryId = NormalizeId(entryId)
    if entryType and entryId then
        return {
            entryType = entryType,
            entryId = entryId,
            name = name,
        }
    end
    -- Legacy spellId:name tokens (pre-0.4.2 exports missing Type).
    local spellId, legacyName = token:match("^(%d+):(.+)$")
    spellId = NormalizeId(spellId)
    if spellId and legacyName and legacyName ~= "" then
        return {
            spellId = spellId,
            name = legacyName,
        }
    end
    return nil
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
