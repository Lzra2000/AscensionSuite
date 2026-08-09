-- AscensionSuite: automation/DiceGuard.lua
-- Re-enable WildCardDice mouse after level-ups and roll-open events when assists
-- left the frame shown but EnableMouse false (common after animation skip mid-reveal).
-- Coalesces burst events and backs off while Ascension fades or hides the die.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local DiceGuard = {}
AscensionSuite.DiceGuard = DiceGuard

local WATCH_EVENTS = {
    "PLAYER_LEVEL_UP",
    "WILDCARD_ROLL_READY",
    "WILDCARD_ENTRY_LEARNED",
    "WILDCARD_UNLEARN_ABILITY_RESULT",
}

local frame
local pending = false
local elapsed = 0
local DEFER_SECONDS = 0.12
local lastRunAt = 0
local MIN_RUN_INTERVAL = 0.25

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetTime()
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return 0
end

local function ScheduleEnsure(event)
    if event == "PLAYER_LEVEL_UP" then
        local api = GetAPI()
        if api and api.MarkLevelUpDiceSettle then
            api.MarkLevelUpDiceSettle()
        end
    end
    pending = true
    elapsed = 0
end

local function RunGuard()
    pending = false
    local now = GetTime()
    if now > 0 and (now - lastRunAt) < MIN_RUN_INTERVAL then
        return
    end
    if now > 0 then
        lastRunAt = now
    end

    local api = GetAPI()
    if not api then
        return
    end

    if api.IsDiceStuckVisibleNonInteractive and api.IsDiceStuckVisibleNonInteractive() then
        if api.HideLingeringDice and api.HideLingeringDice() then
            return
        end
    end

    if api.ShouldLetDiceHide and api.ShouldLetDiceHide() then
        if api.ClearDiceClickStealer then
            api.ClearDiceClickStealer()
        end
        if api.ClearDiceHoverArtifacts then
            api.ClearDiceHoverArtifacts()
        end
        return
    end

    if api.IsDiceRecoveryCooldownActive and api.IsDiceRecoveryCooldownActive() then
        if api.ClearDiceClickStealer then
            api.ClearDiceClickStealer()
        end
        return
    end

    if api.EnsureDiceClickable then
        api.EnsureDiceClickable()
    end
end

function DiceGuard.EnsureNow()
    RunGuard()
end

function DiceGuard.Init()
    if frame or type(CreateFrame) ~= "function" then
        return
    end

    frame = CreateFrame("Frame")
    for index = 1, #WATCH_EVENTS do
        frame:RegisterEvent(WATCH_EVENTS[index])
    end

    frame:SetScript("OnEvent", function(_, event)
        ScheduleEnsure(event)
    end)

    frame:SetScript("OnUpdate", function(_, delta)
        if not pending then
            return
        end
        elapsed = elapsed + (delta or 0)
        if elapsed >= DEFER_SECONDS then
            RunGuard()
        end
    end)
end
