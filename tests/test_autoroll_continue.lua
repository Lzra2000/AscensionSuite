-- AscensionSuite: tests/test_autoroll_continue.lua
-- The opt-in continue assist: after a Desired entry lands, close the session
-- through Ascension's own button and open the next one, until the wishlist has
-- nothing Desired left. Default off -- one hit still stops the run.

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

local function RunTick()
    for frame, fn in pairs(updateScripts) do
        if fn then
            fn(frame, 1)
        end
    end
end

function UnitLevel() return 20 end

------------------------------------------------------------------------
-- Advancement data
------------------------------------------------------------------------

local ENTRIES = {
    [4001] = { ID = 4001, Type = "Ability", Spell = 133, Name = "Fireball" },
    [4002] = { ID = 4002, Type = "Ability", Spell = 116, Name = "Ice Block" },
    [4003] = { ID = 4003, Type = "Talent", Spell = 118, Name = "Polymorph" },
}

local BY_SPELL = {}
for _, entry in pairs(ENTRIES) do
    BY_SPELL[entry.Spell] = entry
end

local desired = {}
local function Key(entryId, entryType)
    return tostring(entryId) .. "/" .. tostring(entryType)
end

------------------------------------------------------------------------
-- A rapid session that lands one queued Desired entry per start
------------------------------------------------------------------------

local rapid = { Phase = nil, StopCode = nil, LearnedEntryID = nil }
local pendingHits = {}
local startCalls = 0
local closeCalls = 0

-- Set for the repeat-guard case: the client keeps reporting the entry as Desired
-- after learning it, which would otherwise be an endless reroll of one spell.
local stickyDesired = false

local function LandNextHit()
    local target = table.remove(pendingHits, 1)
    if not target then
        rapid.Phase = "Idle"
        rapid.StopCode = nil
        rapid.LearnedEntryID = nil
        return
    end
    if not stickyDesired then
        desired[Key(target.id, target.type)] = nil
    end
    rapid.Phase = "Completed"
    rapid.StopCode = "STOP_RAPID_ROLLING_DESIRED_ENTRY_LEARNED"
    rapid.LearnedEntryID = target.id
end

WildCardRapidRollingFrame = {
    IsShown = function() return true end,
    Roll = function(_, skipConfirm)
        assert(skipConfirm == true, "the assist must never stall on the confirm popup")
        if rapid.Phase == "Completed" then
            -- Ascension's own terminal branch: cancel and clear, no new roll.
            closeCalls = closeCalls + 1
            rapid.Phase = "Idle"
            rapid.StopCode = nil
            rapid.LearnedEntryID = nil
            return
        end
        startCalls = startCalls + 1
        LandNextHit()
    end,
}

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id) return BY_SPELL[id] end,
    GetEntryByInternalID = function(_, id) return ENTRIES[id] end,
}

C_Wildcard = {
    GetNumFilteredDesiredEntries = function() return 0 end,
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, id, entryType) return desired[Key(id, entryType)] == true end,
    CanRollAbilities = function() return true end,
    GetRapidRollingState = function() return rapid end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/automation/AutoRoller.lua")

AscensionSuite.Database.Init()

local AutoRoller = AscensionSuite.AutoRoller
local Wishlist = AscensionSuite.Wishlist
local assists = AscensionSuiteDB.assists

assert(assists.autoRollContinue == false, "the continue assist ships off, like every other assist")

------------------------------------------------------------------------
-- Default: one Desired hit still ends the run
------------------------------------------------------------------------

assists.autoRoll = true
Wishlist.AddEntry(4001, "Ability", 133, "Fireball")
Wishlist.AddEntry(4002, "Ability", 116, "Ice Block")
desired[Key(4001, "Ability")] = true
desired[Key(4002, "Ability")] = true

pendingHits = { { id = 4001, type = "Ability" } }
rapid.Phase = "Idle"

assert(AutoRoller.Start() == true, "arms with two Desired targets")
RunTick()   -- starts the session, which lands 4001
RunTick()   -- sees the hit
assert(AutoRoller.IsRunning() == false, "with the assist off, a Desired hit ends the run")
assert(AutoRoller.GetLastError() == "desired_learned",
    "and says so, got " .. tostring(AutoRoller.GetLastError()))
assert(closeCalls == 1, "the session is closed through the native button")
assert(AutoRoller.GetDesiredHits() == 1, "one entry landed")

local startsAfterStop = startCalls
RunTick()
assert(startCalls == startsAfterStop, "a stopped run never opens another session")

------------------------------------------------------------------------
-- Assist on: the run chains until the wishlist has nothing Desired left
------------------------------------------------------------------------

assists.autoRollContinue = true
desired = {}
desired[Key(4001, "Ability")] = true
desired[Key(4002, "Ability")] = true
desired[Key(4003, "Talent")] = true
Wishlist.AddEntry(4003, "Talent", 118, "Polymorph")

pendingHits = {
    { id = 4001, type = "Ability" },
    { id = 4002, type = "Ability" },
    { id = 4003, type = "Talent" },
}
rapid.Phase = "Idle"
rapid.StopCode = nil
closeCalls = 0
startCalls = 0

