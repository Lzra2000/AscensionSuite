-- AscensionSuite: tests/test_suite_dice_strata.lua
-- WildCardDice demotes below AscensionSuiteMainWindow while /asuite is open,
-- restores Ascension native layering on close, and never mutates rapid dice.

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
local suiteShown = true
local hoverClears = 0

local rollButton = {
    SetFrameLevel = function(_, level)
        rollButtonLevel = level
    end,
}

_G.WildCardDice = {
    isRapidRolling = false,
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
    Highlight = {
        Hide = function()
            hoverClears = hoverClears + 1
        end,
    },
    OnLeave = function() end,
    IsMouseEnabled = function() return true end,
    EnableMouse = function() end,
    RegisterOnClick = function() end,
}

_G.AscensionSuiteMainWindow = {
    IsShown = function()
        return suiteShown
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
assert(_G.WildCardDice._asuiteDemotedForSuite == true, "demote flag set")

local clearsAfterFirst = hoverClears
assert(API.DemoteDiceBelowSuite() == true, "idempotent demote returns true")
assert(hoverClears == clearsAfterFirst, "idempotent demote does not re-clear hover")

frameStrata = "FULLSCREEN_DIALOG"
frameLevel = 128
_G.WildCardDice._asuiteDemotedForSuite = nil
_G.WildCardDice._asuiteNativeStrata = nil
assert(API.SyncDiceLayeringForSuite() == true, "sync demotes")
assert(frameStrata == "DIALOG", "sync keeps dice under Suite")

-- Closing Suite restores Ascension native FULLSCREEN_DIALOG.
suiteShown = false
assert(API.RestoreDiceAfterSuite() == true, "restore after Suite")
assert(frameStrata == "FULLSCREEN_DIALOG", "restored Ascension native strata")
assert(_G.WildCardDice._asuiteDemotedForSuite == nil, "demote flag cleared")

-- Rapid-rolling die is never demoted (parented to Rapid board).
suiteShown = true
_G.WildCardDice.isRapidRolling = true
frameStrata = "FULLSCREEN_DIALOG"
_G.WildCardDice._asuiteDemotedForSuite = nil
assert(API.DemoteDiceBelowSuite() == false, "rapid die not demoted")
assert(frameStrata == "FULLSCREEN_DIALOG", "rapid strata untouched")
assert(API.ResolveDiceGuardMode() == "rapid", "rapid mode")

print("OK: AscensionSuite suite dice strata test passed")
