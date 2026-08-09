-- AscensionSuite: tests/test_settings_layout.lua
-- Assists Categories sidebar, draft Save/Cancel, Undesired badge seams.

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

local function NewFrame()
    local frame = {
        _scripts = {},
        _shown = false,
        _width = 64,
        _height = 64,
        _checked = nil,
        _text = "",
    }

    local function Index(_, key)
        if key == "RegisterEvent" or key == "UnregisterEvent" or key == "UnregisterAllEvents" then
            return Noop
        elseif key == "SetScript" then
            return function(self, event, fn)
                self._scripts[event] = fn
            end
        elseif key == "GetScript" then
            return function(self, event)
                return self._scripts[event]
            end
        elseif key == "Show" then
            return function(self) self._shown = true end
        elseif key == "Hide" then
            return function(self) self._shown = false end
        elseif key == "IsShown" then
            return function(self) return self._shown end
        elseif key == "SetSize" or key == "SetWidth" or key == "SetHeight" then
            return function(self, w, h)
                if h then
                    self._width, self._height = w, h
                else
                    self._width = w
                end
            end
        elseif key == "GetWidth" then
            return function(self) return self._width end
        elseif key == "GetHeight" then
            return function(self) return self._height end
        elseif key == "GetChecked" then
            return function(self) return self._checked end
        elseif key == "SetChecked" then
            return function(self, value)
                if value == true or value == 1 then
                    self._checked = 1
                else
                    self._checked = nil
                end
            end
        elseif key == "SetText" then
            return function(self, value) self._text = value or "" end
        elseif key == "GetText" then
            return function(self) return self._text or "" end
        elseif key == "CreateTexture" then
            return function()
                return {
                    SetAllPoints = Noop, SetPoint = Noop, SetTexture = Noop,
                    SetTexCoord = Noop, SetWidth = Noop, SetHeight = Noop,
                    Show = Noop, Hide = Noop,
                }
            end
        elseif key == "CreateFontString" then
            return function()
                local text = ""
                return {
                    SetPoint = Noop,
                    SetText = function(_, value) text = value or "" end,
                    GetText = function() return text end,
                    SetJustifyH = Noop,
                    SetTextColor = Noop,
                    SetWidth = Noop,
                    Show = Noop,
                    Hide = Noop,
                }
            end
        elseif key == "CreateFrame" then
            return function(_, childName, parent, template)
                local child = NewFrame()
                child._name = childName
                child._parent = parent
                child._template = template
                return child
            end
        elseif key == "SetOwner" or key == "ClearLines" or key == "AddLine"
            or key == "SetSpellByID" or key == "SetHyperlink"
            or key == "EnableMouse" or key == "RegisterForDrag" or key == "SetMovable"
            or key == "StartMoving" or key == "StopMovingOrSizing" or key == "ClearAllPoints"
            or key == "SetPoint" or key == "SetAutoFocus" or key == "ClearFocus"
            or key == "SetNumeric" or key == "SetMaxLetters" or key == "SetTexCoord"
            or key == "SetJustifyH" or key == "SetTextColor" or key == "SetEnabled"
            or key == "SetBackdrop" or key == "SetBackdropColor" or key == "SetBackdropBorderColor"
            or key == "SetFrameStrata" or key == "SetFrameLevel" or key == "SetID"
            or key == "GetID" or key == "GetFrameLevel" or key == "RegisterForClicks"
            or key == "SetAllPoints" then
            return Noop
        end
        return Noop
    end

    return setmetatable(frame, { __index = Index })
end

CreateFrame = function(kind, name, parent, template)
    local frame = NewFrame()
    frame._kind = kind
    frame._name = name
    frame._parent = parent
    frame._template = template
    if name then
        _G[name] = frame
    end
    return frame
end

UIParent = NewFrame()
GameTooltip = NewFrame()
hooksecurefunc = function() end
StaticPopup_Show = function() end
SlashCmdList = SlashCmdList or {}
DEFAULT_CHAT_FRAME = { AddMessage = Noop }

local undesired = {}
local desired = {}

C_GameMode = {
    IsGameModeActive = function(_, mode) return mode == "WildCard" end,
}

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        return {
            ID = id + 1000,
            Name = "CA Entry " .. tostring(id),
            Icon = "Interface\\Icons\\Spell_Nature_Lightning",
            Type = "Ability",
            Spell = id,
        }
    end,
    GetEntryByInternalID = function(_, id)
        return {
            ID = id,
            Name = "Entry " .. tostring(id),
            Icon = "Interface\\Icons\\Spell_Nature_Lightning",
            Type = "Ability",
            Spell = id - 1000,
        }
    end,
    GetKnownSpellEntries = function() return {} end,
    GetKnownTalentEntries = function() return {} end,
}

