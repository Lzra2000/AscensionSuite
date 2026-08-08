-- AscensionSuite: automation/AnimationSkip.lua
-- Opt-in instant finish for WildCardDice / SkillCard flipbooks (never starts rolls).

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local AnimationSkip = {}
AscensionSuite.AnimationSkip = AnimationSkip

local hooked = false

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

local function ForceFinishDice(dice)
    if not dice or not ShouldSkipDice() then
        return
    end
    if dice.HideFlipBooks then
        dice:HideFlipBooks()
    end
    if dice.OnFinishedAppear and dice.DiceAppearFlipBook and dice.DiceAppearFlipBook.IsPlaying and dice.DiceAppearFlipBook:IsPlaying() then
        dice:OnFinishedAppear()
    elseif dice.OnFinishedRoll and dice.DiceRollFlipBook and dice.DiceRollFlipBook.IsPlaying and dice.DiceRollFlipBook:IsPlaying() then
        dice:OnFinishedRoll()
    elseif dice.OnFinishedCrack and dice.DiceCrackFlipBook and dice.DiceCrackFlipBook.IsPlaying and dice.DiceCrackFlipBook:IsPlaying() then
        dice:OnFinishedCrack()
    elseif dice.OnFinishedCollapse and dice.DiceCollapseFlipBook and dice.DiceCollapseFlipBook.IsPlaying and dice.DiceCollapseFlipBook:IsPlaying() then
        dice:OnFinishedCollapse()
    end
end

local function StopFlipBook(flipBook)
    if not flipBook then
        return
    end
    if flipBook.Stop then
        flipBook:Stop()
    end
    if flipBook.Hide then
        flipBook:Hide()
    end
end

local function ForceFinishSkillCardCover(cover)
    if not cover or not ShouldSkipSkillCard() then
        return
    end
    StopFlipBook(cover.FlipBookCommon)
    StopFlipBook(cover.FlipBookQuality)
    StopFlipBook(cover.FlipBookQualityGlow)
    if cover.OnFlip then
        cover:OnFlip()
    end
end

function AnimationSkip.Init()
    if hooked then
        return
    end
    hooked = true

    local dice = _G.WildCardDice
    if dice and hooksecurefunc then
        if dice.PlayFlipBook then
            hooksecurefunc(dice, "PlayFlipBook", function(self)
                ForceFinishDice(self)
            end)
        end
        if dice.OnPlayRoll then
            hooksecurefunc(dice, "OnPlayRoll", function(self)
                ForceFinishDice(self)
            end)
        end
        if dice.OnPlayAppear then
            hooksecurefunc(dice, "OnPlayAppear", function(self)
                ForceFinishDice(self)
            end)
        end
    end

    if hooksecurefunc and _G.SkillCardUnlockCoverMixin and _G.SkillCardUnlockCoverMixin.PlayReveal then
        hooksecurefunc(_G.SkillCardUnlockCoverMixin, "PlayReveal", function(self)
            ForceFinishSkillCardCover(self)
        end)
    end
end
