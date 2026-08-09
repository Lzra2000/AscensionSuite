-- AscensionSuite: automation/DiceGuard.lua
-- Re-enable WildCardDice mouse after level-ups and roll-open events when assists
-- left the frame shown but EnableMouse false (common after animation skip mid-reveal).

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
}

local frame
local pending = false
local elapsed = 0
local DEFER_SECONDS = 0.05

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function ScheduleEnsure()
    pending = true
    elapsed = 0
end

local function RunEnsure()
    pending = false
    local api = GetAPI()
    if api and api.EnsureDiceClickable then
        api.EnsureDiceClickable()
    end
end

function DiceGuard.EnsureNow()
    RunEnsure()
end

function DiceGuard.Init()
    if frame or type(CreateFrame) ~= "function" then
        return
    end

    frame = CreateFrame("Frame")
    for index = 1, #WATCH_EVENTS do
        frame:RegisterEvent(WATCH_EVENTS[index])
    end

    frame:SetScript("OnEvent", function()
        ScheduleEnsure()
    end)

    frame:SetScript("OnUpdate", function(_, delta)
        if not pending then
            return
        end
        elapsed = elapsed + (delta or 0)
        if elapsed >= DEFER_SECONDS then
            RunEnsure()
        end
    end)
end
