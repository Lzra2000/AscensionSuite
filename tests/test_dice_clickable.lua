-- AscensionSuite: tests/test_dice_clickable.lua
-- Shown WildCardDice in clickable Core states must not stay EnableMouse false.

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

local registeredEvents = {}
local updateScripts = {}
local eventScripts = {}

CreateFrame = function()
    local frame = {}
    frame.RegisterEvent = function(_, event)
        registeredEvents[event] = true
    end
    frame.SetScript = function(self, script, fn)
        if script == "OnUpdate" then
            updateScripts[self] = fn
        elseif script == "OnEvent" then
            eventScripts[self] = fn
        end
    end
    return frame
end

_G.C_Wildcard = {
    IsGameModeActive = function() return true end,
}
_G.C_GameMode = {
    GetGameMode = function() return 1 end,
}

local mouseEnabled = false
local registerCalls = 0
local diceShown = true
local diceAlpha = 0
local frameStrata
local frameLevel
local rollButtonEnabled = false
local rollButtonVisible = false
local updateRollButtonCalls = 0
local iconShown = false
local nameFrameShown = false
local internalID = nil

local function ResetDiceVisuals()
    iconShown = false
    nameFrameShown = false
    internalID = nil
    rollButtonVisible = false
    rollButtonEnabled = false
    updateRollButtonCalls = 0
end