assert(AutoRoller.Start() == true, "arms with three Desired targets")

-- Two ticks per entry (open the session, then handle the hit), plus a last pair
-- for the run to notice there is nothing Desired left.
for _ = 1, 12 do
    if AutoRoller.IsRunning() then
        RunTick()
    end
end

assert(AutoRoller.IsRunning() == false, "the chain ends on its own")
assert(AutoRoller.GetDesiredHits() == 3,
    "all three Desired entries landed in one run (got " .. tostring(AutoRoller.GetDesiredHits()) .. ")")
assert(closeCalls == 3, "each session was closed through the native button")
assert(startCalls == 3, "and the next one opened through it too")
assert(AutoRoller.GetLastError() == "desired_list_done",
    "running the list out is a finish, not the no-targets refusal (got "
        .. tostring(AutoRoller.GetLastError()) .. ")")

------------------------------------------------------------------------
-- A Desired hit is handled once, not once per tick while the code lingers
--
-- Ascension leaves StopCode set for a tick or two after the session it describes
-- is gone, so the assist has to recognise the same hit rather than re-close it.
------------------------------------------------------------------------

desired = {}
desired[Key(4001, "Ability")] = true
pendingHits = {}
rapid.Phase = "Completed"
rapid.StopCode = "STOP_RAPID_ROLLING_DESIRED_ENTRY_LEARNED"
rapid.LearnedEntryID = 4001
closeCalls = 0

-- Roll() must not clear the stop code here: that is the lingering-code case.
local lingering = WildCardRapidRollingFrame.Roll
WildCardRapidRollingFrame.Roll = function()
    closeCalls = closeCalls + 1
end

assert(AutoRoller.Start() == true, "arms with the stale stop code up")
RunTick()
RunTick()
RunTick()
assert(closeCalls == 1, "the same hit is closed once, not once per tick (got " .. closeCalls .. ")")
assert(AutoRoller.IsRunning() == true, "and the run is still waiting for the code to clear")

WildCardRapidRollingFrame.Roll = lingering
AutoRoller.Stop("test_reset")

------------------------------------------------------------------------
-- An entry the client still calls Desired after learning it stops the chain
------------------------------------------------------------------------

stickyDesired = true
desired = {}
desired[Key(4001, "Ability")] = true
pendingHits = {}
for _ = 1, 6 do
    pendingHits[#pendingHits + 1] = { id = 4001, type = "Ability" }
end
rapid.Phase = "Idle"
rapid.StopCode = nil
closeCalls = 0
startCalls = 0

assert(AutoRoller.Start() == true, "arms against the sticky entry")
for _ = 1, 12 do
    if AutoRoller.IsRunning() then
        RunTick()
    end
end

assert(AutoRoller.IsRunning() == false, "the chain refuses to reroll an entry it already landed")
assert(AutoRoller.GetLastError() == "desired_repeat",
    "and says why, got " .. tostring(AutoRoller.GetLastError()))
assert(AutoRoller.GetDesiredHits() == 2, "it takes the repeat to notice, so exactly two hits")

------------------------------------------------------------------------
-- And there is still a hard ceiling on how long one Start may chain
------------------------------------------------------------------------

stickyDesired = true
desired = {}
desired[Key(4001, "Ability")] = true
pendingHits = {}
for index = 1, 60 do
    -- Distinct ids, so only the ceiling can stop this.
    pendingHits[index] = { id = 9000 + index, type = "Ability" }
end
rapid.Phase = "Idle"
rapid.StopCode = nil

assert(AutoRoller.Start() == true, "arms for the ceiling case")
for _ = 1, 200 do
    if AutoRoller.IsRunning() then
        RunTick()
    end
end

assert(AutoRoller.IsRunning() == false, "an unbounded roll loop is not on offer")
assert(AutoRoller.GetLastError() == "chain_limit",
    "the ceiling is the reason, got " .. tostring(AutoRoller.GetLastError()))
assert(AutoRoller.GetDesiredHits() == 25,
    "and it is the documented 25 (got " .. tostring(AutoRoller.GetDesiredHits()) .. ")")

------------------------------------------------------------------------
-- Auto-Roll Start merges the wishlist into Desired instead of only filling an
-- empty Desired set. One hand-made mark used to be enough to make Start ignore
-- everything else on the list.
------------------------------------------------------------------------

stickyDesired = false
assists.autoRollContinue = false
desired = {}
desired[Key(4001, "Ability")] = true
pendingHits = {}
rapid.Phase = "Idle"
rapid.StopCode = nil

assert(Wishlist.Count() == 3, "three rows on the wishlist")
assert(Wishlist.CountDesired() == 1, "one of them marked Desired by hand")

assert(AutoRoller.Start() == true, "starts")
assert(Wishlist.CountDesired() == 3,
    "Start pushes the rest of the list into Desired (got " .. Wishlist.CountDesired() .. ")")
assert(desired[Key(4001, "Ability")] == true, "and leaves the hand-made mark exactly where it was")
AutoRoller.Stop("test_done")

print("OK: AscensionSuite auto-roll continue test passed")
