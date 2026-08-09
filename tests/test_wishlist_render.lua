-- AscensionSuite: tests/test_wishlist_render.lua
-- Store has wishlist rows but the /asuite panel must list them after CA adds.

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
    local shown = true
    return {
        SetPoint = Noop,
        SetWidth = Noop,
        SetHeight = Noop,
        SetJustifyH = Noop,
        SetTextColor = Noop,
        SetText = function(_, value)
            text = value or ""
        end,
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

local messages = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, text)
        messages[#messages + 1] = tostring(text)
    end,
}

function GetTime() return 1000 end
function IsAltKeyDown() return true end
function CloseDropDownMenus() end

function GetSpellInfo(spellId)
    return "Spell " .. tostring(spellId), "Rank 1", "Interface\\Icons\\Test"
end

local wildcard = false

local ENTRIES = {
    [3001] = { ID = 3001, Type = "Ability", Spells = { 133 }, Name = "Fireball" },
    [3002] = { ID = 3002, Type = "Ability", Spells = { 116 }, Name = "Ice Block" },
    [3003] = { ID = 3003, Type = "Talent", Spells = { 118 }, Name = "Polymorph" },
}

C_GameMode = {
    IsGameModeActive = function(_, mode)
        return wildcard and mode == "WildCard"
    end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        for _, entry in pairs(ENTRIES) do
            if entry.Spells[1] == id then
                return entry
            end
        end
        return nil
    end,
    GetEntryByInternalID = function(_, id)
        return ENTRIES[id]
    end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function() return true end,
    RemoveDesiredID = function() return true end,
    IsDesiredID = function() return false end,
}

CharacterAdvancement = {
    ShowSpellDropDownMenu = function(_, spellButton)
        return AscensionSuite.DesiredSync.OnSpellDropDown(spellButton)
    end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/integration/DesiredSync.lua")
dofile(ROOT .. "/ui/NativeChrome.lua")
dofile(ROOT .. "/ui/WishlistPanel.lua")
dofile(ROOT .. "/ui/MainWindow.lua")

AscensionSuite.Database.Init()

local Wishlist = AscensionSuite.Wishlist
local Panel = AscensionSuite.WishlistPanel
local MainWindow = AscensionSuite.MainWindow

local function MarkFromBook(entryId)
    local entry = ENTRIES[entryId]
    CharacterAdvancement:ShowSpellDropDownMenu({ entry = entry, spellID = entry.Spells[1] })
end

------------------------------------------------------------------------
-- Sparse SavedVariables: #wishlist reads 0 but pairs still has rows
------------------------------------------------------------------------

AscensionSuiteDB.wishlist = {}
AscensionSuiteDB.wishlist[2] = {
    spellId = 133,
    entryId = 3001,
    entryType = "Ability",
    name = "Fireball",
}
AscensionSuiteDB.wishlist[4] = {
    spellId = 116,
    entryId = 3002,
    entryType = "Ability",
    name = "Ice Block",
}

assert(Wishlist.Count() == 2, "sparse wishlist rows are counted")
assert(#Wishlist.Search(nil) == 2, "sparse wishlist rows are listed")

------------------------------------------------------------------------
-- CA marks reach the store and the open /asuite panel
------------------------------------------------------------------------

AscensionSuiteDB.wishlist = {}
MarkFromBook(3001)
MarkFromBook(3002)
MarkFromBook(3003)
assert(Wishlist.Count() == 3, "three book marks are stored")

local window = MainWindow.Show()
assert(window:IsShown(), "/asuite opens")
assert(Panel.GetFrame(), "wishlist panel builds on first show")

local filtered = Panel.GetFilteredRows()
assert(#filtered == 3, "the panel lists all three rows (got " .. #filtered .. ")")

local row1 = _G.AscensionSuiteWishlistPanelRow1
assert(row1 and row1:IsShown(), "the first row is visible")
assert(row1._nameLabel:GetText() == "Fireball", "the row shows the resolved name")

------------------------------------------------------------------------
-- Adds while /asuite is already open refresh immediately
------------------------------------------------------------------------

MarkFromBook(3001)
assert(Wishlist.Count() == 2, "Alt + right-click again removes the duplicate row")
assert(#Panel.GetFilteredRows() == 2, "the panel drops to two rows after toggling one off")

------------------------------------------------------------------------
-- Layout invalidation keeps rows after switching tabs
------------------------------------------------------------------------

MainWindow.SelectTab(2)
MainWindow.SelectTab(1)
filtered = Panel.GetFilteredRows()
assert(#filtered == 2, "rows survive an Assists round-trip")
assert(filtered[1] and filtered[1].name ~= nil, "the first visible row still has a name")

print("OK: AscensionSuite wishlist render test passed")
