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

-- Hard ceiling on the opt-in continue assist. It should end by running the Desired
-- set empty, but a client that keeps reporting an entry as Desired after learning
-- it would otherwise be an unbounded roll loop, which the assist boundary rules out.
local MAX_CHAINED_SESSIONS = 25

local frame
local running = false
local lastError
local lastPhase
local stalledFor = 0
local desiredHits = 0
local chainPending = false
local learnedThisRun = {}

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
-- selections, so this verifies the entries the addon tracks -- which now include
-- marks made in Ascension's own windows, as long as DesiredSync has seen them.
local function HasDesiredTargets()
    local Wishlist = AscensionSuite.Wishlist
    if not Wishlist or not Wishlist.CountDesired then
        return false
    end
    return Wishlist.CountDesired() > 0
end

-- Opt-in, default off. With it on, a Desired hit closes its session through the
-- native path and the assist opens the next one instead of handing control back;
-- with it off (the default since 0.2.1) it stops and waits for another Start.
local function ContinueAfterHit()
    local assists = GetAssists()
    return assists ~= nil and assists.autoRollContinue == true
end

-- skipTargets exists because the Desired set empties at the moment the last entry
-- is learned, and a tick that finds it empty still has a finished session in front
-- of it to close out. Gating on targets before that would leave the player looking
-- at a COMPLETE button nobody pressed.
local function CanOperate(skipTargets)
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
    if not skipTargets and not HasDesiredTargets() then
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

-- How many Desired entries this run has landed. Non-zero only matters for the
-- continue assist, which is the only way a single run sees more than one.
function AutoRoller.GetDesiredHits()
    return desiredHits
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

    local canRun, reason = CanOperate(true)
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
    -- Also stall when the advance is blocked with no usable Phase (die stuck on
    -- "?" / pendingReveal): that is the gray-Continue hang. Phase progress still
    -- resets the clock so a healthy in-flight reveal is not recovered early. It
    -- runs before the Desired-hit branch so that a stop code which never clears
    -- is recovered rather than waited on forever.
    local blocked = false
    if api.IsRapidRollingAdvanceBlocked then
        blocked = api.IsRapidRollingAdvanceBlocked() == true
    end
    if (phase ~= nil and phase == lastPhase) or (blocked and phase == lastPhase) then
        stalledFor = stalledFor + (delta or TICK_SECONDS)
        if stalledFor >= STALL_SECONDS then
            if api.RecoverStuckRapidSession then
                api.RecoverStuckRapidSession()
            end
            AutoRoller.Stop("stalled")
            return
        end
    else
        lastPhase = phase
        stalledFor = 0
    end

    -- A Desired entry landed: it is already learned, and the session's own
    -- buttons are now COMPLETE, Lock and Unlearn, none of which an assist may
    -- press. Either way the session is closed out through Ascension's own Roll
    -- button; the only question is whether the next one is opened.
    if api.IsRapidRollingDesiredHit and api.IsRapidRollingDesiredHit() then
        -- The stop code outlives the session it describes by a tick or two, so
        -- without this the same hit would be "closed" over and over.
        if chainPending then
            return
        end

        -- Read before the close: the state that names the learned entry is the
        -- one the close throws away.
        local learnedId = api.GetRapidRollingLearnedEntryID and api.GetRapidRollingLearnedEntryID()

        api.AdvanceRapidRoll(true)
        desiredHits = desiredHits + 1

        if not ContinueAfterHit() then
            AutoRoller.Stop("desired_learned")
            return
        end

        -- An entry the client still reports as Desired after learning it would
        -- make the chain roll for something it already has.
        if learnedId then
            if learnedThisRun[learnedId] then
                AutoRoller.Stop("desired_repeat")
                return
            end
            learnedThisRun[learnedId] = true
        end

        if desiredHits >= MAX_CHAINED_SESSIONS then
            AutoRoller.Stop("chain_limit")
            return
        end

        chainPending = true
        lastPhase = nil
        stalledFor = 0
        return
    end
    chainPending = false

    -- Rolling with nothing Desired left is the reroll loop the assist boundary
    -- rules out, so this is where a chained run finishes. It reads as a finish
    -- rather than the "you have no targets" refusal because it is one.
    if not HasDesiredTargets() then
        AutoRoller.Stop(desiredHits > 0 and "desired_list_done" or "no_desired_targets")
        return
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
    -- Pull in Desired marks the player made in Ascension's own windows before
    -- deciding there are no targets: those are invisible until something has
    -- tracked their (id, type) pair.
    local DesiredSync = AscensionSuite.DesiredSync
    if DesiredSync and DesiredSync.Sync then
        DesiredSync.Sync()
    end

    -- Merge the wishlist into Desired. PushToDesired only ever adds -- it does not
    -- clear, and it skips whatever is Desired already -- so a player who marked a
    -- few entries by hand keeps every one of them and gains the rest of the list.
    -- Until 0.2.5 this ran only when Desired was completely empty, which meant one
    -- hand-made mark was enough to make Start silently ignore the whole wishlist.
    local Wishlist = AscensionSuite.Wishlist
    if Wishlist and Wishlist.PushToDesired and Wishlist.Count and Wishlist.Count() > 0 then
        Wishlist.PushToDesired()
    end

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
    desiredHits = 0
    chainPending = false
    learnedThisRun = {}
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
    -- The push above may have marked rows Desired; the panel's badges are stale
    -- until something re-reads them.
    if MainWindow and MainWindow.RefreshWishlist then
        MainWindow.RefreshWishlist()
    end
    return true
end

function AutoRoller.Init()
    -- no-op; frame created on Start
end
