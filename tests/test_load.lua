-- AscensionSuite: tests/test_load.lua
-- Minimal stub environment; loads every shipped Lua file in TOC order.

unpack = unpack or table.unpack

local ADDON_NAME = "AscensionSuite"

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

AscensionSuite = AscensionSuite or {}
AscensionSuiteDB = AscensionSuiteDB or {}

local function Noop() end

local function NewFrame()
    local frame = {
        _scripts = {},
        _shown = false,
        _width = 64,
        _height = 64,
        _points = {},
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
        elseif key == "EnableMouse" or key == "RegisterForDrag" or key == "SetMovable"
            or key == "StartMoving" or key == "StopMovingOrSizing" or key == "ClearAllPoints"
            or key == "SetPoint" or key == "SetAutoFocus" or key == "ClearFocus"
            or key == "SetNumeric" or key == "SetMaxLetters" or key == "SetTexCoord"
            or key == "SetJustifyH" or key == "SetTextColor" then
            return Noop
        elseif key == "SetBackdrop" then
            return Noop
        elseif key == "CreateTexture" then
            return function()
                return {
                    SetAllPoints = Noop,
                    SetPoint = Noop,
                    SetTexture = Noop,
                    SetTexCoord = Noop,
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
        elseif key == "SetText" then
            return function(self, value) self._text = value end
        elseif key == "GetText" then
            return function(self) return self._text or "" end
        elseif key == "SetOwner" or key == "ClearLines" or key == "AddLine" then
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
    return frame
end

UIParent = NewFrame()
GameTooltip = NewFrame()

SLASH_ASUITE1 = nil
SlashCmdList = SlashCmdList or {}

function GetSpellInfo(spellId)
    return "Test Spell " .. tostring(spellId), "Rank 1", nil, "10 Mana", nil, nil, 1500, 0, 30
end

C_CharacterAdvancement = {
    GetEntryBySpellID = function(_, id)
        return {
            Name = "CA Entry " .. tostring(id),
            Icon = "Interface\\Icons\\Spell_Nature_Lightning",
            Description = "From C_CharacterAdvancement",
            Type = "Talent",
        }
    end,
}

local files = {
    "core/Bootstrap.lua",
    "core/Database.lua",
    "integration/AscensionAPI.lua",
    "ui/SpellCell.lua",
    "ui/MainWindow.lua",
}

for index = 1, #files do
    local path = ROOT .. "/" .. files[index]
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk(ADDON_NAME)
end

local API = AscensionSuite.AscensionAPI
assert(API, "AscensionAPI missing")
assert(API.GetEntryIcon(133):find("Icons"), "GetEntryIcon failed")
assert(API.GetEntryName(133):find("CA Entry"), "GetEntryName failed")
assert(#API.GetEntryTooltipLines(133) > 0, "GetEntryTooltipLines failed")

AscensionSuite.Database.Init()
assert(AscensionSuiteDB.assists.autoRoll == false, "autoRoll must default false")

local cell = AscensionSuite.SpellCell.Create(UIParent, "TestCell")
cell:SetSpell(133)
assert(cell:GetSpellId() == 133, "SpellCell spell id")

AscensionSuite.MainWindow.RegisterSlash()
assert(type(SlashCmdList.ASUITE) == "function", "slash handler missing")

print("OK: AscensionSuite load smoke test passed")
