-- AscensionSuite: tests/test_wishlist_panel.lua
-- The Wishlist panel driven through its own widgets: search, scroll, add,
-- remove, and the Wildcard-gated Desired push.

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

------------------------------------------------------------------------
-- Frame stubs. Named frames land in _G exactly as the client does it, which
-- is how the test reaches the panel's buttons instead of re-implementing them.
------------------------------------------------------------------------

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
        -- Strict on purpose. The client raises on a non-string here, and the one
        -- caller that used to hand it a frame -- the scroll handler, via
        -- FauxScrollFrame_OnVerticalScroll(self, ..., updateFunction) -- only broke
        -- in game, where the harness could not see it.
        SetText = function(_, value)
            assert(type(value) == "string" or type(value) == "number",
                "FontString:SetText needs a string, got " .. type(value))
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
    local texture
    return {
        SetAllPoints = Noop,
        SetPoint = Noop,
        SetTexCoord = Noop,
        SetWidth = Noop,
        SetHeight = Noop,
        SetTexture = function(_, value) texture = value end,
        GetTexture = function() return texture end,
        Show = function() shown = true end,
        Hide = function() shown = false end,
        IsShown = function() return shown end,
    }
end

local Frame = {}
-- Underscore keys are this stub's own bookkeeping, so they must read as nil when
-- unset rather than falling through to the catch-all method. Returning Noop for
-- them would hand the addon a function where it expected a number.
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
function Frame:IsShown() return self._shown end
function Frame:SetText(value) self._text = value end
function Frame:GetText() return self._text or "" end
function Frame:SetEnabled(value) self._enabled = value and true or false end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:GetID() return self._id end
function Frame:SetID(value) self._id = value end
function Frame:GetFrameLevel() return self._frameLevel or 0 end
function Frame:SetFrameLevel(value) self._frameLevel = value end
function Frame:EnableMouse() end
function Frame:RegisterForClicks() end
function Frame:CreateFontString() return NewFontString() end
function Frame:CreateTexture() return NewTexture() end

-- Panel widgets call OnClick with no argument; the real client passes the
-- button. Both shapes go through the stored handler, so route them the same way.
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

-- Enough FauxScrollFrame for the offset maths the panel relies on, called the way
-- FrameXML calls it -- including handing the update function the scroll frame.
local function FauxUpdate(frame, numItems, numToDisplay)
    frame._numItems = numItems
    frame._numToDisplay = numToDisplay
end
FauxScrollFrame_Update = FauxUpdate
FauxScrollFrame_GetOffset = function(frame) return frame._offset or 0 end
FauxScrollFrame_SetOffset = function(frame, offset) frame._offset = offset end
FauxScrollFrame_OnVerticalScroll = function(frame, offset, valueStep, updater)
    frame._offset = math.floor((offset or 0) / (valueStep or 1))
    if updater then
        updater(frame)
    end
end

local clock = 1000
function GetTime() return clock end

------------------------------------------------------------------------
-- Client stubs
------------------------------------------------------------------------

local wildcard = false

local NAMES = {
    [133] = "Fireball",
    [116] = "Ice Block",
    [118] = "Polymorph",
    [122] = "Frost Nova",
    [780] = "Living Bomb",
    [475] = "Remove Curse",
    [604] = "Dampen Magic",
    [130] = "Slow Fall",
    [168] = "Frost Armor",
    [143] = "Ice Lance",
    [145] = "Blink",
    [147] = "Counterspell",
}

local BY_SPELL, BY_ENTRY = {}, {}
for spellId, name in pairs(NAMES) do
    local entry = { ID = spellId + 9000, Type = "Ability", Spell = spellId, Name = name }
    BY_SPELL[spellId] = entry
    BY_ENTRY[entry.ID] = entry
end

local desired = {}
local function Key(entryId, entryType)
    return tostring(entryId) .. "/" .. tostring(entryType)
end

C_GameMode = {
    IsGameModeActive = function(_, mode) return wildcard and mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id) return BY_SPELL[id] end,
    GetEntryByInternalID = function(_, id) return BY_ENTRY[id] end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, id, entryType)
        desired[Key(id, entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, id, entryType) return desired[Key(id, entryType)] == true end,
}

dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/ui/NativeChrome.lua")
dofile(ROOT .. "/ui/WishlistPanel.lua")

AscensionSuite.Database.Init()

local Wishlist = AscensionSuite.Wishlist
local Panel = AscensionSuite.WishlistPanel
assert(Panel, "WishlistPanel module missing")

local host = CreateFrame("Frame", "TestWishlistHost", UIParent)
assert(Panel.Create(host, 640), "the panel builds outside Wildcard")

local searchBox = _G.AscensionSuiteWishlistPanelSearch
local addBox = _G.AscensionSuiteWishlistPanelAdd
local addButton = _G.AscensionSuiteWishlistPanelAddButton
local clearButton = _G.AscensionSuiteWishlistPanelClearButton
local pushButton = _G.AscensionSuiteWishlistPanelPushButton
local scrollFrame = _G.AscensionSuiteWishlistPanelScroll
assert(searchBox and addBox and addButton and pushButton and scrollFrame, "panel widgets missing")

------------------------------------------------------------------------
-- Adding by id, outside Wildcard
------------------------------------------------------------------------

