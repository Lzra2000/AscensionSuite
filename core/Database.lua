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
    version = 4,
    assists = {
        autoRoll = false,
        instantDiceSkip = false,
        instantSkillCardSkip = false,
        acceptWildcardPopups = false,
        captureRolls = false,
    },
    wishlistSpellIds = {},
    wishlistEntries = {},
    desiredProfiles = {},
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

    if type(db.wishlistSpellIds) ~= "table" then
        db.wishlistSpellIds = {}
    end

    if type(db.wishlistEntries) ~= "table" then
        db.wishlistEntries = {}
    end

    if type(db.desiredProfiles) ~= "table" then
        db.desiredProfiles = {}
    end

    if type(db.logbook) ~= "table" then
        db.logbook = {}
    end

    -- Migrate v2 marks/profiles into wishlist spell ids only (best-effort).
    if db.version < 3 then
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

function DB.GetWishlistSpellIds()
    return DB.Get().wishlistSpellIds
end

function DB.SetWishlistSpellIds(spellIds)
    DB.Get().wishlistSpellIds = spellIds
end

function DB.GetLogbook()
    return DB.Get().logbook
end