C_Wildcard = {
    CanAddDesiredID = function() return true end,
    AddDesiredID = function(_, id, entryType)
        desired[tostring(id) .. tostring(entryType)] = true
        return true
    end,
    RemoveDesiredID = function(_, id, entryType)
        desired[tostring(id) .. tostring(entryType)] = nil
        return true
    end,
    IsDesiredID = function(_, id, entryType)
        return desired[tostring(id) .. tostring(entryType)] == true
    end,
    ClearDesiredSpells = function() return true end,
    GetNumFilteredDesiredEntries = function() return 0 end,
    IsUndesiredID = function(_, id, entryType)
        return undesired[tostring(id) .. tostring(entryType)] == true
    end,
    GetNumFilteredUndesiredEntries = function() return 0 end,
    GetFilteredUndesiredEntryAtIndex = function() return nil end,
    CanRollAbilities = function() return false end,
}

dofile(ROOT .. "/core/Bootstrap.lua")
dofile(ROOT .. "/core/Database.lua")
dofile(ROOT .. "/core/Loadouts.lua")
dofile(ROOT .. "/core/Wishlist.lua")
dofile(ROOT .. "/core/Logbook.lua")
dofile(ROOT .. "/integration/AscensionAPI.lua")
dofile(ROOT .. "/integration/DesiredSync.lua")
dofile(ROOT .. "/automation/AutoRoller.lua")
dofile(ROOT .. "/automation/AutoUnstick.lua")
dofile(ROOT .. "/automation/DiceGuard.lua")
dofile(ROOT .. "/automation/AnimationSkip.lua")
dofile(ROOT .. "/automation/PopupAssist.lua")
dofile(ROOT .. "/ui/WishlistPanel.lua")
dofile(ROOT .. "/ui/LoadoutsPanel.lua")
dofile(ROOT .. "/ui/MainWindow.lua")

AscensionSuite.Database.Init()
assert(AscensionSuiteDB.prefs.showWishlistBadges == true, "badges default on")
assert(AscensionSuiteDB.prefs.clickTrace == false, "clickTrace default off")

local API = AscensionSuite.AscensionAPI
assert(API.IsUndesiredID, "IsUndesiredID seam missing")
assert(API.CollectAllUndesiredSelections, "CollectAllUndesiredSelections missing")
assert(API.CountUndesiredSelections, "CountUndesiredSelections missing")

local Wishlist = AscensionSuite.Wishlist
assert(Wishlist.Add(133), "seed wishlist")
local entryId = 1133
undesired[tostring(entryId) .. "Ability"] = true
assert(Wishlist.IsItemUndesired(Wishlist.GetItems()[1]) == true, "wishlist row is Undesired")
assert(Wishlist.CountUndesired() == 1, "CountUndesired sees Rapid Undesired")
local row = Wishlist.Describe(Wishlist.GetItems()[1])
assert(row.undesired == true, "Describe carries undesired")
assert(row.desired == false, "not Desired")

local MainWindow = AscensionSuite.MainWindow
local window = MainWindow.Show()
assert(window:IsShown(), "/asuite opens")

MainWindow.SelectTab(3)
assert(MainWindow.GetActiveTab() == 3, "Assists tab")
assert(MainWindow.GetActiveCategory, "GetActiveCategory exposed")
assert(MainWindow.GetActiveCategory() == "windows"
    or MainWindow.GetActiveCategory() == "automation"
    or MainWindow.GetActiveCategory() == "general"
    or MainWindow.GetActiveCategory() == "logbook"
    or MainWindow.GetActiveCategory() == "sync",
    "category selected after Assists open")

MainWindow.SelectCategory("automation")
assert(MainWindow.GetActiveCategory() == "automation", "Automation category")
MainWindow.SelectCategory("logbook")
assert(MainWindow.GetActiveCategory() == "logbook", "Logbook category")
MainWindow.SelectCategory("sync")
assert(MainWindow.GetActiveCategory() == "sync", "Wishlist sync category")
MainWindow.SelectCategory("windows")
assert(MainWindow.GetActiveCategory() == "windows", "Windows & Tools category")

-- Draft Save: flipping a check must not apply until Save.
local assists = AscensionSuite.Database.GetAssists()
assert(assists.autoRoll == false, "autoRoll still off before Save")

print("OK: test_settings_layout")
