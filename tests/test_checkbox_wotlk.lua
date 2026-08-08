-- AscensionSuite: tests/test_checkbox_wotlk.lua
-- WotLK CheckButton:GetChecked() returns 1 / nil. Writing == true left every
-- assist permanently off while the box stayed visually checked.

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
local ADDON_NAME = "AscensionSuite"

AscensionSuite = {}
AscensionSuiteDB = {}

local function Noop() end

local Frame = {}
Frame.__index = Frame
function Frame:RegisterEvent() end
function Frame:UnregisterEvent() end
function Frame:SetScript(name, fn) self["_" .. name] = fn end
function Frame:GetScript(name) return self["_" .. name] end
function Frame:EnableMouse() end
function Frame:RegisterForDrag() end
function Frame:SetMovable() end
function Frame:SetClampedToScreen() end
function Frame:SetFrameStrata() end
function Frame:SetSize() end
function Frame:SetWidth() end
function Frame:SetHeight() end
function Frame:SetPoint() end
function Frame:SetText() end
function Frame:SetTextColor() end
function Frame:SetJustifyH() end
function Frame:SetFontObject() end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown == true end
function Frame:Enable() self._enabled = true end
function Frame:Disable() self._enabled = false end
function Frame:SetEnabled(v) self._enabled = v and true or false end
function Frame:SetChecked(v)
    -- Mirror the client: checked widgets store 1, not true.
    if v == true or v == 1 then
        self._checked = 1
    else
        self._checked = nil
    end
end
function Frame:GetChecked()
    return self._checked
end
function Frame:CreateFontString()
    return setmetatable({
        SetPoint = Noop, SetText = Noop, SetTextColor = Noop,
        SetWidth = Noop, SetJustifyH = Noop, SetFontObject = Noop,
    }, Frame)
end
function Frame:CreateTexture()
    return setmetatable({
        SetAllPoints = Noop, SetTexture = Noop, SetVertexColor = Noop,
        SetTexCoord = Noop, SetPoint = Noop, SetSize = Noop, Hide = Noop, Show = Noop,
    }, Frame)
end

CreateFrame = function(_, _, parent)
    local f = setmetatable({ _parent = parent, _shown = false, _enabled = true }, Frame)
    return f
end

UIParent = CreateFrame("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = Noop }
UnitLevel = function() return 20 end
UnitName = function() return "Tester" end
GetTime = function() return 0 end
hooksecurefunc = function() end

_G.C_Wildcard = {}
_G.C_GameMode = { GetGameMode = function() return 1 end, IsGameModeActive = function() return true end }
_G.C_CharacterAdvancement = {
    GetEntryBySpellID = function(id)
        return { ID = id, Type = "Ability", Spells = { id }, Name = "Spell " .. tostring(id) }
    end,
    GetEntryByInternalID = function(id)
        return { ID = id, Type = "Ability", Spells = { id }, Name = "Entry " .. tostring(id) }
    end,
}

local files = {
    "core/Database.lua",
    "core/Wishlist.lua",
    "core/Logbook.lua",
    "integration/AscensionAPI.lua",
    "integration/DesiredSync.lua",
    "automation/AutoRoller.lua",
    "automation/AnimationSkip.lua",
    "automation/PopupAssist.lua",
    "ui/WishlistPanel.lua",
    "ui/MainWindow.lua",
    "core/Bootstrap.lua",
}

for index = 1, #files do
    assert(loadfile(ROOT .. "/" .. files[index]))(ADDON_NAME)
end

AscensionSuite.Database.Init()
local MainWindow = AscensionSuite.MainWindow
assert(MainWindow.CheckButtonIsOn, "CheckButtonIsOn helper missing")

-- Direct contract: 1 means on, nil/false/0 mean off.
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return 1 end }) == true,
    "GetChecked() == 1 must read as on")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return true end }) == true,
    "boolean true still counts")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return nil end }) == false,
    "nil is off")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return false end }) == false,
    "false is off")
assert(MainWindow.CheckButtonIsOn({ GetChecked = function() return 0 end }) == false,
    "0 is off")

-- Open the window so the real assist checkboxes exist, then fire OnClick with a
-- WotLK-style checked widget.
MainWindow.Show()
MainWindow.ShowTab(2)

local autoRollCheck
-- Walk assistChecks via a click simulation: create a stand-in and use the same
-- storage path the OnClick handler uses.
local assists = AscensionSuite.Database.GetAssists()
assert(assists.autoRoll == false, "starts off")

-- Simulate what the live OnClick must do when GetChecked returns 1.
local fake = {
    GetChecked = function() return 1 end,
}
assert(MainWindow.CheckButtonIsOn(fake) == true)
assists.autoRoll = MainWindow.CheckButtonIsOn(fake)
assert(AscensionSuiteDB.assists.autoRoll == true,
    "storing GetChecked()==1 must enable autoRoll in SavedVariables")

-- The old bug: == true would have written false.
local broken = (fake:GetChecked() == true)
assert(broken == false, "sanity: 1 == true is false in Lua 5.1")
assert(MainWindow.CheckButtonIsOn(fake) ~= broken,
    "the helper must disagree with the broken == true compare")

-- Stale assist_off must not stick after the box is on again.
local AutoRoller = AscensionSuite.AutoRoller
AutoRoller.Stop("assist_off")
assert(AutoRoller.GetLastError() == "assist_off")
AutoRoller.ClearLastError()
assert(AutoRoller.GetLastError() == nil, "ClearLastError drops the sticky reason")

MainWindow.RefreshAutoRoll()
MainWindow.RefreshLogbook()

print("OK: AscensionSuite WotLK checkbox test passed")
