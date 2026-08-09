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
    SetFrameStrata = Noop,
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

-- REVEALING is not a clickable state; do not force mouse on mid-animation.
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
mouseEnabled = false
assert(API.DiceShouldAcceptClicks() == false, "REVEALING is not clickable")
assert(API.IsDiceShownUnclickable() == false, "mid-reveal mouse-off is expected")
assert(API.EnsureDiceClickable() == false, "must not touch revealing dice")

-- RecoverDiceInteraction restores mouse without hiding the die.
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
mouseEnabled = false
registerCalls = 0
local ok, reason = API.RecoverDiceInteraction()
assert(ok == true and reason == "mouse_restored", "recover restores mouse, got " .. tostring(reason))
assert(diceShown == true, "leveling recover does not hide the die")
assert(registerCalls >= 1, "recover calls RegisterOnClick")

-- DiceGuard watches level-up and roll-open events.
DiceGuard.Init()
assert(registeredEvents.PLAYER_LEVEL_UP == true, "PLAYER_LEVEL_UP registered")
assert(registeredEvents.WILDCARD_ROLL_READY == true, "WILDCARD_ROLL_READY registered")
assert(registeredEvents.WILDCARD_ENTRY_LEARNED == true, "WILDCARD_ENTRY_LEARNED registered")

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
