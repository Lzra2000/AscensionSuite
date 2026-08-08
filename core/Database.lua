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
    version = 1,
    assists = {
        autoRoll = false,
        instantDiceSkip = false,
        instantSkillCardSkip = false,
        acceptWildcardPopups = false,
    },
    proofSpellIds = {},
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

    if type(db.proofSpellIds) ~= "table" then
        db.proofSpellIds = {}
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

function DB.GetProofSpellIds()
    local data = DB.Get()
    return data.proofSpellIds
end

function DB.SetProofSpellIds(spellIds)
    local data = DB.Get()
    data.proofSpellIds = spellIds
end
