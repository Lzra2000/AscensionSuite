-- AscensionSuite: automation/AutoUnstick.lua
-- Opt-in auto-recovery when Rapid Continue is stuck gray (die on "?").
-- Calls the same RecoverStuckRapidSession path as the manual Unstick button.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local AutoUnstick = {}
AscensionSuite.AutoUnstick = AutoUnstick

local TICK_SECONDS = 0.5
-- Long enough to ignore a die still animating toward Continue; short enough that
-- the player does not reach for the manual Unstick button first.
local STUCK_SECONDS = 5
-- Recovery is idempotent but not free; cap how often it can fire back-to-back.
local COOLDOWN_SECONDS = 30

local frame
local lastPhase
local stuckFor = 0
local cooldownUntil = 0

local function GetAPI()
    return AscensionSuite.AscensionAPI
end

local function GetAssists()
    local DB = AscensionSuite.Database
    if DB and DB.GetAssists then
        return DB.GetAssists()
    end
    return {}
end

local function ShouldRun()
    local assists = GetAssists()
    return assists and assists.autoUnstick == true
end

local function AutoRollIsRunning()
    local AutoRoller = AscensionSuite.AutoRoller
    return AutoRoller and AutoRoller.IsRunning and AutoRoller.IsRunning()
end

local function Now()
    if type(_G.GetTime) == "function" then
        return _G.GetTime()
    end
    return 0
end

local function Tick(delta)
    if not ShouldRun() then
        stuckFor = 0
        lastPhase = nil
        return
    end

    -- Auto-Roll already recovers after its own stall window; avoid double-firing.
    if AutoRollIsRunning() then
        stuckFor = 0
        return
    end

    local now = Now()
    if now < cooldownUntil then
        return
    end

    local api = GetAPI()
    if not api or not api.IsRapidRollingContinueStuck then
        return
    end

    local state = api.GetRapidRollingState and api.GetRapidRollingState()
    local phase = state and state.Phase

    if api.IsRapidRollingContinueStuck(state) then
        if phase == lastPhase then
            stuckFor = stuckFor + (delta or TICK_SECONDS)
        else
            lastPhase = phase
            stuckFor = 0
        end
    else
        lastPhase = phase
        stuckFor = 0
    end

    if stuckFor < STUCK_SECONDS then
        return
    end

    stuckFor = 0
    lastPhase = nil
    cooldownUntil = now + COOLDOWN_SECONDS

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.UnstickRapid then
        MainWindow.UnstickRapid()
    elseif api.RecoverStuckRapidSession then
        api.RecoverStuckRapidSession()
    end
end

function AutoUnstick.Refresh()
    if not ShouldRun() then
        stuckFor = 0
        lastPhase = nil
    end
end

function AutoUnstick.Init()
    if frame or type(CreateFrame) ~= "function" then
        return
    end

    frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= TICK_SECONDS then
            local step = elapsed
            elapsed = 0
            Tick(step)
        end
    end)
end
