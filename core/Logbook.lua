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

local function BuildRecord(spellOrEntryId, entryTypeOverride)
    local api = GetAPI()
    if not api then
        return nil
    end

    local spellId = api.GetEntrySpellID(spellOrEntryId) or tonumber(spellOrEntryId)
    local entryId = api.GetEntryInternalID(spellOrEntryId)
    local name = api.GetEntryName(spellOrEntryId)
    local icon = api.GetEntryIcon(spellOrEntryId)
    local entryType = entryTypeOverride or api.GetEntryType(spellOrEntryId)

    return {
        spellId = spellId,
        entryId = entryId,
        name = name,
        icon = icon,
        entryType = NormalizeEntryType(entryType),
        timestamp = time and time() or 0,
    }
end

function Logbook.Append(spellOrEntryId, entryTypeOverride)
    if not AssistsEnabled() then
        return false
    end

    local record = BuildRecord(spellOrEntryId, entryTypeOverride)
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

local function OnWildcardLearned(_, internalID)
    if internalID then
        Logbook.Append(internalID)
    end
end

local function OnSpellsChanged()
    if not AssistsEnabled() then
        return
    end
    -- Known updates are observed for future diffing; roll events are primary.
end

function Logbook.Init()
    if frame then
        return
    end

    frame = CreateFrame("Frame")
    frame:RegisterEvent("WILDCARD_RAPID_ROLL_LEARNED")
    frame:RegisterEvent("WILDCARD_ENTRY_LEARNED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "WILDCARD_RAPID_ROLL_LEARNED" or event == "WILDCARD_ENTRY_LEARNED" then
            OnWildcardLearned(event, arg1)
        elseif event == "SPELLS_CHANGED" then
            OnSpellsChanged()
        end
    end)
end