_G.WildCardDice = {
    isRapidRolling = false,
    pendingReveal = nil,
    IsShown = function() return diceShown end,
    IsMouseEnabled = function() return mouseEnabled end,
    EnableMouse = function(_, enabled) mouseEnabled = enabled == true end,
    RegisterOnClick = function()
        registerCalls = registerCalls + 1
        mouseEnabled = true
    end,
    GetAlpha = function() return diceAlpha end,
    SetAlpha = function(_, alpha) diceAlpha = alpha end,
    SetFrameStrata = function(_, strata) frameStrata = strata end,
    SetFrameLevel = function(_, level) frameLevel = level end,
    GetInternalID = function() return internalID end,
    UpdateRollButton = function()
        updateRollButtonCalls = updateRollButtonCalls + 1
        rollButtonEnabled = true
    end,
    Icon = {
        IsShown = function() return iconShown end,
    },
    NameFrame = {
        IsShown = function() return nameFrameShown end,
    },
    RollButton = {
        IsVisible = function() return rollButtonVisible end,
        IsEnabled = function() return rollButtonEnabled end,
        Enable = function() rollButtonEnabled = true end,
        Disable = function() rollButtonEnabled = false end,
        SetFrameLevel = Noop,
    },
    Core = {
        State = {
            IDLE = "IDLE",
            READY_TO_ROLL = "READY_TO_ROLL",
            DECISION_PENDING = "DECISION_PENDING",
            REVEALING = "REVEALING",
        },
        GetState = function() return "READY_TO_ROLL" end,
    },
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/automation/DiceGuard.lua")

AscensionSuite.Database.Init()
local API = AscensionSuite.AscensionAPI
local DiceGuard = AscensionSuite.DiceGuard

API.IsWildcardModeActive = function() return true end

assert(API.DiceShouldAcceptClicks() == true, "READY_TO_ROLL should accept clicks")
assert(API.IsDiceShownUnclickable() == true, "shown die with mouse off is unclickable")

local healed = API.EnsureDiceClickable()
assert(healed == true, "EnsureDiceClickable should heal")
assert(mouseEnabled == true, "RegisterOnClick re-enables mouse")
assert(registerCalls == 1, "RegisterOnClick called once")
assert(diceAlpha == 1, "near-zero alpha is restored")

assert(API.IsDiceShownUnclickable() == false, "healed die is clickable")

-- REVEALING mid-animation (no spell icon yet) is not clickable.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
mouseEnabled = false
assert(API.DiceShouldAcceptClicks() == false, "REVEALING without icon is not clickable")
assert(API.IsDiceShownUnclickable() == false, "mid-reveal mouse-off is expected")
assert(API.EnsureDiceClickable() == false, "must not touch mid-reveal dice")

-- REVEALING stranded after skip: icon shown, Core still REVEALING — must heal.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
internalID = 42
iconShown = true
nameFrameShown = true
rollButtonVisible = true
mouseEnabled = false
registerCalls = 0
frameStrata = nil
frameLevel = nil
assert(API.IsDiceRevealedDecisionShown() == true, "revealed decision visuals detected")
assert(API.DiceShouldAcceptClicks() == true, "stranded reveal should accept clicks")
assert(API.IsDiceShownUnclickable() == true, "stranded reveal with mouse off is unclickable")
healed = API.EnsureDiceClickable()
assert(healed == true, "EnsureDiceClickable heals stranded reveal")
assert(mouseEnabled == true, "stranded reveal mouse restored")
assert(registerCalls >= 1, "stranded reveal calls RegisterOnClick")
assert(frameStrata == "FULLSCREEN_DIALOG", "stranded reveal raises strata")
assert(frameLevel == 128, "stranded reveal raises frame level")
assert(updateRollButtonCalls >= 1, "stranded reveal refreshes RollButton")

-- DECISION_PENDING post-reveal decision die (green cage + spell icon).
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
internalID = 99
iconShown = true
rollButtonVisible = true
rollButtonEnabled = false
mouseEnabled = false
registerCalls = 0
updateRollButtonCalls = 0
assert(API.DiceShouldAcceptClicks() == true, "DECISION_PENDING should accept clicks")
assert(API.IsDiceShownUnclickable() == true, "DECISION_PENDING with mouse off is unclickable")
healed = API.EnsureDiceClickable()
assert(healed == true, "DECISION_PENDING revealed die is healed")
assert(mouseEnabled == true, "DECISION_PENDING mouse restored")
assert(updateRollButtonCalls >= 1, "DECISION_PENDING refreshes RollButton")
assert(rollButtonEnabled == true, "DECISION_PENDING RollButton enabled via UpdateRollButton")

-- RecoverDiceInteraction restores mouse without hiding the die.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
mouseEnabled = false
registerCalls = 0
local ok, reason = API.RecoverDiceInteraction()
assert(ok == true and reason == "mouse_restored", "recover restores mouse, got " .. tostring(reason))
assert(diceShown == true, "leveling recover does not hide the die")
assert(registerCalls >= 1, "recover calls RegisterOnClick")

-- RecoverDiceInteraction on DECISION_PENDING revealed die.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
internalID = 77
iconShown = true
rollButtonVisible = true
mouseEnabled = false
registerCalls = 0
ok, reason = API.RecoverDiceInteraction()
assert(ok == true, "recover heals DECISION_PENDING revealed die")
assert(mouseEnabled == true, "recover restores DECISION_PENDING mouse")

-- DiceGuard watches level-up and roll-open events.
DiceGuard.Init()
assert(registeredEvents.PLAYER_LEVEL_UP == true, "PLAYER_LEVEL_UP registered")
assert(registeredEvents.WILDCARD_ROLL_READY == true, "WILDCARD_ROLL_READY registered")
assert(registeredEvents.WILDCARD_ENTRY_LEARNED == true, "WILDCARD_ENTRY_LEARNED registered")
assert(registeredEvents.WILDCARD_UNLEARN_ABILITY_RESULT == true,
    "WILDCARD_UNLEARN_ABILITY_RESULT registered")

mouseEnabled = false
registerCalls = 0
for frame, fn in pairs(eventScripts) do
    fn(frame, "PLAYER_LEVEL_UP", 42)
end
for frame, fn in pairs(updateScripts) do
    if fn then
        fn(frame, 0.02)
    end
end
assert(mouseEnabled == false, "guard waits for defer before ensuring")

for frame, fn in pairs(updateScripts) do
    if fn then
        fn(frame, 0.1)
    end
end
assert(mouseEnabled == true, "deferred guard tick restores mouse")

print("OK: AscensionSuite dice clickable test passed")
