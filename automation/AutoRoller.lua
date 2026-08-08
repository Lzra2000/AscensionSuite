-- AscensionSuite: automation/AutoRoller.lua
-- Opt-in Auto-Roll against Ascension Desired while Rapid Rolling / leveling.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local AutoRoller = {}
AscensionSuite.AutoRoller = AutoRoller

local TICK_SECONDS = 0.35

local frame
local running = false
local lastError

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

local function PlayerLevelInRange()
    if not UnitLevel then
        return true
    end
    local level = UnitLevel("player")
    if not level then
        return true
    end
    return level >= 1 and level <= 60
end

local function CanOperate()
    local assists = GetAssists()
    if not assists or assists.autoRoll ~= true then
        return false, "assist_off"
    end
    if not PlayerLevelInRange() then
        return false, "level_out_of_range"
    end
    local api = GetAPI()
    if not api or not api.IsWildcardModeActive() then
        return false, "not_wildcard"
    end
    if not api.IsRapidRollingFrameShown() and not api.CanRollAbilities() then
        return false, "rapid_not_ready"
    end
    return true
end

function AutoRoller.IsRunning()
    return running
end

function AutoRoller.GetLastError()
    return lastError
end

function AutoRoller.Stop(reason)
    running = false
    lastError = reason
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshAutoRoll then
        MainWindow.RefreshAutoRoll()
    end
end

local function Tick()
    if not running then
        return
    end

    local canRun, reason = CanOperate()
    if not canRun then
        AutoRoller.Stop(reason)
        return
    end

    local api = GetAPI()
    local ok, err = api.AdvanceRapidRoll(true)
    if not ok then
        if err == "roll_in_flight" or err == "session_complete" then
            return
        end
        AutoRoller.Stop(err or "api_error")
        return
    end
    lastError = nil
end

function AutoRoller.Start()
    local canRun, reason = CanOperate()
    if not canRun then
        return false, reason
    end

    if not frame then
        frame = CreateFrame("Frame")
    end

    running = true
    lastError = nil
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= TICK_SECONDS then
            elapsed = 0
            Tick()
        end
    end)

    local MainWindow = AscensionSuite.MainWindow
    if MainWindow and MainWindow.RefreshAutoRoll then
        MainWindow.RefreshAutoRoll()
    end
    return true
end

function AutoRoller.Init()
    -- no-op; frame created on Start
end