addBox:SetText("133")
addButton:Click()
assert(Wishlist.Count() == 1, "Add stores the row without needing Wildcard")
assert(addBox:GetText() == "", "and clears the input")
assert(#Panel.GetFilteredRows() == 1, "the list shows it")

addBox:SetText("not a number")
addButton:Click()
assert(Wishlist.Count() == 1, "junk input is refused")

for spellId in pairs(NAMES) do
    Wishlist.Add(spellId)
end
Panel.Refresh()
assert(Wishlist.Count() == 12, "twelve rows on the list")
assert(#Panel.GetFilteredRows() == 12, "and all twelve pass an empty filter")

------------------------------------------------------------------------
-- Search and scroll
------------------------------------------------------------------------

searchBox:SetText("frost")
Panel.Refresh()
local matches = Panel.GetFilteredRows()
assert(#matches == 2, "search narrows to Frost Nova and Frost Armor (got " .. #matches .. ")")

searchBox:SetText("118")
Panel.Refresh()
assert(#Panel.GetFilteredRows() == 1, "search matches ids as well as names")

searchBox:SetText("")
Panel.Refresh()
assert(#Panel.GetFilteredRows() == 12, "clearing the search restores the list")

-- Twelve rows into eight visible slots: scrolling has to move the window, not
-- the list. FrameXML calls the update function with the scroll frame, so this
-- also covers the panel taking a frame where its status note goes.
local row1 = _G.AscensionSuiteWishlistPanelRow1
local firstBeforeScroll = row1._nameLabel:GetText()
scrollFrame._scripts.OnVerticalScroll(scrollFrame, 4 * 28)
assert(scrollFrame._offset == 4, "the scroll handler converts pixels to rows")
assert(row1._nameLabel:GetText() ~= firstBeforeScroll, "and the top row follows the offset")

-- Scrolled down, then a search that leaves fewer rows than the offset. Without a
-- clamp the panel renders eight blanks over matches that are right there.
searchBox:SetText("frost")
Panel.Refresh()
assert(#Panel.GetFilteredRows() == 2, "two matches")
assert(row1:IsShown(), "the first match is drawn, not scrolled past")
assert(row1._nameLabel:GetText():lower():find("frost"), "and it is one of the matches")

searchBox:SetText("")
scrollFrame._offset = 0
Panel.Refresh()

------------------------------------------------------------------------
-- Row selection works in any mode; Desired toggle is right-click in Wildcard
------------------------------------------------------------------------

wildcard = false
Panel.Refresh()

row1 = _G.AscensionSuiteWishlistPanelRow1
assert(row1 and row1:IsShown(), "rows render outside Wildcard")
row1._scripts.OnClick(row1, "LeftButton")
assert(Panel.GetSelectedKey() ~= nil, "left-click selects a row outside Wildcard")
assert(row1._select and row1._select:IsShown(), "selection highlight is visible")

local blocked = Panel.GetPushBlockReason()
assert(blocked and blocked:find("Wildcard"), "Push tooltip says why Desired is blocked, got " .. tostring(blocked))

pushButton:Click()
assert(Wishlist.CountDesired() == 0, "Push outside Wildcard marks nothing")

wildcard = true
Panel.Refresh()
row1._scripts.OnClick(row1, "RightButton")
assert(Wishlist.CountDesired() >= 1, "right-click toggles Desired in Wildcard")

------------------------------------------------------------------------
-- Push to Desired (Wildcard)
------------------------------------------------------------------------

pushButton:Click()
assert(Wishlist.CountDesired() == 12, "every row is pushed to Desired")

local rows = Panel.GetFilteredRows()
assert(rows[1].desired, "and the rows report the badge")

------------------------------------------------------------------------
-- Push merges rather than replacing
------------------------------------------------------------------------

local pushed, already, failed = Wishlist.PushToDesired()
assert(pushed == 0 and already == 12 and failed == 0,
    "a second push adds nothing and un-marks nothing")

desired = {}
Wishlist.PushToDesired()
assert(Wishlist.CountDesired() == 12, "and it re-marks a Desired set the player cleared")

------------------------------------------------------------------------
-- A row that was just touched is lit, and goes out on its own
------------------------------------------------------------------------

Panel.Refresh()
local touchTarget = Panel.GetFilteredRows()[3]
assert(Panel.NoteTouched(touchTarget.entryId, touchTarget.entryType, touchTarget.spellId),
    "an edit from anywhere can light its row")
Panel.Refresh()

local lit = 0
for index = 1, 8 do
    local row = _G["AscensionSuiteWishlistPanelRow" .. index]
    if row and row._touch and row._touch:IsShown() then
        lit = lit + 1
        assert(row._nameLabel:GetText() == touchTarget.name, "the lit row is the one that was touched")
    end
end
assert(lit == 1, "exactly one row is lit (got " .. lit .. ")")

clock = clock + 30
Panel.Refresh()
for index = 1, 8 do
    local row = _G["AscensionSuiteWishlistPanelRow" .. index]
    assert(not (row and row._touch and row._touch:IsShown()), "the highlight expires by itself")
end

------------------------------------------------------------------------
-- Removing a row touches the wishlist only
------------------------------------------------------------------------

local removeButton = _G.AscensionSuiteWishlistPanelRow1Remove
local removedName = row1._nameLabel:GetText()
removeButton:Click()
assert(Wishlist.Count() == 11, "the row is gone from the wishlist")
for _, row in ipairs(Panel.GetFilteredRows()) do
    assert(row.name ~= removedName, "and gone from the list")
end
assert(Wishlist.CountDesired() == 11,
    "Ascension keeps its own Desired mark; only the wishlist row was removed")

clearButton:Click()
assert(Wishlist.Count() == 0, "Clear list empties the wishlist")
assert(#Panel.GetFilteredRows() == 0, "and the panel")
assert(pushButton._enabled == false, "with nothing to push")

print("OK: AscensionSuite wishlist panel test passed")
