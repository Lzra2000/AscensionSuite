-- AscensionSuite: automation/PopupAssist.lua
-- Opt-in auto-accept for allowlisted Wildcard confirm dialogs only.

local AscensionSuite = _G.AscensionSuite
if type(AscensionSuite) ~= "table" then
    AscensionSuite = {}
    _G.AscensionSuite = AscensionSuite
end

local PopupAssist = {}
AscensionSuite.PopupAssist = PopupAssist

local ALLOWLIST = {
    CONFIRM_WILDCARD_MASS_ROLL = true,
    CONFIRM_WILDCARD_LEVELING = true,
    CONFIRM_UNLEARN_S = true,
}

local hooked = false

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

local function TryAcceptPopup(which)
    if not ShouldAccept() or not ALLOWLIST[which] then
        return
    end
    if not StaticPopup_FindVisible or not StaticPopup_OnClick then
        return
    end
    local dialog = StaticPopup_FindVisible(which)
    if dialog and dialog.which == which then
        StaticPopup_OnClick(dialog, 1)
    end
end

function PopupAssist.Init()
    if hooked or not hooksecurefunc or not StaticPopup_Show then
        return
    end
    hooked = true

    hooksecurefunc("StaticPopup_Show", function(which)
        if ALLOWLIST[which] then
            TryAcceptPopup(which)
        end
    end)
end

function PopupAssist.IsAllowlisted(dialogName)
    return ALLOWLIST[dialogName] == true
end
