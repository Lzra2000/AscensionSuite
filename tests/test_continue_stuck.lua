-- AscensionSuite: tests/test_continue_stuck.lua
-- Gray Continue / die stuck on "?" must not look like a successful Auto-Roll tick.

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

CreateFrame = function()
    return {
        RegisterEvent = Noop,
        SetScript = Noop,
        EnableMouse = Noop,
        RegisterForDrag = Noop,
        SetMovable = Noop,
        SetClampedToScreen = Noop,
        SetFrameStrata = Noop,
        SetSize = Noop,
        SetPoint = Noop,
        CreateFontString = function()
            return {
                SetPoint = Noop,
                SetText = Noop,
                SetTextColor = Noop,
                SetWidth = Noop,
                SetJustifyH = Noop,
            }
        end,
        CreateTexture = function()
            return { SetAllPoints = Noop, SetTexture = Noop, SetVertexColor = Noop }
        end,
    }
end

UnitLevel = function() return 20 end
UnitName = function() return "Tester" end

local rapidState = {
    Phase = "Revealing",
    StopCode = nil,
}

local rollCalls = 0
local cancelCalls = 0

_G.C_Wildcard = {
    IsGameModeActive = function() return true end,
}
_G.C_GameMode = {
    GetGameMode = function() return 1 end,
}

-- Minimal GameMode gate: AscensionAPI accepts any truthy wildcard probe.
-- Force the seam's RequireWildcard path open via IsWildcardModeActive monkey
-- after load if needed.

local diceShown = true
_G.WildCardDice = {
    isRapidRolling = true,
    pendingReveal = { 2001, 1 },
    IsShown = function() return diceShown end,
    Hide = function(self) diceShown = false end,
    Core = {
        State = { IDLE = "IDLE" },
        GetState = function() return "REVEALING" end,
    },
}

_G.WildCardRapidRollingFrame = {
    IsShown = function() return true end,
    Roll = function()
        rollCalls = rollCalls + 1
        -- Native early-out: inFlight / dice active without Continue.
    end,
    UpdateRollButton = Noop,
    RegisterEvent = Noop,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")

AscensionSuite.Database.Init()
local API = AscensionSuite.AscensionAPI

-- Patch live probes the seam uses.
API.IsWildcardModeActive = function() return true end
API.GetRapidRollingState = function() return rapidState end
API.CancelRapidRolling = function()
    cancelCalls = cancelCalls + 1
    return true
end

assert(API.IsRapidRollingDiceActive(rapidState) == true, "die with pendingReveal is active")
assert(API.IsRapidRollingAdvanceBlocked(rapidState) == true, "reveal phase blocks advance")

local ok, err = API.AdvanceRapidRoll(true)
assert(ok == false, "blocked advance must fail")
assert(err == "roll_in_flight", "expected roll_in_flight, got " .. tostring(err))
assert(rollCalls == 0, "native Roll must not be called while blocked")

-- AwaitingContinue is actionable.
rapidState.Phase = "AwaitingContinue"
_G.WildCardDice.pendingReveal = nil
_G.WildCardDice.Core.GetState = function() return "DECISION_PENDING" end
assert(API.IsRapidRollingAdvanceBlocked(rapidState) == false, "Continue phase is not blocked")

ok, err = API.AdvanceRapidRoll(true)
assert(ok == true, "Continue phase should advance")
assert(rollCalls == 1, "Roll should run once when unblocked")

-- Recovery clears the stranded die.
diceShown = true
_G.WildCardDice.pendingReveal = { 2001, 1 }
rapidState.Phase = "Revealing"
local recovered = API.RecoverStuckRapidSession()
assert(recovered == true, "recover should succeed in Wildcard")
assert(cancelCalls >= 1, "recover cancels the server session")
assert(_G.WildCardDice.pendingReveal == nil, "pendingReveal cleared")
assert(diceShown == false, "die hidden after recover")

print("OK: AscensionSuite continue-stuck test passed")
