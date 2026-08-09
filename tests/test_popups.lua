-- AscensionSuite: tests/test_popups.lua
-- Popup accept is limited to the two Wildcard roll confirmations, is off by
-- default, and clicks the plain accept button.

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
    frame.SetScript = function(self, event, fn)
        if event == "OnUpdate" then
            updateScripts[self] = fn
        end
    end
    return frame
end

local function RunPendingUpdates()
    local ran = 0
    for frame, fn in pairs(updateScripts) do
        if fn then
            updateScripts[frame] = nil
            fn(frame)
            ran = ran + 1
        end
    end
    return ran
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

local visible = nil
local clicks = {}

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

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/automation/PopupAssist.lua")

AscensionSuite.Database.Init()
local PopupAssist = AscensionSuite.PopupAssist
assert(PopupAssist, "PopupAssist missing")

PopupAssist.Init()

-- The allowlist is exactly the roll confirmations.
local allowlist = PopupAssist.GetAllowlist()
assert(#allowlist == 2, "expected 2 allowlisted dialogs, got " .. #allowlist)
assert(PopupAssist.IsAllowlisted("CONFIRM_WILDCARD_MASS_ROLL"), "mass roll confirm should be allowlisted")
assert(PopupAssist.IsAllowlisted("CONFIRM_WILDCARD_LEVELING"), "leveling confirm should be allowlisted")

-- Anything that unlearns, unlocks or touches Draft must never be accepted.
local FORBIDDEN = {
    "CONFIRM_UNLEARN_S",
    "CONFIRM_UNLEARN_ALL_S",
    "UNLOCK_SPELL_CONFIRM",
    "UNLOCK_SPEC_CONFIRM",
    "DRAFT_UNLEARN_CONFIRM",
    "UNLEARN_SKILL",
    "UNLEARN_SKILLID",
    "CONFIRM_RESET_BUILD",
    "CONFIRM_RESET_BUILD_NO_COST",
    "RECOVER_WILDCARD_ROLL_CONFIRM",
}
for index = 1, #FORBIDDEN do
    assert(not PopupAssist.IsAllowlisted(FORBIDDEN[index]),
        FORBIDDEN[index] .. " must not be auto-accepted")
end

-- Default off: showing an allowlisted popup changes nothing.
assert(AscensionSuiteDB.assists.acceptWildcardPopups == false, "popup accept default off")
StaticPopup_Show("CONFIRM_WILDCARD_MASS_ROLL", nil, nil, Noop)
RunPendingUpdates()
assert(#clicks == 0, "no click while assist is off")
assert(StaticPopup_FindVisible("CONFIRM_WILDCARD_MASS_ROLL"), "dialog should still be waiting")

-- Opt in: the click lands, on button 1, on the next frame rather than inline.
AscensionSuiteDB.assists.acceptWildcardPopups = true
visible = nil

local rolled = 0
StaticPopup_Show("CONFIRM_WILDCARD_MASS_ROLL", nil, nil, function() rolled = rolled + 1 end)
assert(#clicks == 0, "click must be deferred out of the StaticPopup_Show hook")
assert(RunPendingUpdates() > 0, "a deferred dispatch should have been queued")
assert(#clicks == 1, "expected one click, got " .. #clicks)
assert(clicks[1].which == "CONFIRM_WILDCARD_MASS_ROLL", "clicked the right dialog")
assert(clicks[1].index == 1,
    "must click button 1, not the 'don't ask again' button, got index " .. tostring(clicks[1].index))

-- A non-allowlisted popup stays untouched even with the assist on.
visible = nil
clicks = {}
StaticPopup_Show("CONFIRM_UNLEARN_S", nil, nil, Noop)
RunPendingUpdates()
assert(#clicks == 0, "unlearn confirm must be left for the player")
assert(StaticPopup_FindVisible("CONFIRM_UNLEARN_S"), "unlearn confirm still waiting")

-- Accepting something that is not on screen is a no-op, not an error.
visible = nil
assert(PopupAssist.AcceptVisible("CONFIRM_WILDCARD_LEVELING") == false, "nothing visible to accept")

print("OK: AscensionSuite popup assist test passed")
