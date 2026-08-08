-- AscensionSuite: tests/test_assists.lua
-- Assists default off, Auto-Roll refuses to run without Desired targets, and it
-- halts (rather than looping) on an API error.

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

local updateScripts = {}

CreateFrame = function()
    local frame = {}
    frame.RegisterEvent = Noop
    frame.IsShown = function() return false end
    frame.SetScript = function(self, script, fn)
        if script == "OnUpdate" then
            updateScripts[self] = fn
        end
    end
    return frame
end

-- Drive the Auto-Roll OnUpdate loop past its tick threshold.
local function RunTick()
    local ran = 0
    for frame, fn in pairs(updateScripts) do
        if fn then
            fn(frame, 10)
            ran = ran + 1
        end
    end
    return ran
end

function UnitLevel() return 20 end

local WISHLIST_SPELL = 133
local WISHLIST_ENTRY = 1133

local desired = {}
local rollCalls = 0
local rollResult = { false, "forced_error" }

-- Drives the rapid session phase the addon polls; nil means "no live session",
-- which is the plain leveling dice case the early assertions run under.
local rapidPhase = nil

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        if id == WISHLIST_SPELL then
            return { ID = WISHLIST_ENTRY, Type = "Ability", Spell = WISHLIST_SPELL, Name = "Wish" }
        end
        return nil
    end,
    GetEntryByInternalID = function() return nil end,
}

C_Wildcard = {
    -- Non-zero on purpose: this is the filtered candidate count, which must not
    -- be mistaken for "the player has Desired targets".
    GetNumFilteredDesiredEntries = function() return 25 end,
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[tostring(id) .. tostring(entryType)] = true
        return true
    end,
    IsDesiredID = function(_, id, entryType)
        return desired[tostring(id) .. tostring(entryType)] == true
    end,
    CanRollAbilities = function() return true end,
    -- With no Rapid window open this is the plain leveling dice path.
    RollAbilities = function()
        rollCalls = rollCalls + 1
        return rollResult[1], rollResult[2]
    end,
    GetRapidRollingState = function()
        return { Phase = rapidPhase }
    end,
}

_G.WildCardRapidRollingFrame = nil

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/automation/AutoRoller.lua")

AscensionSuite.Database.Init()

local assists = AscensionSuiteDB.assists
assert(assists.autoRoll == false, "autoRoll default off")
assert(assists.instantDiceSkip == false, "dice skip default off")
assert(assists.instantSkillCardSkip == false, "skillcard skip default off")
assert(assists.acceptWildcardPopups == false, "popup accept default off")
assert(assists.captureRolls == false, "capture default off")

local AutoRoller = AscensionSuite.AutoRoller
local Wishlist = AscensionSuite.Wishlist
assert(AutoRoller, "AutoRoller missing")
assert(Wishlist, "Wishlist missing")

-- Off by default: no start even when the client would allow a roll.
local ok, reason = AutoRoller.Start()
assert(ok == false and reason == "assist_off", "must not start while assist is off, got " .. tostring(reason))

assists.autoRoll = true

-- Opted in but nothing marked Desired: still refuses, and never rolls.
assert(Wishlist.CountDesired() == 0, "no desired targets yet")
ok, reason = AutoRoller.Start()
assert(ok == false and reason == "no_desired_targets",
    "must refuse without Desired targets, got " .. tostring(reason))
assert(rollCalls == 0, "no roll should have been requested")

-- Mark a wishlist entry Desired; now it may run.
assert(Wishlist.AddToDesired(WISHLIST_SPELL), "wishlist add should reach Desired")
assert(Wishlist.CountDesired() == 1, "one desired target tracked")

ok, reason = AutoRoller.Start()
assert(ok == true, "should arm loop once a Desired target exists, got " .. tostring(reason))
assert(AutoRoller.IsRunning() == true, "running after start")

