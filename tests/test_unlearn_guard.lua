-- AscensionSuite: tests/test_unlearn_guard.lua
-- Auto-Roll and AdvanceRapidRoll must halt on keep-vs-unlearn / Scroll-of-Fortune
-- decisions; PopupAssist must never accept unlearn confirms.

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
local visible = nil
local clicks = {}

CreateFrame = function()
    local frame = {}
    frame.RegisterEvent = Noop
    frame.SetScript = function(self, script, fn)
        if script == "OnUpdate" then
            updateScripts[self] = fn
        end
    end
    return frame
end

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

local function RunPendingUpdates()
    for frame, fn in pairs(updateScripts) do
        if fn then
            updateScripts[frame] = nil
            fn(frame)
        end
    end
end

hooksecurefunc = function(arg1, arg2, arg3)
    local host, key, post
    if type(arg1) == "table" then
        host, key, post = arg1, arg2, arg3
    else
        host, key, post = _G, arg1, arg2
    end
    local original = host[key]
    assert(type(original) == "function", "cannot hook missing " .. tostring(key))
    host[key] = function(...)
        local results = { original(...) }
        post(...)
        return unpack(results)
    end
end

StaticPopup_Show = function(which, _, _, data)
    visible = { which = which, data = data }
    return visible
end

StaticPopup_FindVisible = function(which)
    if visible and visible.which == which then
        return visible
    end
    return nil
end

StaticPopup_OnClick = function(dialog, index)
    clicks[#clicks + 1] = { which = dialog.which, index = index }
    visible = nil
end

function UnitLevel() return 20 end

local desired = {}
local rollCalls = 0
local rapidPhase = nil

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        if id == 133 then
            return { ID = 1133, Type = "Ability", Spell = 133, Name = "Wish" }
        end
        return nil
    end,
    GetEntryByInternalID = function() return nil end,
}

C_Wildcard = {
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
    RollAbilities = function()
        rollCalls = rollCalls + 1
        return true
    end,
    GetRapidRollingState = function()
        return { Phase = rapidPhase }
    end,
}

local diceShown = false
local diceCoreState = "IDLE"
local rollButtonVisible = false

_G.WildCardDice = {
    isRapidRolling = false,
    pendingReveal = nil,
    IsShown = function() return diceShown end,
    Core = {
        State = {
            IDLE = "IDLE",
            READY_TO_ROLL = "READY_TO_ROLL",
            DECISION_PENDING = "DECISION_PENDING",
        },
        GetState = function() return diceCoreState end,
    },
    RollButton = {
        IsVisible = function() return rollButtonVisible end,
    },
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/automation/AutoRoller.lua")
dofile(ROOT .. "/automation/PopupAssist.lua")

AscensionSuite.Database.Init()

local API = AscensionSuite.AscensionAPI
local AutoRoller = AscensionSuite.AutoRoller
local PopupAssist = AscensionSuite.PopupAssist
local Wishlist = AscensionSuite.Wishlist

API.IsWildcardModeActive = function() return true end

-- Deny-list covers every CA unlearn StaticPopup from patch-B extracts.
local denyList = API.GetUnlearnConfirmDialogs()
assert(#denyList >= 5, "expected unlearn deny-list entries, got " .. #denyList)
for index = 1, #denyList do
    assert(API.IsUnlearnConfirmDialog(denyList[index]),
        denyList[index] .. " should be an unlearn confirm dialog")
    assert(not PopupAssist.IsAllowlisted(denyList[index]),
        denyList[index] .. " must not be allowlisted")
end

-- DECISION_PENDING on the leveling die.
diceShown = true
diceCoreState = "DECISION_PENDING"
rollButtonVisible = false
assert(API.IsDiceDecisionPending() == true, "DECISION_PENDING detected")
assert(API.IsUnlearnOrKeepDecisionPending() == true, "decision pending blocks assists")

local ok, err = API.AdvanceRapidRoll(true)
assert(ok == false and err == "unlearn_decision",
    "AdvanceRapidRoll must refuse, got " .. tostring(ok) .. " / " .. tostring(err))
assert(rollCalls == 0, "must not call RollAbilities during decision pending")

-- Visible CONFIRM_UNLEARN_S.
diceShown = false
diceCoreState = "IDLE"
visible = { which = "CONFIRM_UNLEARN_S" }
assert(API.IsUnlearnConfirmVisible() == true, "visible unlearn confirm detected")
assert(API.IsUnlearnOrKeepDecisionPending() == true, "visible confirm blocks assists")
visible = nil

-- Rapid WaitingForUnlearn phase.
rapidPhase = "WaitingForUnlearn"
assert(API.IsRapidRollingWaitingForUnlearn() == true, "WaitingForUnlearn detected")
assert(API.IsUnlearnOrKeepDecisionPending() == true, "rapid unlearn phase blocks assists")
rapidPhase = nil

-- Leveling RollButton offer (Unlearn and Roll).
diceShown = true
diceCoreState = "IDLE"
rollButtonVisible = true
assert(API.IsDiceUnlearnRollOffered() == true, "RollButton offer detected")
assert(API.IsUnlearnOrKeepDecisionPending() == true, "RollButton offer blocks assists")

-- Auto-Roll stops on tick when decision becomes pending.
AscensionSuiteDB.assists.autoRoll = true
Wishlist.Add(133, "Ability", "Wish")
rollCalls = 0
diceShown = false
diceCoreState = "IDLE"
rollButtonVisible = false

assert(AutoRoller.Start() == true, "Auto-Roll arms")
assert(AutoRoller.IsRunning() == true, "running before decision")

diceShown = true
diceCoreState = "DECISION_PENDING"
RunTick()
assert(AutoRoller.IsRunning() == false, "must stop on unlearn decision")
assert(AutoRoller.GetLastError() == "unlearn_decision",
    "reports unlearn_decision, got " .. tostring(AutoRoller.GetLastError()))
assert(rollCalls == 0, "Auto-Roll must not spend scrolls while decision is up")

-- PopupAssist halts a running Auto-Roll when an unlearn confirm appears.
AutoRoller.ClearLastError()
diceCoreState = "IDLE"
rollButtonVisible = false
rollCalls = 0
visible = nil
clicks = {}

assert(AutoRoller.Start() == true, "Auto-Roll arms again")
assert(AutoRoller.IsRunning() == true, "running before popup")

PopupAssist.Init()
AscensionSuiteDB.assists.acceptWildcardPopups = true
StaticPopup_Show("CONFIRM_UNLEARN_S", nil, nil, Noop)
RunPendingUpdates()

assert(AutoRoller.IsRunning() == false, "popup must stop Auto-Roll")
assert(AutoRoller.GetLastError() == "unlearn_decision",
    "popup stop reason, got " .. tostring(AutoRoller.GetLastError()))
assert(#clicks == 0, "must not accept unlearn confirm")
assert(StaticPopup_FindVisible("CONFIRM_UNLEARN_S"), "dialog left for the player")

print("OK: AscensionSuite unlearn guard test passed")
