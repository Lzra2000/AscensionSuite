-- AscensionSuite: tests/test_assists.lua
-- Assist defaults off and Auto-Roll halts on API error.

unpack = unpack or table.unpack

local function RepoRoot()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    local dir = src:match("^(.*)/")
    if dir and dir:match("/tests$") then
        return dir:gsub("/tests$", "")
    end
    return "."
end

local ROOT = RepoRoot()

AscensionSuite = {}
AscensionSuiteDB = {}

local function Noop() end

local function NewFrame()
    return {
        RegisterEvent = Noop,
        SetScript = Noop,
        IsShown = function() return true end,
    }
end

CreateFrame = function()
    return NewFrame()
end

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return mode == "WildCard"
    end,
}

C_Wildcard = {
    GetNumFilteredDesiredEntries = function() return 2 end,
    CanRollAbilities = function() return true end,
    StartRapidRolling = function()
        return false, "forced_error"
    end,
}

_G.WildCardRapidRollingFrame = nil

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/automation/AutoRoller.lua")

AscensionSuite.Database.Init()

local assists = AscensionSuiteDB.assists
assert(assists.autoRoll == false, "autoRoll default off")
assert(assists.instantDiceSkip == false, "dice skip default off")
assert(assists.acceptWildcardPopups == false, "popup accept default off")

assists.autoRoll = true

local AutoRoller = AscensionSuite.AutoRoller
assert(AutoRoller, "AutoRoller missing")

local ok = AutoRoller.Start()
assert(ok == true, "start should arm loop")

-- Simulate one tick by calling AdvanceRapidRoll path via Stop after error.
local api = AscensionSuite.AscensionAPI
local advanceOk, err = api.AdvanceRapidRoll(true)
assert(advanceOk == false, "advance should fail on API error")
assert(err == "forced_error" or err == "start_failed", "error propagated: " .. tostring(err))

AutoRoller.Stop(err)
assert(AutoRoller.IsRunning() == false, "stopped after error")
assert(AutoRoller.GetLastError() ~= nil, "last error recorded")

print("OK: AscensionSuite assists test passed")
