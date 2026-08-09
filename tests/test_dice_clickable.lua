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

local canRollAbilities = true

_G.C_Wildcard = {
    IsGameModeActive = function() return true end,
    CanRollAbilities = function() return canRollAbilities end,
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
local rollButtonMouseEnabled = true
local scrollCountMouseEnabled = true
local updateRollButtonCalls = 0
local iconShown = false
local nameFrameShown = false
local internalID = nil
local diceMouseOver = false
local rollButtonMouseOver = false
local scrollCountMouseOver = false
local highlightShown = false
local tooltipHidden = false
local onEnterCalls = 0
local onLeaveCalls = 0
local rollButtonOnEnterCalls = 0
local scrollCountOnEnterCalls = 0

local function ResetDiceVisuals()
    iconShown = false
    nameFrameShown = false
    internalID = nil
    rollButtonVisible = false
    rollButtonEnabled = false
    rollButtonMouseEnabled = true
    scrollCountMouseEnabled = true
    updateRollButtonCalls = 0
    frameStrata = "MEDIUM"
    frameLevel = 1
    diceShown = true
    diceMouseOver = false
    rollButtonMouseOver = false
    scrollCountMouseOver = false
    highlightShown = false
    tooltipHidden = false
    onEnterCalls = 0
    onLeaveCalls = 0
    rollButtonOnEnterCalls = 0
    scrollCountOnEnterCalls = 0
end

_G.GameTooltip = {
    Hide = function()
        tooltipHidden = true
    end,
}

_G.WildCardDice = {
    isRapidRolling = false,
    pendingReveal = nil,
    IsShown = function() return diceShown end,
    IsMouseOver = function() return diceMouseOver end,
    IsMouseEnabled = function() return mouseEnabled end,
    EnableMouse = function(_, enabled) mouseEnabled = enabled == true end,
    RegisterOnClick = function()
        registerCalls = registerCalls + 1
        mouseEnabled = true
    end,
    OnEnter = function()
        onEnterCalls = onEnterCalls + 1
        highlightShown = true
    end,
    OnLeave = function()
        onLeaveCalls = onLeaveCalls + 1
        highlightShown = false
        tooltipHidden = true
    end,
    RollButtonOnEnter = function()
        rollButtonOnEnterCalls = rollButtonOnEnterCalls + 1
    end,
    ScrollCountOnEnter = function()
        scrollCountOnEnterCalls = scrollCountOnEnterCalls + 1
    end,
    GetAlpha = function() return diceAlpha end,
    SetAlpha = function(_, alpha) diceAlpha = alpha end,
    SetFrameStrata = function(_, strata) frameStrata = strata end,
    SetFrameLevel = function(_, level) frameLevel = level end,
    GetFrameStrata = function() return frameStrata end,
    GetFrameLevel = function() return frameLevel end,
    Hide = function() diceShown = false end,
    GetInternalID = function() return internalID end,
    UpdateRollButton = function()
        updateRollButtonCalls = updateRollButtonCalls + 1
        rollButtonEnabled = true
    end,
    Highlight = {
        Hide = function() highlightShown = false end,
        Show = function() highlightShown = true end,
    },
    Icon = {
        IsShown = function() return iconShown end,
    },
    NameFrame = {
        IsShown = function() return nameFrameShown end,
    },
    RollButton = {
        IsVisible = function() return rollButtonVisible end,
        IsEnabled = function() return rollButtonEnabled end,
        IsMouseOver = function() return rollButtonMouseOver end,
        IsMouseEnabled = function() return rollButtonMouseEnabled end,
        EnableMouse = function(_, enabled) rollButtonMouseEnabled = enabled == true end,
        Enable = function() rollButtonEnabled = true end,
        Disable = function() rollButtonEnabled = false end,
        SetFrameLevel = Noop,
        ScrollCount = {
            IsMouseOver = function() return scrollCountMouseOver end,
            IsMouseEnabled = function() return scrollCountMouseEnabled end,
            EnableMouse = function(_, enabled) scrollCountMouseEnabled = enabled == true end,
        },
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

-- Hidden READY_TO_ROLL die must not get mouse enabled.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
diceShown = false
mouseEnabled = false
registerCalls = 0
assert(API.EnsureDiceClickable() == false, "hidden die is not touched")
assert(mouseEnabled == false, "hidden die mouse stays off")
assert(registerCalls == 0, "hidden die RegisterOnClick not called")

-- Stranded IDLE die at FULLSCREEN_DIALOG with mouse on steals clicks — clear it.
-- Ascension's native strata is FULLSCREEN_DIALOG; Suite must not demote it to MEDIUM.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
frameStrata = "FULLSCREEN_DIALOG"
frameLevel = 128
mouseEnabled = true
diceShown = true
assert(API.ClearDiceClickStealer() == true, "idle click stealer cleared")
assert(mouseEnabled == false, "click stealer mouse disabled")
assert(frameStrata == "FULLSCREEN_DIALOG", "native FULLSCREEN_DIALOG left alone")
assert(diceShown == false, "idle click stealer hidden")

-- RecoverDiceInteraction clears stranded click stealers (Manastorm tracker regression).
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
frameStrata = "FULLSCREEN_DIALOG"
mouseEnabled = true
diceShown = true
ok, reason = API.RecoverDiceInteraction()
assert(ok == true and reason == "click_stealer_cleared",
    "recover clears click stealer, got " .. tostring(reason))
assert(mouseEnabled == false, "recover disables stealer mouse")
assert(diceShown == false, "recover hides idle stealer")

-- Mid-reveal REVEALING without icon: EnsureDiceClickable must not enable mouse.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
frameStrata = "FULLSCREEN_DIALOG"
mouseEnabled = true
diceShown = true
assert(API.EnsureDiceClickable() == true, "mid-reveal clears click stealer")
assert(mouseEnabled == false, "mid-reveal mouse disabled")
assert(frameStrata == "FULLSCREEN_DIALOG", "mid-reveal keeps Ascension native strata")
assert(onLeaveCalls >= 1 or tooltipHidden == true, "mid-reveal hover artifacts cleared")

-- ClearDiceHoverArtifacts hides tooltip and highlight.
ResetDiceVisuals()
highlightShown = true
tooltipHidden = false
assert(API.ClearDiceHoverArtifacts() == true, "hover artifacts cleared")
assert(highlightShown == false, "highlight hidden")
assert(tooltipHidden == true, "tooltip hidden")

-- SanitizeDiceHover calls OnLeave when cursor is elsewhere.
ResetDiceVisuals()
highlightShown = true
onLeaveCalls = 0
assert(API.SanitizeDiceHover() == true, "sanitize runs")
assert(onLeaveCalls == 1, "OnLeave when not mouseover")
assert(highlightShown == false, "highlight cleared via OnLeave")

-- SanitizeDiceHover re-fires OnEnter when cursor is over the die.
ResetDiceVisuals()
diceMouseOver = true
onEnterCalls = 0
assert(API.SanitizeDiceHover() == true, "sanitize over dice")
assert(onEnterCalls == 1, "OnEnter when mouseover dice")
assert(highlightShown == true, "highlight shown via OnEnter")

-- SanitizeDiceHover re-fires RollButtonOnEnter when cursor is over Unlearn bar.
ResetDiceVisuals()
rollButtonVisible = true
rollButtonMouseOver = true
rollButtonOnEnterCalls = 0
assert(API.SanitizeDiceHover() == true, "sanitize over roll button")
assert(rollButtonOnEnterCalls == 1, "RollButtonOnEnter when mouseover roll button")

-- EnsureDiceClickable sanitizes hover after mouse restore.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
internalID = 55
iconShown = true
rollButtonVisible = true
mouseEnabled = false
diceMouseOver = true
onEnterCalls = 0
registerCalls = 0
healed = API.EnsureDiceClickable()
assert(healed == true, "DECISION_PENDING heal includes hover sanitize")
assert(onEnterCalls >= 1, "EnsureDiceClickable re-fires OnEnter when mouseover")

-- RollButton mouse restored for interactive decision die.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
internalID = 66
iconShown = true
rollButtonVisible = true
rollButtonMouseEnabled = false
scrollCountMouseEnabled = false
mouseEnabled = false
API.EnsureDiceClickable()
assert(rollButtonMouseEnabled == true, "RollButton mouse restored")
assert(scrollCountMouseEnabled == true, "ScrollCount mouse restored")

-- Fading die: EnsureDiceClickable must not re-show or RegisterOnClick.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
mouseEnabled = false
registerCalls = 0
diceAlpha = 0.4
_G.WildCardDice.FadeMode = "OUT"
canRollAbilities = false
healed = API.EnsureDiceClickable()
assert(registerCalls == 0, "fading die RegisterOnClick not called")
assert(diceAlpha == 0.4, "fading die alpha not forced to 1")
assert(mouseEnabled == false, "fading die mouse not re-enabled")
_G.WildCardDice.FadeMode = nil
canRollAbilities = true

-- Appear fade-IN must NOT be treated as fading out (alpha mid is normal).
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
_G.WildCardDice.FadeMode = "IN"
diceAlpha = 0.4
mouseEnabled = false
registerCalls = 0
assert(API.IsDiceFadingOut() == false, "FadeMode IN is not fading out")
assert(API.ResolveDiceGuardMode() == "heal", "appear fade-IN still heals")
healed = API.EnsureDiceClickable()
assert(healed == true, "fade-IN READY_TO_ROLL is healed")
assert(mouseEnabled == true, "fade-IN mouse restored")
_G.WildCardDice.FadeMode = nil

-- Sticky FadeMode OUT at full alpha is NOT an active fade — READY_TO_ROLL must heal.
-- Ascension leaves FadeMode set after ramps end; PlayFlipBook UnregisterOnClick races
-- can leave mouse false while the gold "Click the Dice…" hint stays up.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
_G.WildCardDice.FadeMode = "OUT"
diceAlpha = 1
mouseEnabled = false
registerCalls = 0
assert(API.IsDiceFadingOut() == false, "sticky OUT at full alpha is not fading out")
assert(API.ResolveDiceGuardMode() == "heal", "sticky OUT READY_TO_ROLL heals")
healed = API.EnsureDiceClickable()
assert(healed == true, "sticky OUT READY_TO_ROLL is healed")
assert(mouseEnabled == true, "sticky OUT mouse restored")
_G.WildCardDice.FadeMode = nil

-- Active mid fade-OUT on READY_TO_ROLL must not re-enable mouse (HideDices ramp).
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
_G.WildCardDice.FadeMode = "OUT"
diceAlpha = 0.4
mouseEnabled = false
registerCalls = 0
assert(API.IsDiceFadingOut() == true, "mid OUT ramp is fading out")
assert(API.ResolveDiceGuardMode() ~= "heal", "mid OUT ramp does not heal")
healed = API.EnsureDiceClickable()
assert(registerCalls == 0, "mid OUT ramp RegisterOnClick not called")
assert(mouseEnabled == false, "mid OUT ramp mouse stays off")
_G.WildCardDice.FadeMode = nil

-- Gold hint prompt alone (Core lagged) still counts as interactive.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
_G.WildCardDice.HintFrame = {
    IsShown = function() return true end,
    GetAlpha = function() return 1 end,
}
mouseEnabled = false
registerCalls = 0
assert(API.DiceShouldAcceptClicks() == true, "HintFrame prompt accepts clicks")
assert(API.ResolveDiceGuardMode() == "heal", "hint prompt heals")
healed = API.EnsureDiceClickable()
assert(healed == true and mouseEnabled == true, "hint prompt mouse restored")
_G.WildCardDice.HintFrame = nil

-- FadeMode IN on IDLE appear must not hide/clear (Core stays IDLE until OnFinishedAppear).
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
_G.WildCardDice.FadeMode = "IN"
diceShown = true
mouseEnabled = false
assert(API.ShouldLetDiceHide() == false, "appear fade-IN IDLE is not let_hide")
assert(API.IsDiceStuckVisibleNonInteractive() == false, "appear fade-IN is not stuck linger")
_G.WildCardDice.FadeMode = nil

-- ShouldLetDiceHide after level-up when no roll and no decision.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
canRollAbilities = false
assert(API.ShouldLetDiceHide() == true, "idle die should hide when no roll")
canRollAbilities = true

-- HideLingeringDice clears hover artifacts.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "IDLE" end
highlightShown = true
tooltipHidden = false
canRollAbilities = false
assert(API.HideLingeringDice() == true, "lingering die hidden")
assert(diceShown == false, "HideLingeringDice hides die")
assert(highlightShown == false, "hide path clears highlight")
assert(tooltipHidden == true, "hide path clears tooltip")
canRollAbilities = true

-- Recovery cooldown must not block healing a new READY_TO_ROLL die.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
API.NoteDiceRecoveryHide()
mouseEnabled = false
registerCalls = 0
assert(API.IsDiceRecoveryCooldownActive() == true
    or type(_G.GetTime) ~= "function"
    or _G.GetTime() == 0
    or API.ResolveDiceGuardMode() == "heal",
    "cooldown active or sandbox GetTime unavailable")
_G.GetTime = function() return 100 end
API.NoteDiceRecoveryHide()
assert(API.IsDiceRecoveryCooldownActive() == true, "cooldown armed")
assert(API.ResolveDiceGuardMode() == "heal", "cooldown still allows heal mode")
healed = API.EnsureDiceClickable()
assert(healed == true, "cooldown does not block READY_TO_ROLL heal")
assert(mouseEnabled == true, "cooldown heal restores mouse")

-- DiceGuard debounce: burst events coalesce; fading die not re-shown.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "READY_TO_ROLL" end
mouseEnabled = false
registerCalls = 0
diceAlpha = 0.5
_G.WildCardDice.FadeMode = "OUT"
canRollAbilities = false
local guardRuns = 0
local origEnsure = API.EnsureDiceClickable
API.EnsureDiceClickable = function()
    guardRuns = guardRuns + 1
    return origEnsure()
end
for frame, fn in pairs(eventScripts) do
    fn(frame, "PLAYER_LEVEL_UP", 42)
    fn(frame, "WILDCARD_ENTRY_LEARNED", 1, 0)
    fn(frame, "WILDCARD_ROLL_READY")
end
for frame, fn in pairs(updateScripts) do
    if fn then
        fn(frame, 0.15)
    end
end
assert(guardRuns <= 1, "burst guard events coalesce to one ensure")
assert(registerCalls == 0, "guard does not RegisterOnClick on fading die")
API.EnsureDiceClickable = origEnsure
_G.WildCardDice.FadeMode = nil
canRollAbilities = true

-- Suite-raised flag only: native FULLSCREEN_DIALOG is not a Suite raise.
ResetDiceVisuals()
_G.WildCardDice.Core.GetState = function() return "REVEALING" end
frameStrata = "FULLSCREEN_DIALOG"
_G.WildCardDice._asuiteStrataRaised = nil
mouseEnabled = true
API.ClearDiceClickStealer()
assert(frameStrata == "FULLSCREEN_DIALOG", "without Suite flag strata untouched")
_G.WildCardDice._asuiteStrataRaised = true
_G.WildCardDice._asuiteNativeStrata = "FULLSCREEN_DIALOG"
frameStrata = "FULLSCREEN_DIALOG"
mouseEnabled = true
diceShown = true
API.ClearDiceClickStealer()
assert(_G.WildCardDice._asuiteStrataRaised == nil, "Suite raise flag cleared")

print("OK: AscensionSuite dice clickable test passed")
