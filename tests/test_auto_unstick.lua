-- AscensionSuite: tests/test_auto_unstick.lua
-- Opt-in auto-unstick detects gray Continue and calls RecoverStuckRapidSession.

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

local updateScripts = {}
local now = 1000

CreateFrame = function()
    local frame = {}
    frame.RegisterEvent = Noop
    frame.IsShown = function() return false end
    frame.SetScript = function(self, script, fn)
        if script == "OnUpdate" then
            updateScripts[self] = fn
        end
    end
    return frame
end

function GetTime() return now end

local rapidState = { Phase = "Idle" }
local diceShown = true
local recoverCalls = 0
local unstickCalls = 0

_G.C_Wildcard = {
    IsGameModeActive = function() return true end,
}
_G.C_GameMode = {
    GetGameMode = function() return 1 end,
}

_G.WildCardDice = {
    isRapidRolling = true,
    pendingReveal = { 2001, 1 },
    IsShown = function() return diceShown end,
    Hide = function(self) diceShown = false end,
    Core = {
        State = { IDLE = "IDLE" },
        GetState = function() return "REVEALING" end,
    },
}

_G.WildCardRapidRollingFrame = {
    IsShown = function() return true end,
    Roll = Noop,
    UpdateRollButton = Noop,
    RegisterEvent = Noop,
    RollingFrame = {
        ErrorFrame = { Hide = Noop },
        RollButton = {
            IsEnabled = function() return false end,
            Enable = Noop,
        },
    },
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/automation/AutoUnstick.lua")

AscensionSuite.Database.Init()
local API = AscensionSuite.AscensionAPI
local AutoUnstick = AscensionSuite.AutoUnstick

API.IsWildcardModeActive = function() return true end
API.GetRapidRollingState = function() return rapidState end
API.RecoverStuckRapidSession = function()
    recoverCalls = recoverCalls + 1
    return true
end

AscensionSuite.MainWindow = {
    UnstickRapid = function()
        unstickCalls = unstickCalls + 1
        if API.RecoverDiceInteraction then
            return API.RecoverDiceInteraction()
        end
        return API.RecoverStuckRapidSession()
    end,
}

assert(AscensionSuiteDB.assists.autoUnstick == false, "autoUnstick default off")
assert(API.IsRapidRollingContinueStuck(rapidState) == true,
    "idle phase with active die counts as stuck Continue")

rapidState.Phase = "Revealing"
assert(API.IsRapidRollingContinueStuck(rapidState) == false,
    "in-flight reveal is not the gray-Continue hang")

rapidState.Phase = "AwaitingContinue"
_G.WildCardDice.pendingReveal = nil
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
assert(API.IsRapidRollingContinueStuck(rapidState) == false,
    "actionable Continue is not stuck")

------------------------------------------------------------------------
-- AutoUnstick ticks recover after the stuck window, with cooldown
------------------------------------------------------------------------

rapidState.Phase = "Idle"
_G.WildCardDice.pendingReveal = { 2001, 1 }
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
diceShown = true
recoverCalls = 0
unstickCalls = 0

AscensionSuiteDB.assists.autoUnstick = true
AutoUnstick.Init()

local function RunTick(seconds)
    for frame, fn in pairs(updateScripts) do
        if fn then
            fn(frame, seconds)
        end
    end
end

RunTick(2)
assert(recoverCalls == 0, "recovery waits for the stuck window")

RunTick(3)
assert(recoverCalls == 0, "phase-stable time must reach five seconds")

RunTick(2)
assert(unstickCalls == 1, "auto-unstick calls the shared Unstick path")
assert(recoverCalls == 1, "and RecoverDiceInteraction runs once")

RunTick(10)
assert(recoverCalls == 1, "cooldown blocks a second recovery")

now = now + 35
RunTick(2)
RunTick(3)
RunTick(2)
assert(recoverCalls == 2, "after cooldown another stuck window can recover")

-- Leveling die shown in READY_TO_ROLL with mouse disabled also recovers.
API.RecoverDiceInteraction = function()
    recoverCalls = recoverCalls + 1
    return true, "mouse_restored"
end
API.IsDiceShownUnclickable = function() return true end
API.IsDiceInteractionStuck = function() return true end
API.IsRapidRollingContinueStuck = function() return false end
rapidState.Phase = "Idle"
_G.WildCardDice.isRapidRolling = false
_G.WildCardDice.pendingReveal = nil
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
recoverCalls = 0
unstickCalls = 0
now = now + 35
RunTick(2)
RunTick(3)
RunTick(2)
assert(unstickCalls == 1, "unclickable leveling die triggers Unstick")
assert(recoverCalls == 1, "through RecoverDiceInteraction")

AscensionSuiteDB.assists.autoUnstick = false
AutoUnstick.Refresh()
recoverCalls = 0
RunTick(10)
assert(recoverCalls == 0, "turning the assist off stops recovery")

print("OK: AscensionSuite auto-unstick test passed")
