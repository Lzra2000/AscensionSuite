-- AscensionSuite: core/Logbook.lua
-- Append rolled / known entries while leveling (opt-in capture assist).

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local Logbook = {}
AscensionSuite.Logbook = Logbook

local MAX_ENTRIES = 500

local frame

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

local function AssistsEnabled()
    local data = GetDB()
    return data and data.assists and data.assists.captureRolls == true
end

local function NormalizeEntryType(entryType)
    if type(entryType) ~= "string" then
        return "ability"
    end
    local lower = string.lower(entryType)
    if lower:find("talent", 1, true) then
        return "talent"
    end
    return "ability"
end

local function BuildRecord(internalId, newRank, preRollRank)
    local api = GetAPI()
    if not api then
        return nil
    end

    local described = api.DescribeRolledEntry(internalId, newRank, preRollRank)
    if not described then
        return nil
    end

    return {
        spellId = described.spellId,
        entryId = described.entryId,
        name = described.name,
        icon = described.icon,
        entryType = NormalizeEntryType(described.entryType),
        rank = described.rank,
        maxRank = described.maxRank,
        timestamp = time and time() or 0,
    }
end

function Logbook.Append(internalId, newRank, preRollRank)
    if not AssistsEnabled() then
        return false
    end

    local record = BuildRecord(internalId, newRank, preRollRank)
    if not record then
        return false
    end

    local data = GetDB()
    if type(data.logbook) ~= "table" then
        data.logbook = {}
    end

    data.logbook[#data.logbook + 1] = record
    while #data.logbook > MAX_ENTRIES do
        table.remove(data.logbook, 1)
    end

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshLogbook then
        MainWindow.RefreshLogbook()
    end
    return true
end

function Logbook.GetEntries()
    local data = GetDB()
    if type(data.logbook) ~= "table" then
        return {}
    end
    return data.logbook
end

function Logbook.Clear()
    local data = GetDB()
    data.logbook = {}
    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshLogbook then
        MainWindow.RefreshLogbook()
    end
end

function Logbook.Init()
    if frame then
        return
    end

    -- Both events carry (internalID, newRank, preRollRank); the rapid variant
    -- adds a stop reason. Rank matters because a talent upgrade reports the same
    -- internal ID at a new rank.
    frame = CreateFrame("Frame")
    frame:RegisterEvent("WILDCARD_RAPID_ROLL_LEARNED")
    frame:RegisterEvent("WILDCARD_ENTRY_LEARNED")
    frame:SetScript("OnEvent", function(_, event, internalId, newRank, preRollRank)
        if event ~= "WILDCARD_RAPID_ROLL_LEARNED" and event ~= "WILDCARD_ENTRY_LEARNED" then
            return
        end
        if internalId then
            Logbook.Append(internalId, newRank, preRollRank)
        end
    end)
end
