-- AscensionSuite: automation/AnimationSkip.lua
-- Opt-in instant reveal for WildCardDice / SkillCard animations.
--
-- Everything here only changes playback *speed* of Ascension's own animations
-- and then lets the client's own finish callbacks fire. It never calls the
-- native OnFinished* handlers directly: those handlers drive the dice state
-- machine (pendingReveal -> SetInternalID -> DECISION_PENDING), so invoking one
-- while its flipbook is still playing runs the transition twice and can strand
-- the dice mid-session. It never starts a roll either.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local AnimationSkip = {}
AscensionSuite.AnimationSkip = AnimationSkip

-- Ascension's own speeds, restored when the assist is switched back off
-- (Ascension_WildCard/Dice/WildCardDice.lua Layout()).
local DICE_FLIPBOOK_SPEEDS = {
    { name = "DiceAppearFlipBook", native = 1 },
    { name = "DiceCrackFlipBook", native = 3 },
    { name = "DiceCollapseFlipBook", native = 2 },
    { name = "DiceRollFlipBook", native = 2 },
}

local SKILLCARD_FLIPBOOKS = { "FlipBookCommon", "FlipBookQuality", "FlipBookQualityGlow" }
local SKILLCARD_NATIVE_SPEED = 1

-- AtlasVerticalFlipbookMixin turns speed S into frameStep ~= S, so a large S
-- crosses every frame of a book in one or two OnUpdate ticks.
local SKIP_SPEED = 60

-- Ascension reads DEBUG_WC_ROULETTE_DURATION for the icon reel on the leveling
-- roll path (WildCardRouletteMixin:Play); rapid rolling hardcodes 0.5.
local SKIP_ROULETTE_DURATION = 0.05

local attachedDice = false
local attachedSkillCard = false
local loadWatcher
local ensureFrame
local ensurePending = false
local ensureElapsed = 0
local ENSURE_DEFER_SECONDS = 0.2
local recoveryUntil = 0
local RECOVERY_WINDOW_SECONDS = 1.5

local function MarkDiceSkipRecovery()
    if not ShouldSkipDice() then
        return
    end
    local now = 0
    if type(_G.GetTime) == "function" then
        now = _G.GetTime()
    end
    recoveryUntil = now + RECOVERY_WINDOW_SECONDS
end

local function ShouldDeferDiceRecovery()
    local API = AscensionSuite.AscensionAPI
    if not API then
        return false
    end
    if API.ShouldLetDiceHide and API.ShouldLetDiceHide() then
        return true
    end
    if API.IsDiceRecoveryCooldownActive and API.IsDiceRecoveryCooldownActive() then
        return true
    end
    if API.IsDiceFadingOut and API.IsDiceFadingOut() then
        return true
    end
    return false
end

local function ScheduleEnsureDiceClickable(forceDecision)
    local API = AscensionSuite.AscensionAPI
    if not API or not API.EnsureDiceClickable then
        return
    end

    if not forceDecision and ShouldDeferDiceRecovery() then
        if API.ClearDiceClickStealer then
            API.ClearDiceClickStealer()
        end
        if API.ClearDiceHoverArtifacts then
            API.ClearDiceHoverArtifacts()
        end
        return
    end

    if not ensureFrame and type(CreateFrame) == "function" then
        ensureFrame = CreateFrame("Frame")
        ensureFrame:SetScript("OnUpdate", function(self, delta)
            if not ensurePending then
                return
            end
            ensureElapsed = ensureElapsed + (delta or 0)
            if ensureElapsed < ENSURE_DEFER_SECONDS then
                return
            end
            ensurePending = false
            ensureElapsed = 0
            if ShouldDeferDiceRecovery() then
                if API.ClearDiceClickStealer then
                    API.ClearDiceClickStealer()
                end
                return
            end
            MarkDiceSkipRecovery()
            API.EnsureDiceClickable()
        end)
    end

    ensurePending = true
    ensureElapsed = 0
end

function AnimationSkip.IsRecoveryActive()
    if recoveryUntil <= 0 then
        return false
    end
    if type(_G.GetTime) ~= "function" then
        return false
    end
    return _G.GetTime() < recoveryUntil
end

local function GetAssists()
    local DB = AscensionSuite.Database
    if DB and DB.GetAssists then
        return DB.GetAssists()
    end
    return {}
end

local function ShouldSkipDice()
    local assists = GetAssists()
    return assists and assists.instantDiceSkip == true
end

local function ShouldSkipSkillCard()
    local assists = GetAssists()
    return assists and assists.instantSkillCardSkip == true
end

local function SetFlipBookSpeed(flipBook, speed)
    if type(flipBook) ~= "table" or type(flipBook.SetSpeed) ~= "function" then
        return false
    end
    local ok = pcall(flipBook.SetSpeed, flipBook, speed)
    return ok
end

------------------------------------------------------------------------
-- WildCardDice
------------------------------------------------------------------------

-- Speed is read by AtlasVerticalFlipbookMixin:Play(), so this must be applied
-- before the next Play() rather than while a book is mid-flight.
function AnimationSkip.ApplyDiceSpeeds(dice)
    dice = dice or _G.WildCardDice
    if type(dice) ~= "table" then
        return false
    end

    local skip = ShouldSkipDice()
    local applied = 0
    for index = 1, #DICE_FLIPBOOK_SPEEDS do
        local info = DICE_FLIPBOOK_SPEEDS[index]
        local speed = skip and SKIP_SPEED or info.native
        if SetFlipBookSpeed(dice[info.name], speed) then
            applied = applied + 1
        end
    end

    if skip then
        _G.DEBUG_WC_ROULETTE_DURATION = SKIP_ROULETTE_DURATION
    elseif _G.DEBUG_WC_ROULETTE_DURATION == SKIP_ROULETTE_DURATION then
        _G.DEBUG_WC_ROULETTE_DURATION = nil
    end

    return applied > 0
