-- AscensionSuite: tests/test_loadouts_panel.lua
-- Loadouts tab builds on first open, survives tab round-trips, and keeps widths.

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

local function NewFontString()
    local text = ""
    local width
    local shown = true
    return {
        SetPoint = Noop,
        SetWidth = function(_, value) width = value end,
        GetWidth = function() return width or 0 end,
        SetHeight = Noop,
        SetJustifyH = Noop,
        SetTextColor = Noop,
        SetText = function(_, value) text = value or "" end,
        GetText = function() return text end,
        Show = function() shown = true end,
        Hide = function() shown = false end,
        IsShown = function() return shown end,
    }
end

local function NewTexture()
    local shown = true
    return {
        SetAllPoints = Noop,
        SetPoint = Noop,
        SetTexCoord = Noop,
        SetWidth = Noop,
        SetHeight = Noop,
        SetTexture = Noop,
        Show = function() shown = true end,
        Hide = function() shown = false end,
        IsShown = function() return shown end,
    }
end

local Frame = {}
Frame.__index = function(_, key)
    if type(key) == "string" and key:sub(1, 1) == "_" then
        return nil
    end
    return Frame[key] or Noop
end

function Frame:SetScript(script, fn) self._scripts[script] = fn end
function Frame:GetScript(script) return self._scripts[script] end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown == true end
function Frame:SetText(value) self._text = value end
function Frame:GetText() return self._text or "" end
function Frame:SetEnabled(value) self._enabled = value and true or false end
function Frame:GetID() return self._id end
function Frame:SetID(value) self._id = value end
function Frame:GetFrameLevel() return self._frameLevel or 0 end
function Frame:SetFrameLevel(value) self._frameLevel = value end
function Frame:SetWidth(value) self._width = value end
function Frame:GetWidth() return self._width or 0 end
function Frame:SetHeight(value) self._height = value end
function Frame:GetHeight() return self._height or 0 end
function Frame:EnableMouse() end
function Frame:RegisterForClicks() end
function Frame:CreateFontString() return NewFontString() end
function Frame:CreateTexture() return NewTexture() end
function Frame:ClearAllPoints() end
function Frame:SetAllPoints() end
function Frame:Click()
    local handler = self._scripts.OnClick
    if handler then
        handler(self)
    end
end

CreateFrame = function(kind, name, parent, template)
    local frame = setmetatable({
        _scripts = {},
        _shown = true,
        _kind = kind,
        _name = name,
        _parent = parent,
        _template = template,
    }, Frame)
    if name then
        _G[name] = frame
    end
    return frame
end

UIParent = CreateFrame("Frame")
GameTooltip = CreateFrame("Frame")
hooksecurefunc = function() end
PanelTemplates_SetTab = function() end
PanelTemplates_SetNumTabs = function() end
PanelTemplates_TabResize = function() end

FauxScrollFrame_Update = function(frame, numItems)
    frame._numItems = numItems
end
FauxScrollFrame_GetOffset = function(frame) return frame._offset or 0 end
FauxScrollFrame_SetOffset = function(frame, offset) frame._offset = offset end
FauxScrollFrame_OnVerticalScroll = function(frame, offset, valueStep, updater)
    frame._offset = math.floor((offset or 0) / (valueStep or 1))
    if updater then
        updater(frame)
    end
end

DEFAULT_CHAT_FRAME = { AddMessage = Noop }
function GetTime() return 0 end

local wildcard = false

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return wildcard and mode == "WildCard"
    end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        return { ID = 1133, Type = "Ability", Spell = id, Name = "Fireball" }
    end,
    GetEntryByInternalID = function(_, id)
        return { ID = id, Type = "Ability", Spell = 133, Name = "Fireball" }
    end,
    GetKnownSpellEntries = function() return {} end,
    GetKnownTalentEntries = function() return {} end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function() return true end,
    RemoveDesiredID = function() return true end,
    IsDesiredID = function() return false end,
    ClearDesiredSpells = function() return true end,
    GetNumFilteredDesiredEntries = function() return 0 end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/core/Loadouts.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/ui/WishlistPanel.lua")
dofile(ROOT .. "/ui/LoadoutsPanel.lua")
dofile(ROOT .. "/ui/MainWindow.lua")

AscensionSuite.Database.Init()

local Loadouts = AscensionSuite.Loadouts
local Panel = AscensionSuite.LoadoutsPanel
local MainWindow = AscensionSuite.MainWindow

local loadout, id = Loadouts.Create("Test build", "notes", false)
assert(loadout and id, "seed loadout")

------------------------------------------------------------------------
-- Build on first Loadouts tab open (parent was hidden until then)
------------------------------------------------------------------------

local window = MainWindow.Show()
assert(window:IsShown(), "/asuite opens")

MainWindow.SelectTab(2)
assert(MainWindow.GetActiveTab() == 2, "Loadouts tab active")

local frame = Panel.GetFrame()
assert(frame, "loadouts panel builds on first tab open")

local listRow = _G.AscensionSuiteLoadoutsPanelListRow1
assert(listRow and listRow:GetWidth() > 0, "list rows have non-zero width after build")

local spellRow = _G.AscensionSuiteLoadoutsPanelSpellRow1
assert(spellRow and spellRow:GetWidth() > 0, "spell rows have non-zero width after build")
assert(Panel.GetActiveSection() == "SPELLS_AND_TALENTS", "default section is spells")

------------------------------------------------------------------------
-- Layout invalidation keeps widths after tab round-trip
------------------------------------------------------------------------

MainWindow.SelectTab(3)
MainWindow.SelectTab(2)
Panel.InvalidateLayout()

assert(listRow:GetWidth() > 0, "list row width survives Assists round-trip")
if spellRow then
    assert(spellRow:GetWidth() > 0, "spell row width survives Assists round-trip")
end
assert(Panel.GetFilteredEntries() ~= nil, "filtered entries table exists")

------------------------------------------------------------------------
-- Refresh lists saved builds
------------------------------------------------------------------------

local list = Loadouts.List()
assert(#list >= 1, "saved build is listed")
Panel.Refresh()
assert(listRow:IsShown(), "the first list row is visible after refresh")

print("OK: AscensionSuite loadouts panel test passed")
