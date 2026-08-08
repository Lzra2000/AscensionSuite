-- AscensionSuite: core/Database.lua
-- SavedVariables defaults. Every assist defaults off until the player opts in.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local DB = {}
AscensionSuite.Database = DB

local DEFAULTS = {
    version = 7,
    assists = {
        autoRoll = false,
        autoRollContinue = false,
        instantDiceSkip = false,
        instantSkillCardSkip = false,
        acceptWildcardPopups = false,
        captureRolls = false,
        autoUnstick = false,
    },
    wishlist = {},
    desiredProfiles = {},
    loadouts = {},
    logbook = {},
}

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

local function EnsureDefaults(db)
    if type(db) ~= "table" then
        return CopyTable(DEFAULTS)
    end

    if db.version == nil then
        db.version = DEFAULTS.version
    end

    if type(db.assists) ~= "table" then
        db.assists = CopyTable(DEFAULTS.assists)
    else
        for key, value in pairs(DEFAULTS.assists) do
            if db.assists[key] == nil then
                db.assists[key] = value
            end
        end
    end

    if type(db.wishlist) ~= "table" then
        db.wishlist = {}
    end

    if type(db.desiredProfiles) ~= "table" then
        db.desiredProfiles = {}
    end

    if type(db.loadouts) ~= "table" then
        db.loadouts = {}
    end

    if type(db.logbook) ~= "table" then
        db.logbook = {}
    end

    -- Migrate v2 marks/profiles into wishlist spell ids only (best-effort).
    if db.version < 3 then
        if type(db.wishlistSpellIds) ~= "table" then
            db.wishlistSpellIds = {}
        end
        if type(db.proofSpellIds) == "table" and #db.wishlistSpellIds == 0 then
            for index = 1, #db.proofSpellIds do
                db.wishlistSpellIds[#db.wishlistSpellIds + 1] = db.proofSpellIds[index]
            end
        end
        if type(db.marks) == "table" then
            for key in pairs(db.marks) do
                local spellId = tonumber(key)
                if spellId then
                    local found = false
                    for index = 1, #db.wishlistSpellIds do
                        if db.wishlistSpellIds[index] == spellId then
                            found = true
                            break
                        end
                    end
                    if not found then
                        db.wishlistSpellIds[#db.wishlistSpellIds + 1] = spellId
                    end
                end
            end
        end
        db.marks = nil
        db.profiles = nil
        db.proofSpellIds = nil
        db.version = 3
    end

    -- v4 adds the tracked Desired entry registry. Nothing to carry over: a
    -- v3 save has only spell ids, which CollectTracked still resolves.
    if db.version < 4 then
        db.version = 4
    end

    -- v5 folds the two v4 stores into one player-owned wishlist. The spell id
    -- grid and the tracked (id, type) registry were always two views of the same
    -- list, and a row can now carry both halves. Entry pairs go in first so the
    -- spell ids they already resolve to do not create duplicate rows.
    if db.version < 5 then
        local seenPair, seenSpell = {}, {}

        if type(db.wishlistEntries) == "table" then
            for index = 1, #db.wishlistEntries do
                local row = db.wishlistEntries[index]
                if type(row) == "table" and tonumber(row.id) and type(row.type) == "string" then
                    local key = row.type .. ":" .. tostring(row.id)
                    if not seenPair[key] then
                        seenPair[key] = true
                        local spellId = tonumber(row.spellId)
                        if spellId then
                            seenSpell[spellId] = true
                        end
                        db.wishlist[#db.wishlist + 1] = {
                            spellId = spellId,
                            entryId = tonumber(row.id),
                            entryType = row.type,
                            name = row.name,
                        }
                    end
                end
            end
        end

        if type(db.wishlistSpellIds) == "table" then
            for index = 1, #db.wishlistSpellIds do
                local spellId = tonumber(db.wishlistSpellIds[index])
                if spellId and not seenSpell[spellId] then
                    seenSpell[spellId] = true
                    db.wishlist[#db.wishlist + 1] = { spellId = spellId }
                end
            end
        end

        db.wishlistEntries = nil
        db.wishlistSpellIds = nil
        db.version = 5
    end

    -- v6 adds named loadouts and migrates legacy desiredProfiles into them.
    if db.version < 6 then
        if type(db.loadouts) ~= "table" then
            db.loadouts = {}
        end

        local function ProfileToLoadout(name, profile)
            if type(profile) ~= "table" then
                return nil
            end
            local entries = {}
            if type(profile.wishlist) == "table" then
                for index = 1, #profile.wishlist do
                    local row = profile.wishlist[index]
                    if type(row) == "table" then
                        entries[#entries + 1] = {
                            entryId = tonumber(row.entryId),
                            entryType = row.entryType,
                            spellId = tonumber(row.spellId),
                            name = row.name,
                        }
                    end
                end
            end
            if type(profile.entries) == "table" then
                for index = 1, #profile.entries do
                    local row = profile.entries[index]
                    if type(row) == "table" and tonumber(row.id) and type(row.type) == "string" then
                        local found = false
                        for scan = 1, #entries do
                            local existing = entries[scan]
                            if existing.entryId == tonumber(row.id) and existing.entryType == row.type then
                                existing.desired = true
                                found = true
                                break
                            end
                        end
                        if not found then
                            entries[#entries + 1] = {
                                entryId = tonumber(row.id),
                                entryType = row.type,
                                spellId = tonumber(row.spellId),
                                desired = true,
                            }
                        end
                    end
                end
            end
            local slug = name:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
            if slug == "" then
                slug = "profile"
            end
            local id = slug .. "-migrated"
            local suffix = 1
            while db.loadouts[id] do
                suffix = suffix + 1
                id = slug .. "-migrated-" .. tostring(suffix)
            end
            return {
                id = id,
                name = name,
                notes = "Migrated from Assists Desired profile.",
                entries = entries,
                knownSnapshot = profile.knownSnapshot,
                updatedAt = 0,
                character = "shared",
            }, id
        end

        if type(db.desiredProfiles) == "table" then
            for profileName, profile in pairs(db.desiredProfiles) do
                if type(profileName) == "string" and db.loadouts then
                    local loadout, id = ProfileToLoadout(profileName, profile)
                    if loadout and id and not db.loadouts[id] then
                        db.loadouts[id] = loadout
                    end
                end
            end
        end

        db.version = 6
    end

    -- v7 adds archetype-style sections, tags, and equipment stubs on loadouts.
    if db.version < 7 then
        if type(db.loadouts) == "table" then
            for _, loadout in pairs(db.loadouts) do
                if type(loadout) == "table" then
                    if type(loadout.sections) ~= "table" then
                        loadout.sections = { OVERVIEW = loadout.notes or "" }
                    end
                    if type(loadout.equipment) ~= "table" then
                        loadout.equipment = { armorTypes = {}, weaponTypes = {} }
                    end
                    if loadout.author == nil then
                        loadout.author = loadout.character or "shared"
                    end
                end
            end
        end
        db.version = 7
    end

    return db
end

function DB.Init()
    AscensionSuiteDB = EnsureDefaults(AscensionSuiteDB)
    DB.data = AscensionSuiteDB
end

function DB.Get()
    if not DB.data then
        DB.Init()
    end
    return DB.data
end

function DB.GetAssists()
    return DB.Get().assists
end

function DB.GetWishlist()
    return DB.Get().wishlist
end

function DB.GetLogbook()
    return DB.Get().logbook
end
