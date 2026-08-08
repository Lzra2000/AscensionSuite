-- AscensionSuite: tests/test_animation_skip.lua
-- Animation skip changes playback speed only: it restores Ascension's native
-- speeds when switched off and never calls the dice finish handlers itself.

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
    }
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

-- Flipbook stub recording only what AnimationSkip is allowed to touch.
local function NewFlipBook()
    local book = { speed = nil, setSpeedCalls = 0 }
    book.SetSpeed = function(self, speed)
        self.speed = speed
        self.setSpeedCalls = self.setSpeedCalls + 1
    end
    return book
end

local finishedHandlerCalls = 0

local group = {
    finishCalls = 0,
    stopCalls = 0,
}
group.Finish = function(self) self.finishCalls = self.finishCalls + 1 end
group.Stop = function(self) self.stopCalls = self.stopCalls + 1 end

local dice = {
    DiceAppearFlipBook = NewFlipBook(),
    DiceCrackFlipBook = NewFlipBook(),
    DiceCollapseFlipBook = NewFlipBook(),
    DiceRollFlipBook = NewFlipBook(),
    ScrollFrame = {
        Content = { AnimationGroup = group },
        playCalls = 0,
    },
}

dice.OnShow = Noop
dice.PlayFlipBook = Noop
dice.ScrollFrame.Play = function(self) self.playCalls = self.playCalls + 1 end

-- If the assist ever calls these directly the dice state machine runs twice.
local function CountFinish() finishedHandlerCalls = finishedHandlerCalls + 1 end
dice.OnFinishedAppear = CountFinish
dice.OnFinishedRoll = CountFinish
dice.OnFinishedCrack = CountFinish
dice.OnFinishedCollapse = CountFinish

_G.WildCardDice = dice

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/automation/AnimationSkip.lua")

AscensionSuite.Database.Init()
local AnimationSkip = AscensionSuite.AnimationSkip
assert(AnimationSkip, "AnimationSkip missing")

local BOOKS = {
    "DiceAppearFlipBook",
    "DiceCrackFlipBook",
    "DiceCollapseFlipBook",
    "DiceRollFlipBook",
}

AnimationSkip.Init()

-- Assist defaults off: Ascension's own speeds, and no debug duration override.
local nativeSpeeds = {}
for index = 1, #BOOKS do
    local speed = dice[BOOKS[index]].speed
    assert(type(speed) == "number", BOOKS[index] .. " never received a speed")
    nativeSpeeds[BOOKS[index]] = speed
end
assert(_G.DEBUG_WC_ROULETTE_DURATION == nil, "roulette duration must stay native while off")

-- Skipping while off must leave the reel alone.
dice.ScrollFrame:Play()
assert(group.finishCalls == 0, "reel must not be finished while assist is off")

-- Turn the dice skip on.
AscensionSuiteDB.assists.instantDiceSkip = true
AnimationSkip.Refresh()

local skipSpeed
for index = 1, #BOOKS do
    local name = BOOKS[index]
    local speed = dice[name].speed
    assert(speed > nativeSpeeds[name],
        name .. " skip speed " .. tostring(speed) .. " must exceed native " .. tostring(nativeSpeeds[name]))
    skipSpeed = skipSpeed or speed
    assert(speed == skipSpeed, "all dice books share one skip speed")
end

local duration = _G.DEBUG_WC_ROULETTE_DURATION
assert(type(duration) == "number" and duration > 0 and duration < 0.5,
    "roulette duration override must be a small positive number, got " .. tostring(duration))

-- Reel is finished through the client's own completion path.
dice.ScrollFrame:Play()
assert(group.finishCalls == 1, "reel should be finished once per play, got " .. group.finishCalls)
assert(group.stopCalls == 0, "Finish() is preferred over Stop() when available")

-- Native finish handlers stay untouched: that is what caused double transitions.
assert(finishedHandlerCalls == 0,
    "animation skip must not invoke dice OnFinished* handlers (" .. finishedHandlerCalls .. " calls)")

-- Turn it back off: exact native speeds restored, override cleared.
AscensionSuiteDB.assists.instantDiceSkip = false
AnimationSkip.Refresh()

for index = 1, #BOOKS do
    local name = BOOKS[index]
    assert(dice[name].speed == nativeSpeeds[name],
        name .. " should be restored to " .. tostring(nativeSpeeds[name]) .. ", got " .. tostring(dice[name].speed))
end
assert(_G.DEBUG_WC_ROULETTE_DURATION == nil, "roulette duration override must be cleared")

dice.ScrollFrame:Play()
assert(group.finishCalls == 1, "reel must not be finished again once assist is off")

-- SkillCard covers use the same speed-only treatment.
local cover = {
    FlipBookCommon = NewFlipBook(),
    FlipBookQuality = NewFlipBook(),
    FlipBookQualityGlow = NewFlipBook(),
}

AscensionSuiteDB.assists.instantSkillCardSkip = true
assert(AnimationSkip.ApplySkillCardSpeeds(cover), "skillcard speeds should apply")
assert(cover.FlipBookCommon.speed == skipSpeed, "skillcard shares the dice skip speed")
assert(cover.FlipBookQuality.speed == skipSpeed, "quality book skipped")
assert(cover.FlipBookQualityGlow.speed == skipSpeed, "quality glow book skipped")

AscensionSuiteDB.assists.instantSkillCardSkip = false
AnimationSkip.ApplySkillCardSpeeds(cover)
assert(cover.FlipBookCommon.speed == 1, "skillcard restored to native speed")

-- Missing client globals must not error.
_G.WildCardDice = nil
AnimationSkip.Refresh()

print("OK: AscensionSuite animation skip test passed")
