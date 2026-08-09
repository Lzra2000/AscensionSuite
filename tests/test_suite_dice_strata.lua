-- AscensionSuite: tests/test_suite_dice_strata.lua
-- WildCardDice demotes below AscensionSuiteMainWindow while /asuite is open.

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

local diceShown = true
local frameStrata
local frameLevel
local rollButtonLevel

local rollButton = {
    SetFrameLevel = function(_, level)
        rollButtonLevel = level
    end,
}

_G.WildCardDice = {
    IsShown = function()
        return diceShown
    end,
    GetFrameStrata = function()
        return frameStrata
    end,
    SetFrameStrata = function(_, strata)
        frameStrata = strata
    end,
    GetFrameLevel = function()
        return frameLevel
    end,
    SetFrameLevel = function(_, level)
        frameLevel = level
    end,
    RollButton = rollButton,
    Core = {
        State = { IDLE = "IDLE", READY_TO_ROLL = "READY_TO_ROLL", DECISION_PENDING = "DECISION_PENDING" },
        GetState = function()
            return "READY_TO_ROLL"
        end,
    },
    DiceEmptyEnter = { IsShown = function() return true end },
    Highlight = { Hide = function() end },
    OnLeave = function() end,
}

_G.AscensionSuiteMainWindow = {
    IsShown = function()
        return true
    end,
    GetFrameLevel = function()
        return 130
    end,
}

GameTooltip = { Hide = function() end }

dofile(ROOT .. "/integration/AscensionAPI.lua")

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")

frameStrata = "FULLSCREEN_DIALOG"
frameLevel = 128

assert(API.DemoteDiceBelowSuite() == true, "demote runs on shown die")
assert(frameStrata == "DIALOG", "demoted to DIALOG under Suite")
assert(frameLevel == 128, "frame level below Suite 130")
assert(rollButtonLevel == 129, "roll button above die but below Suite")

frameStrata = "FULLSCREEN_DIALOG"
frameLevel = 128
assert(API.SyncDiceLayeringForSuite() == true, "sync demotes")
assert(frameStrata == "DIALOG", "sync keeps dice under Suite")

print("OK: AscensionSuite suite dice strata test passed")