end

-- The icon reel is an AnimationGroup, not a flipbook, so speed does not apply.
-- Finishing it fires OnFinished -> OnRouletteFinished, which is the same path a
-- naturally completed reel takes on the *leveling* dice. Rapid Rolling wires
-- reveal through pendingReveal + flipbook order; finishing the reel early there
-- can leave the dice shown with pendingReveal set while Phase never reaches
-- AwaitingContinue — Continue stays gray forever. So rapid sessions only get
-- the flipbook speed-up above; the reel plays out on its already-short duration.
function AnimationSkip.SkipRoulette(scrollFrame)
    if not ShouldSkipDice() or type(scrollFrame) ~= "table" then
        return false
    end

    local dice = _G.WildCardDice
    if type(dice) == "table" and dice.isRapidRolling then
        return false
    end

    local content = scrollFrame.Content
    local group = content and content.AnimationGroup
    if type(group) ~= "table" then
        return false
    end

    if type(group.Finish) == "function" then
        local ok = pcall(group.Finish, group)
        return ok
    end
    if type(group.Stop) == "function" then
        local ok = pcall(group.Stop, group)
        return ok
    end
    return false
end

local function AttachDice()
    local dice = _G.WildCardDice
    if attachedDice or type(dice) ~= "table" or type(_G.hooksecurefunc) ~= "function" then
        return false
    end
    attachedDice = true

    AnimationSkip.ApplyDiceSpeeds(dice)

    -- Re-assert speeds on each show and after each book starts, so a toggle
    -- flipped mid-session takes effect on the following animation.
    if type(dice.OnShow) == "function" then
        hooksecurefunc(dice, "OnShow", function(self)
            AnimationSkip.ApplyDiceSpeeds(self)
        end)
    end

    if type(dice.PlayFlipBook) == "function" then
        hooksecurefunc(dice, "PlayFlipBook", function(self)
            AnimationSkip.ApplyDiceSpeeds(self)
        end)
    end

    if type(dice.OnFinishedAppear) == "function" then
        hooksecurefunc(dice, "OnFinishedAppear", function()
            ScheduleEnsureDiceClickable()
        end)
    end

    if type(dice.SetInternalID) == "function" then
        hooksecurefunc(dice, "SetInternalID", function()
            ScheduleEnsureDiceClickable(true)
        end)
    end

    local scrollFrame = dice.ScrollFrame
    if type(scrollFrame) == "table" and type(scrollFrame.Play) == "function" then
        hooksecurefunc(scrollFrame, "Play", function(self)
            AnimationSkip.SkipRoulette(self)
        end)
    end

    return true
end

------------------------------------------------------------------------
-- SkillCard reveal covers
------------------------------------------------------------------------

function AnimationSkip.ApplySkillCardSpeeds(cover)
    if type(cover) ~= "table" then
        return false
    end

    local speed = ShouldSkipSkillCard() and SKIP_SPEED or SKILLCARD_NATIVE_SPEED
    local applied = 0
    for index = 1, #SKILLCARD_FLIPBOOKS do
        if SetFlipBookSpeed(cover[SKILLCARD_FLIPBOOKS[index]], speed) then
            applied = applied + 1
        end
    end
    return applied > 0
end

-- Covers are template instances, so speeds are applied per cover as the client
-- refreshes or flips one. Covers built before this hook keeps their own copy of
-- the mixin methods and stay at native speed.
local function AttachSkillCard()
    local mixin = _G.SkillCardUnlockCoverMixin
    if attachedSkillCard or type(mixin) ~= "table" or type(_G.hooksecurefunc) ~= "function" then
        return false
    end
    attachedSkillCard = true

    if type(mixin.UpdateVisual) == "function" then
        hooksecurefunc(mixin, "UpdateVisual", function(self)
            AnimationSkip.ApplySkillCardSpeeds(self)
        end)
    end

    if type(mixin.OnMouseUp) == "function" then
        hooksecurefunc(mixin, "OnMouseUp", function(self)
            AnimationSkip.ApplySkillCardSpeeds(self)
        end)
    end

    return true
end

------------------------------------------------------------------------
-- Wiring
------------------------------------------------------------------------

-- Ascension_WildCard and Ascension_SkillCards are load-on-demand, so the globals
-- we hook usually do not exist yet at our own ADDON_LOADED.
function AnimationSkip.Attach()
    local dice = AttachDice()
    local card = AttachSkillCard()
    return dice or card
end

-- Called when the player flips a skip toggle so the change lands immediately.
function AnimationSkip.Refresh()
    AnimationSkip.Attach()
    AnimationSkip.ApplyDiceSpeeds()
end

function AnimationSkip.Init()
    AnimationSkip.Attach()

    if loadWatcher or type(CreateFrame) ~= "function" then
        return
    end

    loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function(_, _, name)
        if name == "Ascension_WildCard" or name == "Ascension_SkillCards" then
            AnimationSkip.Attach()
        end
    end)
end