-- A failing roll starter halts the loop and surfaces the reason.
RunTick()
assert(rollCalls > 0, "tick should have attempted a roll")
assert(AutoRoller.IsRunning() == false, "must halt on API error rather than retry")
local lastError = AutoRoller.GetLastError()
assert(lastError == "forced_error" or lastError == "roll_failed",
    "error propagated, got " .. tostring(lastError))

local callsAfterHalt = rollCalls
RunTick()
assert(rollCalls == callsAfterHalt, "halted loop must not keep rolling")

-- A succeeding roll keeps it running.
rollResult = { true, nil }
ok = AutoRoller.Start()
assert(ok == true, "restart after error")
RunTick()
assert(AutoRoller.IsRunning() == true, "stays running while rolls succeed")

-- Removing the Desired target stops it on the next tick.
desired = {}
RunTick()
assert(AutoRoller.IsRunning() == false, "stops once Desired targets are gone")
assert(AutoRoller.GetLastError() == "no_desired_targets", "reports why it stopped")

-- With the Rapid window open, rolling goes through Ascension's own Roll button
-- rather than the addon re-deriving the phase sequence.
local nativeRollCalls = 0
local nativeSkipConfirm = nil
_G.WildCardRapidRollingFrame = {
    IsShown = function() return true end,
    Roll = function(_, skipConfirm)
        nativeRollCalls = nativeRollCalls + 1
        nativeSkipConfirm = skipConfirm
    end,
}

desired[tostring(WISHLIST_ENTRY) .. "Ability"] = true
local rollsBefore = rollCalls

ok = AutoRoller.Start()
assert(ok == true, "restart with Rapid window open")
RunTick()
assert(nativeRollCalls > 0, "should drive the native Roll button")
assert(nativeSkipConfirm == true, "Auto-Roll passes skipConfirm so it does not stall on the confirm popup")
assert(rollCalls == rollsBefore, "must not also call RollAbilities directly")

AutoRoller.Stop("test_done")
assert(AutoRoller.IsRunning() == false, "stopped")

-- Ascension's Roll button reports a rejected roll by showing its own error frame
-- and returning nothing, so Auto-Roll has to read that surface. Without this it
-- would keep asking for a roll the client has already refused.
local errorShown = false
_G.WildCardRapidRollingFrame.RollingFrame = {
    ErrorFrame = {
        IsShown = function() return errorShown end,
    },
}

ok = AutoRoller.Start()
assert(ok == true, "restart to exercise the native error surface")

errorShown = true
local nativeBefore = nativeRollCalls
RunTick()
assert(AutoRoller.IsRunning() == false, "must halt while Ascension is showing a roll error")
assert(AutoRoller.GetLastError() == "native_error",
    "reports the native refusal, got " .. tostring(AutoRoller.GetLastError()))
assert(nativeRollCalls == nativeBefore, "must not request another roll after a refusal")

errorShown = false

-- Each RunTick advances the loop by 10 seconds, so three ticks on one unchanged
-- phase crosses the stall window while two do not.
rapidPhase = "WaitingForRoll"

-- A session moving through phases is healthy and must not be interrupted.
ok = AutoRoller.Start()
assert(ok == true, "restart for the phase-progress case")
RunTick()
rapidPhase = "Revealing"
RunTick()
rapidPhase = "AwaitingContinue"
RunTick()
assert(AutoRoller.IsRunning() == true, "phase progress must not trip the stall guard")

-- A phase that never moves does get cut off.
AutoRoller.Stop("test_reset")
rapidPhase = "WaitingForRoll"
ok = AutoRoller.Start()
assert(ok == true, "restart for the stall case")

RunTick()
assert(AutoRoller.IsRunning() == true, "first tick only records the phase")
RunTick()
assert(AutoRoller.IsRunning() == true, "10s on one phase is not yet a stall")
RunTick()
assert(AutoRoller.IsRunning() == false, "must stop once a phase is stuck past the stall window")
assert(AutoRoller.GetLastError() == "stalled",
    "reports the stall, got " .. tostring(AutoRoller.GetLastError()))

print("OK: AscensionSuite assists test passed")
