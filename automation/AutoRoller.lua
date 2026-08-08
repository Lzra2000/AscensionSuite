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

-- A rapid session whose phase has not moved for this long is stuck behind
-- something the assist cannot clear. Ascension's Roll button reports failures by
-- showing its own error frame and returns nothing, so without this backstop a
-- rejected roll would be retried every tick forever.
local STALL_SECONDS = 15

local frame
local running = false
local lastError
local lastPhase
local stalledFor = 0

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

-- Rolling with nothing marked Desired is a plain reroll loop until scrolls run
-- out, which the assist boundary rules out. The client cannot count Desired
-- selections, so this verifies the wishlist entries the addon tracks; targets
-- marked only in the native Rapid window are not visible to it.
local function HasDesiredTargets()
    local Wishlist = AscensionSuite.Wishlist
    if not Wishlist or not Wishlist.CountDesired then
        return false
    end
    return Wishlist.CountDesired() > 0
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
    if not HasDesiredTargets() then
        return false, "no_desired_targets"
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

local function CurrentPhase()
    local api = GetAPI()
    local state = api and api.GetRapidRollingState()
    return state and state.Phase or nil
end

local function Tick(delta)
    if not running then
        return
    end

    local canRun, reason = CanOperate()
    if not canRun then
        AutoRoller.Stop(reason)
        return
    end

    local api = GetAPI()

    -- Check what the previous roll did before asking for another one: a shown
    -- error frame is the only trace the native Roll path leaves behind.
    if api.IsRapidRollingErrorShown and api.IsRapidRollingErrorShown() then
        AutoRoller.Stop("native_error")
        return
    end

    local phase = CurrentPhase()
    if phase ~= nil and phase == lastPhase then
        stalledFor = stalledFor + (delta or TICK_SECONDS)
        if stalledFor >= STALL_SECONDS then
            AutoRoller.Stop("stalled")
            return
        end
    else
        lastPhase = phase
        stalledFor = 0
    end

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
    lastPhase = nil
    stalledFor = 0
    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= TICK_SECONDS then
            local sinceLastTick = elapsed
            elapsed = 0
            Tick(sinceLastTick)
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
