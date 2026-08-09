-- AscensionSuite: automation/PopupAssist.lua
-- Opt-in auto-accept for the two Wildcard roll confirmations only.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local PopupAssist = {}
AscensionSuite.PopupAssist = PopupAssist

-- Only dialogs that gate a roll the player already asked for. Deliberately
-- excluded, because accepting them destroys or unprotects spells rather than
-- confirming a roll: CONFIRM_UNLEARN_S, CONFIRM_UNLEARN_ALL_S, UNLOCK_SPELL_CONFIRM,
-- UNLOCK_SPEC_CONFIRM, DRAFT_UNLEARN_CONFIRM, UNLEARN_SKILL, UNLEARN_SKILLID.
local ALLOWLIST = {
    CONFIRM_WILDCARD_MASS_ROLL = true,
    CONFIRM_WILDCARD_LEVELING = true,
}

local function StopAutoRollForUnlearnDialog(which)
    local API = AscensionSuite.AscensionAPI
    if API and API.IsUnlearnConfirmDialog and not API.IsUnlearnConfirmDialog(which) then
        return
    end
    local AutoRoller = AscensionSuite.AutoRoller
    if AutoRoller and AutoRoller.IsRunning and AutoRoller.IsRunning() and AutoRoller.Stop then
        AutoRoller.Stop("unlearn_decision")
    end
end

local hooked = false
local dispatcher
local pending = {}
local dispatching = false

local function GetAssists()
    local DB = AscensionSuite.Database
    if DB and DB.GetAssists then
        return DB.GetAssists()
    end
    return {}
end

local function ShouldAccept()
    local assists = GetAssists()
    return assists and assists.acceptWildcardPopups == true
end

function PopupAssist.IsAllowlisted(dialogName)
    return ALLOWLIST[dialogName] == true
end

function PopupAssist.GetAllowlist()
    local names = {}
    for name in pairs(ALLOWLIST) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Button 1 only. CONFIRM_WILDCARD_MASS_ROLL's third button is
-- "start and don't ask again", which would rewrite Ascension's own skipConfirm
-- preference behind the player's back.
function PopupAssist.AcceptVisible(which)
    if not ShouldAccept() or not ALLOWLIST[which] then
        return false
    end

    local findVisible = _G.StaticPopup_FindVisible
    local onClick = _G.StaticPopup_OnClick
    if type(findVisible) ~= "function" or type(onClick) ~= "function" then
        return false
    end

    local dialog = findVisible(which)
    if type(dialog) ~= "table" or dialog.which ~= which then
        return false
    end

    onClick(dialog, 1)
    return true
end

-- Accepting CONFIRM_WILDCARD_MASS_ROLL runs Ascension's OnAccept, which rolls.
-- Doing that inside the StaticPopup_Show hook would re-enter the popup system
-- from its own show path, so the click is dispatched on the next frame instead.
local function Queue(which)
    pending[#pending + 1] = which

    if not dispatcher then
        if type(CreateFrame) ~= "function" then
            return
        end
        dispatcher = CreateFrame("Frame")
    end

    dispatcher:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)

        if dispatching then
            return
        end
        dispatching = true

        local queued = pending
        pending = {}
        for index = 1, #queued do
            PopupAssist.AcceptVisible(queued[index])
        end

        dispatching = false
    end)
end

function PopupAssist.Init()
    if hooked or type(_G.hooksecurefunc) ~= "function" or type(_G.StaticPopup_Show) ~= "function" then
        return
    end
    hooked = true

    hooksecurefunc("StaticPopup_Show", function(which)
        if ALLOWLIST[which] and ShouldAccept() then
            Queue(which)
        end
        StopAutoRollForUnlearnDialog(which)
    end)
end
